import {createHash, randomBytes, randomUUID} from 'node:crypto';
import {urlencoded} from 'express';
import {BUCKET, FieldProofError, uuid} from './model.mjs';
import {createFieldProofEmailProvider} from './email_provider.mjs';
import {renderFieldProofCustomerEmail} from './email_report.mjs';

export const FIELDPROOF_EMAIL_BUCKET = 'korlix-fieldproof-mail';
export const FIELDPROOF_EMAIL_DEFAULTS = Object.freeze({
  version: 0, business_name: '', customer_mode: 'off', followup_mode: 'off', followup_days: 3,
  supervisor_mode: 'off', supervisor_emails: [], timezone: 'America/New_York', summary_time: '17:00',
  summary_days: [1, 2, 3, 4, 5], include_photos: false, daily_limit: 25, paused: false,
});
const BASE = '/api/fieldproof/email';
const MAX_PDF = 5 * 1024 * 1024;
const RETRY_WINDOW = 23 * 60 * 60 * 1000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const WAITING = new Set(['pending', 'preparing', 'draft', 'ready', 'retry']);
const MODES = new Set(['off', 'draft', 'automatic']);
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const escapeHtml = value => String(value).replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
const oneLine = (value, max = 200) => String(value || '').replace(/[\u0000-\u001f\u007f]+/g, ' ').trim().slice(0, max);
class EmailError extends FieldProofError {
  constructor(message, status = 400, code = 'fieldproof_email_invalid') { super(message, status); this.code = code; }
}
const fail = (message, status, code) => { throw new EmailError(message, status, code); };
const safeCode = code => typeof code === 'string' && /^[a-z][a-z0-9_]{0,99}$/.test(code) ? code : 'fieldproof_email_unavailable';
function object(value, allowed) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(k => !allowed.includes(k))) fail('Refresh FieldProof and review these email settings.');
  return value;
}
function email(value, optional = false) {
  if (typeof value !== 'string') fail('Enter a valid email address.');
  const s = value.trim().toLowerCase();
  if (!s && optional) return '';
  const m = /^([a-z0-9!#$%&'*+\-/=?^_`{|}~.]+)@([a-z0-9.-]+)$/.exec(s);
  if (s.length > 254 || !m || m[1].length > 64 || m[1].startsWith('.') || m[1].endsWith('.') || m[1].includes('..') || m[2].split('.').length < 2 || m[2].split('.').some(p => !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(p)) || !/[a-z]/.test(m[2].split('.').at(-1))) fail('Enter one valid email address per recipient.');
  return s;
}
function revision(value) {
  if (!Number.isSafeInteger(value) || value < 0) fail('Refresh these email settings before saving.', 409, 'fieldproof_email_conflict');
  return value;
}
function confirmed(body) {
  if (body?.confirmed !== true) fail('Confirm this email action before continuing.');
}
export function normalizeFieldProofEmailSettings(input) {
  object(input, Object.keys(FIELDPROOF_EMAIL_DEFAULTS).filter(k => k !== 'version'));
  const s = {...FIELDPROOF_EMAIL_DEFAULTS, ...input}; delete s.version;
  if (typeof s.business_name !== 'string' || s.business_name.trim().length > 120 || /[\u0000-\u001f\u007f]/.test(s.business_name)) fail('Use a business name of up to 120 characters.');
  s.business_name = s.business_name.trim();
  for (const k of ['customer_mode', 'followup_mode', 'supervisor_mode']) if (!MODES.has(s[k])) fail('Choose Off, Review drafts, or Automatic for each email type.');
  if (!Number.isInteger(s.followup_days) || s.followup_days < 1 || s.followup_days > 30) fail('Choose a follow-up delay from 1 to 30 days.');
  if (!Number.isInteger(s.daily_limit) || s.daily_limit < 1 || s.daily_limit > 100) fail('Choose a daily email limit from 1 to 100.');
  if (!Array.isArray(s.supervisor_emails) || s.supervisor_emails.length > 5) fail('Add at most five supervisor email addresses.');
  s.supervisor_emails = [...new Set(s.supervisor_emails.map(v => email(v)))];
  if (s.supervisor_mode !== 'off' && !s.supervisor_emails.length) fail('Add a supervisor email address before enabling summaries.');
  if (typeof s.timezone !== 'string' || s.timezone.length > 100) fail('Choose a valid time zone.');
  try { new Intl.DateTimeFormat('en', {timeZone: s.timezone}).format(); } catch { fail('Choose a valid time zone.'); }
  if (typeof s.summary_time !== 'string' || !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(s.summary_time)) fail('Choose a valid daily summary time.');
  if (!Array.isArray(s.summary_days) || !s.summary_days.length || s.summary_days.length > 7 || s.summary_days.some(d => !Number.isInteger(d) || d < 0 || d > 6)) fail('Choose the days to send supervisor summaries.');
  s.summary_days = [...new Set(s.summary_days)].sort((a, b) => a - b);
  for (const k of ['paused', 'include_photos']) if (typeof s[k] !== 'boolean') fail('Choose the pause and photo-sharing settings.');
  return s;
}

// Calendar boundaries use the selected IANA zone. A local day can be 23 or 25
// hours; subtracting 24 UTC hours would include the wrong closeouts around DST.
const formatters = new Map();
function localParts(instant, timezone) {
  let fmt = formatters.get(timezone);
  if (!fmt) {
    fmt = new Intl.DateTimeFormat('en-CA', {timeZone: timezone, calendar: 'gregory', numberingSystem: 'latn', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23'});
    if (formatters.size >= 100) formatters.clear(); formatters.set(timezone, fmt);
  }
  const p = Object.fromEntries(fmt.formatToParts(instant).map(p => [p.type, p.value]));
  return {date: `${p.year}-${p.month}-${p.day}`, minute: Number(p.hour) * 60 + Number(p.minute)};
}
const priorDate = day => new Date(Date.parse(day + 'T12:00:00Z') - 86400000).toISOString().slice(0, 10);
const nextDate = day => new Date(Date.parse(day + 'T12:00:00Z') + 86400000).toISOString().slice(0, 10);
function dayBoundary(day, timezone) {
  const middle = Date.parse(day + 'T12:00:00Z'); let lo = middle - 48 * 3600000, hi = middle + 48 * 3600000;
  while (lo < hi) { const mid = Math.floor((lo + hi) / 2); if (localParts(mid, timezone).date < day) lo = mid + 1; else hi = mid; }
  return lo;
}
export function fieldProofSummaryWindow(settings, now = new Date()) {
  if (settings.paused || settings.supervisor_mode === 'off') return null;
  const current = localParts(now, settings.timezone), weekday = new Date(current.date + 'T12:00:00Z').getUTCDay();
  if (!settings.summary_days.includes(weekday)) return null;
  const [hour, minute] = settings.summary_time.split(':').map(Number), wanted = hour * 60 + minute;
  if (current.minute < wanted) return null;
  const reportDate = priorDate(current.date), start = dayBoundary(reportDate, settings.timezone), end = dayBoundary(current.date, settings.timezone), expires = dayBoundary(nextDate(current.date), settings.timezone);
  // Scan actual minutes so repeated clock times choose their first occurrence
  // and a nonexistent spring-forward time becomes the first later local minute.
  let scheduled = end;
  while (scheduled < expires && localParts(scheduled, settings.timezone).minute < wanted) scheduled += 60000;
  const deadline = Math.min(expires, scheduled + 6 * 3600000);
  if (new Date(now).getTime() < scheduled || new Date(now).getTime() >= deadline || start === end) return null;
  return {event_key: `supervisor:${current.date}`, report_date: reportDate, period_start: new Date(start).toISOString(), period_end: new Date(end).toISOString(), scheduled_at: new Date(scheduled).toISOString(), expires_at: new Date(deadline).toISOString()};
}

export function renderFieldProofSupervisorSummary({jobs, delivery, settings, now = new Date()}) {
  if (!Array.isArray(jobs) || jobs.length > 200) fail('The summary could not load the saved job list.', 503, 'fieldproof_email_summary_unavailable');
  jobs = jobs.filter(job => job.state !== 'deleting');
  const start = Date.parse(delivery.period_start), end = Date.parse(delivery.period_end);
  if (!Number.isFinite(start) || !Number.isFinite(end) || start >= end || end - start > 27 * 3600000) fail('This summary period is invalid.', 409, 'fieldproof_email_summary_period_invalid');
  const today = localParts(now, settings.timezone).date;
  const completed = jobs.filter(j => j.state === 'completed' && Date.parse(j.completion?.completedAt) >= start && Date.parse(j.completion?.completedAt) < end);
  const overdue = jobs.filter(j => j.state === 'active' && j.data?.dueOn && j.data.dueOn < today);
  const withIssues = jobs.filter(j => (j.data?.issues || []).some(i => i.resolved !== true));
  const label = j => `${oneLine(j.data?.title, 120) || 'Untitled job'}${j.data?.workOrder ? ' | Work order ' + oneLine(j.data.workOrder, 100) : ''}${j.data?.technician ? ' | ' + oneLine(j.data.technician, 120) : ''}`;
  const sections = [
    ['Completed in the previous local calendar day', completed.length ? completed.map(j => label(j)) : ['No currently completed jobs have a closeout timestamp in this period.']],
    ['Currently overdue jobs', overdue.length ? overdue.map(j => `${label(j)} | Due ${oneLine(j.data.dueOn, 10)}`) : ['No active jobs are currently past their entered due date.']],
    ['Currently unresolved punch-list items', withIssues.length ? withIssues.map(j => {
      const open = j.data.issues.filter(i => i.resolved !== true);
      return `${label(j)} | ${open.length} open: ${open.slice(0, 2).map(i => oneLine(i.label, 160)).join('; ')}${open.length > 2 ? `; plus ${open.length - 2} more` : ''}`;
    }) : ['No unresolved punch-list items are recorded.']],
  ];
  const intro = `${oneLine(settings.business_name, 120) || 'Your business'} — FieldProof summary for ${delivery.report_date} (${settings.timezone})`;
  const note = `Period: ${delivery.period_start} to ${delivery.period_end} (end excluded). Overdue and unresolved items reflect the saved records at ${new Date(now).toISOString()}. Reopened or deleted jobs are not counted as completed. All records are technician-entered; this summary does not certify work quality.`;
  const text = [intro, `Completed: ${completed.length} | Currently overdue: ${overdue.length} | Jobs with open items: ${withIssues.length}`, note, ...sections.flatMap(([heading, lines]) => ['', heading, ...lines])].join('\n');
  if (Buffer.byteLength(text) > 120000) fail('This summary is too large to email.', 422, 'fieldproof_email_summary_too_large');
  return {subject: oneLine(`FieldProof daily summary — ${delivery.report_date}`, 150), text, html: `<html><body style="font-family:Arial,sans-serif;color:#16324a"><h1>${escapeHtml(intro)}</h1><p>${escapeHtml(note)}</p>${sections.map(([heading, lines]) => `<h2>${escapeHtml(heading)}</h2><ul>${lines.map(line => `<li>${escapeHtml(line)}</li>`).join('')}</ul>`).join('')}</body></html>`};
}

function publicDelivery(row, now, detail = false) {
  if (!row) return null;
  const inWindow = !row.first_attempt_at || new Date(now).getTime() - Date.parse(row.first_attempt_at) < RETRY_WINDOW;
  const result = Object.fromEntries(['id', 'version', 'kind', 'job_id', 'subject', 'recipient', 'state', 'created_at', 'scheduled_at', 'accepted_at', 'code'].map(k => [k, row[k] ?? null]));
  result.can_approve = row.state === 'draft'; result.can_cancel = WAITING.has(row.state);
  result.can_retry = ['failed', 'retry', 'unknown'].includes(row.state) && !!row.payload && !!row.first_attempt_at && inWindow && (row.attempt_count || 0) < 8;
  result.has_report = !!row.attachment_path;
  if (detail) {
    // Unsubscribe tokens stay in the persisted provider payload, never in an
    // account API preview. Original evidence paths are never included at all.
    result.text = String(row.payload?.text || '').split('\n\nManage FieldProof emails:')[0];
    result.html = String(row.payload?.html || '').replace(/<!--fieldproof-unsubscribe-->[\s\S]*?<!--\/fieldproof-unsubscribe-->/g, '');
  }
  return result;
}
function timeout(promise, ms = 20000) {
  let timer;
  return Promise.race([promise, new Promise((_, reject) => { timer = setTimeout(() => reject(new EmailError('FieldProof email storage did not respond in time.', 503, 'fieldproof_email_timeout')), ms); timer.unref?.(); })]).finally(() => clearTimeout(timer));
}

export function createFieldProofEmails({database, storageDatabase = database, requireUser, environment = process.env, provider = createFieldProofEmailProvider({environment}), renderer = renderFieldProofCustomerEmail, now = () => new Date(), autoStart = true, logger = console, publicRoot = environment.FIELDPROOF_EMAIL_PUBLIC_ROOT || environment.PUBLIC_BASE_URL || 'https://chee-chai-chee-backend.onrender.com'} = {}) {
  let busy = false, stopped = false, timer = null, lastCleanup = 0;
  let publicUrl;
  try { const u = new URL(publicRoot); if (u.protocol !== 'https:' || u.username || u.password || u.search || u.hash || !['', '/'].includes(u.pathname)) throw Error(); publicUrl = u.origin; } catch {}
  const call = async (actor, action, id = null, data = {}, name = 'korlix_fieldproof_email_v1') => {
    if (!database?.rpc) fail('FieldProof email storage is unavailable.', 503, 'fieldproof_email_unavailable');
    const result = await timeout(database.rpc(name, {p_actor: actor, p_action: action, p_id: id, p_data: data}));
    if (result.error) {
      const status = {P0002: 404, '40001': 409, '54000': 429, P0001: 400, '22023': 400, '22P02': 400, '23514': 400, '42501': 403}[result.error.code];
      if (status) fail(oneLine(result.error.message, 300), status, status === 409 ? 'fieldproof_email_conflict' : 'fieldproof_email_invalid');
      logger.warn('FieldProof email storage unavailable', {action, code: safeCode(result.error.code)});
      fail('FieldProof email storage is temporarily unavailable. Refresh before retrying.', 503, 'fieldproof_email_unavailable');
    }
    return result.data;
  };
  const jobsCall = (actor, action, id = null) => call(actor, action, id, {}, 'korlix_fieldproof_v1');
  const verifiedIdentity = async owner => {
    if (!database?.auth?.admin?.getUserById) fail('The account verification service is unavailable.', 503, 'fieldproof_email_identity_unavailable');
    const result = await timeout(database.auth.admin.getUserById(owner)); const user = result.data?.user;
    if (result.error || !user || user.id !== owner || user.deleted_at || user.is_anonymous || !user.email_confirmed_at || (user.banned_until && Date.parse(user.banned_until) > new Date(now()).getTime())) fail('Verify this account email before enabling FieldProof delivery.', 403, 'fieldproof_email_identity_unverified');
    try { return {replyTo: email(user.email)}; } catch { fail('Verify a valid account email before enabling FieldProof delivery.', 403, 'fieldproof_email_identity_unverified'); }
  };
  const capabilities = async owner => {
    const status = provider.status(); let identity = null, reason = status.ready ? null : status.reason;
    try { identity = await verifiedIdentity(owner); } catch (e) { reason = e.code; }
    if (!publicUrl) reason = 'fieldproof_email_public_url_unavailable';
    const messages = {
      provider_key_unavailable: 'Email delivery is being configured. You can save settings and review drafts.',
      sender_unavailable: 'The business email sender is being configured. Delivery will remain off until it is ready.',
      transport_unavailable: 'Email delivery is temporarily unavailable.',
      fieldproof_email_identity_unavailable: 'Your account email could not be verified right now. Try again shortly.',
      fieldproof_email_identity_unverified: 'Verify your account email before enabling FieldProof email delivery.',
      fieldproof_email_public_url_unavailable: 'Email preference links are being configured. Delivery will remain off until they are ready.',
    };
    return {ready: !!identity && status.ready && !!publicUrl, reason: reason ? messages[reason] || 'Email delivery is temporarily unavailable. Try again shortly.' : null, reason_code: reason || null, sender_label: 'KORLIX FieldProof', reply_to: identity?.replyTo || null, daily_limit_max: 100};
  };
  const mailObjects = () => storageDatabase.storage.from(FIELDPROOF_EMAIL_BUCKET);
  const download = async (bucket, path, digest, expectedBytes, maxBytes) => {
    if (typeof digest !== 'string' || !/^[a-f0-9]{64}$/.test(digest) || !Number.isSafeInteger(expectedBytes) || expectedBytes < 1 || expectedBytes > maxBytes) fail('The saved attachment metadata is invalid.', 409, 'fieldproof_email_attachment_invalid');
    const result = await timeout(storageDatabase.storage.from(bucket).download(path));
    if (result.error || !result.data) fail('The saved report or photo could not be downloaded. Nothing was sent.', 503, 'fieldproof_email_attachment_unavailable');
    if (result.data.size != null && result.data.size !== expectedBytes) fail('The saved attachment failed its integrity check.', 409, 'fieldproof_email_attachment_integrity');
    const bytes = Buffer.from(await timeout(result.data.arrayBuffer()));
    if (bytes.length !== expectedBytes || sha(bytes) !== digest) fail('The saved attachment failed its integrity check.', 409, 'fieldproof_email_attachment_integrity');
    return bytes;
  };
  const pathFor = row => `${row.owner_id}/${row.id}/report.pdf`;
  const reportBytes = async row => {
    const a = row.payload?.attachment;
    if (!a || a.path !== pathFor(row) || row.attachment_path !== a.path || row.attachment_sha256 !== a.sha256 || row.attachment_bytes !== a.bytes) fail('The saved report does not match this delivery.', 409, 'fieldproof_email_attachment_invalid');
    return download(FIELDPROOF_EMAIL_BUCKET, a.path, a.sha256, a.bytes, MAX_PDF);
  };
  const ownedDelivery = async (owner, id) => {
    const row = await call(owner, 'delivery', id);
    if (!row || row.owner_id !== owner || row.id !== id) fail('This email report was not found.', 404, 'fieldproof_email_not_found');
    return row;
  };
  const finish = (row, lease, data) => call(row.owner_id, 'finish', row.id, {lease_token: lease, ...data});
  const state = async owner => {
    const data = await call(owner, 'state');
    return {settings: Object.fromEntries(Object.keys(FIELDPROOF_EMAIL_DEFAULTS).map(k => [k, k === 'summary_time' ? String(data.settings?.[k] || FIELDPROOF_EMAIL_DEFAULTS[k]).slice(0, 5) : data.settings?.[k] ?? FIELDPROOF_EMAIL_DEFAULTS[k]])), capabilities: await capabilities(owner), queue_notice: data.queue_notice === 'queue_full' ? 'FieldProof email history is full. Some new reports were not queued. Review recent jobs and prepare a draft after space is available.' : null, deliveries: (data.deliveries || []).map(d => publicDelivery(d, now()))};
  };
  const jobState = async (owner, id) => {
    const data = await call(owner, 'job_state', id);
    return {job_settings: Object.fromEntries(['version', 'customer_email', 'enabled'].map(k => [k, data.job_settings?.[k] ?? ({version: 0, customer_email: '', enabled: false})[k]])), deliveries: (data.deliveries || []).map(d => publicDelivery(d, now()))};
  };
  const unsubFooter = async row => {
    if (!publicUrl) fail('Email links are not configured.', 503, 'fieldproof_email_public_url_unavailable');
    const token = randomBytes(32).toString('base64url');
    const entry = await call(row.owner_id, 'recipient_token', row.id, {recipient: row.recipient, token_hash: sha(token)});
    if (entry?.suppressed) fail('This recipient has stopped FieldProof emails.', 409, 'fieldproof_email_recipient_suppressed');
    const link = `${publicUrl}${BASE}/unsubscribe?token=${token}`;
    return {text: `\n\nManage FieldProof emails: ${link}\nYou can stop these job reports and updates for this business.`, html: `<!--fieldproof-unsubscribe--><p style="font-size:12px;color:#526574"><a href="${escapeHtml(link)}">Stop FieldProof emails for this business</a></p><!--/fieldproof-unsubscribe-->`};
  };
  const prepare = async (row, lease) => {
    const deadline = Date.now() + 170000;
    const step = (run, limit = 20000) => {
      const remaining = deadline - Date.now();
      if (remaining <= 0) fail('The report took too long to prepare. Please prepare a new draft.', 503, 'fieldproof_email_prepare_timeout');
      return timeout(run(), Math.min(remaining, limit));
    };
    const identity = await step(() => verifiedIdentity(row.owner_id)), configuration = await step(() => call(row.owner_id, 'state')), settings = configuration.settings;
    let content, attachment = null;
    if (row.kind === 'supervisor_summary') {
      content = renderFieldProofSupervisorSummary({jobs: await step(() => jobsCall(row.owner_id, 'list')), delivery: row, settings, now: now()});
    } else {
      const snapshot = await step(() => jobsCall(row.owner_id, 'job_get', row.job_id));
      if (!snapshot?.job || snapshot.job.id !== row.job_id || (snapshot.job.user_id && snapshot.job.user_id !== row.owner_id) || snapshot.job.version !== row.job_version || snapshot.job.state !== 'completed') fail('This job changed after the email was queued.', 409, 'fieldproof_email_job_changed');
      snapshot.snapshotAt = row.created_at;
      if (row.kind === 'customer_followup') {
        const title = oneLine(snapshot.job.data.title, 120), business = oneLine(settings.business_name, 120) || 'Your service provider';
        const text = `${business} is following up about “${title}”.\n\nYour service provider marked this job complete on ${oneLine(snapshot.job.completion?.completedAt, 40) || 'the recorded closeout date'}. If you have questions or an outstanding concern, reply to this email to contact the business.\n\nThis is a single service follow-up from the saved job record. It does not verify the work or require a payment.`;
        content = {subject: oneLine(`Following up: ${title}`, 150), text, html: `<html><body><p style="white-space:pre-wrap">${escapeHtml(text)}</p></body></html>`};
      } else if (row.kind === 'customer_report') {
        const previews = new Map(); let total = 0;
        const photos = settings.include_photos ? snapshot.evidence.filter(p => p.state === 'ready').slice(0, 12) : [];
        for (const photo of photos) {
          const prefix = `${row.owner_id}/${row.job_id}/${photo.id}/`;
          if (!UUID.test(photo.id) || photo.preview_path !== prefix + 'preview.jpg' || (photo.user_id && photo.user_id !== row.owner_id) || (photo.job_id && photo.job_id !== row.job_id)) fail('A photo does not belong to this job.', 403, 'fieldproof_email_photo_scope');
          total += photo.preview_bytes; if (total > 8 * 1024 * 1024) fail('The selected photo previews are too large.', 422, 'fieldproof_email_photos_too_large');
        }
        // At most three 20-second downloads at once: twelve photos cannot
        // consume the entire five-minute database lease before rendering.
        for (let i = 0; i < photos.length; i += 3) {
          const batch = await step(() => Promise.all(photos.slice(i, i + 3).map(async photo => [photo.id, await download(BUCKET, photo.preview_path, photo.preview_sha256, photo.preview_bytes, 1024 * 1024)])));
          for (const [id, bytes] of batch) previews.set(id, bytes);
        }
        content = await step(() => renderer({snapshot, previews, includePhotos: settings.include_photos}), 40000);
        const business = oneLine(settings.business_name, 120);
        if (business) {
          content.text = `Report from ${business}\n\n${content.text}`;
          content.html = content.html.replace(/<body([^>]*)>/i, `<body$1><p style="font-family:Arial,sans-serif">Report from ${escapeHtml(business)}</p>`);
        }
        const file = content.attachments?.[0], bytes = file?.content;
        if (content.attachments?.length !== 1 || !Buffer.isBuffer(bytes) || bytes.length < 8 || bytes.length > MAX_PDF || !bytes.subarray(0, 5).equals(Buffer.from('%PDF-'))) fail('The customer report could not be prepared.', 422, 'fieldproof_email_report_invalid');
        attachment = {filename: file.filename, path: pathFor(row), sha256: sha(bytes), bytes: bytes.length};
        const uploaded = await step(() => mailObjects().upload(attachment.path, bytes, {contentType: 'application/pdf', upsert: false, cacheControl: '0'}));
        if (uploaded.error) {
          // A crash can occur after upload but before prepare commits. Reuse
          // only the exact immutable bytes; never replace a prepared report.
          await step(() => download(FIELDPROOF_EMAIL_BUCKET, attachment.path, attachment.sha256, attachment.bytes, MAX_PDF));
        }
      } else fail('This email type is not supported.', 400, 'fieldproof_email_kind_invalid');
    }
    if (typeof content.text !== 'string' || !content.text.trim() || Buffer.byteLength(content.text) > 120000 || typeof content.html !== 'string') fail('The email body could not be prepared.', 422, 'fieldproof_email_body_invalid');
    const footer = await step(() => unsubFooter(row));
    // Escaping many valid job fields can enlarge HTML beyond the provider cap.
    // Keep every fact in the complete plain-text alternative in that case.
    let html = Buffer.byteLength(content.html) <= 120000 ? content.html : '';
    if (html) { html = html.replace(/<\/body>/i, footer.html + '</body>'); if (!html.includes('fieldproof-unsubscribe')) html += footer.html; }
    const payload = {to: row.recipient, subject: content.subject, text: content.text + footer.text, html, replyTo: identity.replyTo, senderFingerprint: provider.status().senderFingerprint || null, ...(attachment ? {attachment} : {})};
    if (Buffer.byteLength(JSON.stringify(payload)) > 190000) payload.html = '';
    return step(() => call(row.owner_id, 'prepare', row.id, {lease_token: lease, payload, subject: payload.subject, attachment_path: attachment?.path || null, attachment_sha256: attachment?.sha256 || null, attachment_bytes: attachment?.bytes || null}));
  };
  const dispatch = async (row, lease) => {
    const identity = await verifiedIdentity(row.owner_id), status = provider.status(), payload = row.payload;
    if (!status.ready) fail('Email delivery is not configured.', 503, 'fieldproof_email_provider_unavailable');
    if (!payload || payload.to !== row.recipient || identity.replyTo !== payload.replyTo || (payload.senderFingerprint || null) !== (status.senderFingerprint || null)) fail('The sender identity changed. Prepare a new report after reviewing settings.', 409, 'fieldproof_email_sender_changed');
    if (row.first_attempt_at && new Date(now()).getTime() - Date.parse(row.first_attempt_at) >= RETRY_WINDOW) { await finish(row, lease, {state: 'unknown', code: 'fieldproof_email_retry_window_expired'}); return; }
    const attachments = payload.attachment ? [{filename: payload.attachment.filename, content: (await reportBytes(row)).toString('base64')}] : [];
    // This is deliberately the last database operation before the provider:
    // pause, recipient suppression, revisions and quota are rechecked atomically.
    const authorized = await call(row.owner_id, 'authorize', row.id, {lease_token: lease});
    if (authorized?.state !== 'sending' || !authorized.first_attempt_at) return;
    try {
      const result = await provider.send({id: row.id, to: payload.to, subject: payload.subject, text: payload.text, html: payload.html, attachments, replyTo: payload.replyTo});
      if (!result?.accepted || !result.providerId) throw Object.assign(Error('No provider receipt'), {outcome: 'uncertain', code: 'fieldproof_email_receipt_uncertain'});
      await finish(row, lease, {state: 'accepted', code: null, provider_id: result.providerId});
    } catch (error) {
      // A dropped connection is not proof that the provider rejected the mail.
      // Keep that outcome visible; only explicit same-ID replay may reconcile it.
      const uncertain = error.outcome === 'uncertain' || !error.outcome;
      const retry = !uncertain && error.retryable === true;
      try {
        await finish(row, lease, {state: uncertain ? 'unknown' : retry ? 'retry' : 'failed', code: safeCode(error.code), ...(retry ? {retry_at: new Date(new Date(now()).getTime() + Math.max(60, Math.min(3600, error.retryAfterSeconds || 300)) * 1000).toISOString()} : {})});
      } catch (saveError) {
        // The provider may already have accepted this message. Database trouble
        // after a dispatch must never let the outer handler mark it "not sent".
        saveError.outcome = 'uncertain'; throw saveError;
      }
    }
  };
  const processClaim = async (row, lease) => {
    try { if (row.payload) await dispatch(row, lease); else await prepare(row, lease); }
    catch (error) {
      const stale = ['fieldproof_email_job_changed', 'fieldproof_email_recipient_suppressed', 'fieldproof_email_sender_changed'].includes(error.code);
      try { await finish(row, lease, {state: error.outcome === 'uncertain' || row.first_attempt_at ? 'unknown' : stale ? 'cancelled' : 'failed', code: safeCode(error.code)}); } catch { logger.warn('FieldProof email outcome could not be saved', {code: safeCode(error.code)}); }
    }
  };
  const cleanup = async deadline => {
    const rows = await call(null, 'cleanup'), ids = [], gcIds = [];
    for (const row of (rows || []).slice(0, 50)) {
      if (Date.now() >= deadline - 1000) break;
      if (!UUID.test(row.id)) continue;
      if (row.attachment_path) {
        const parts = row.attachment_path.split('/');
        if (parts.length !== 3 || !UUID.test(parts[0]) || !UUID.test(parts[1]) || parts[2] !== 'report.pdf' || (!row.gc && parts[1] !== row.id)) continue;
        const removed = await timeout(mailObjects().remove([row.attachment_path]), Math.min(20000, Math.max(1, deadline - Date.now()))); if (removed.error) continue;
      }
      (row.gc ? gcIds : ids).push(row.id);
    }
    if (ids.length || gcIds.length) await call(null, 'cleanup_done', null, {ids, gc_ids: gcIds});
  };
  const tick = async () => {
    if (busy || stopped) return {skipped: true}; busy = true; let claimed = 0; const deadline = Date.now() + 55000;
    try {
      const accounts = await call(null, 'due_accounts');
      for (const account of (accounts || []).slice(0, 50)) {
        if (Date.now() >= deadline || stopped) break;
        try { const window = fieldProofSummaryWindow(account.settings || account, now()); if (window) await call(account.owner_id, 'enqueue_summary', null, window); }
        catch (error) { logger.warn('FieldProof summary schedule deferred', {code: safeCode(error.code)}); }
      }
      for (; claimed < 4 && Date.now() < deadline && !stopped; claimed++) {
        const lease = randomUUID(), row = await call(null, 'claim', null, {lease_token: lease}); if (!row) break;
        if (!UUID.test(row.owner_id) || !UUID.test(row.id)) break;
        await processClaim(row, lease);
      }
      if (Date.now() < deadline && Date.now() - lastCleanup > 300000) { await cleanup(deadline); lastCleanup = Date.now(); }
      return {claimed};
    } catch (error) { logger.warn('FieldProof email worker deferred', {code: safeCode(error.code)}); return {claimed, deferred: true}; }
    finally { busy = false; }
  };
  const route = fn => async (q, r) => {
    r.set('Cache-Control', 'no-store');
    try { const user = await requireUser(q); if (!user?.id || !UUID.test(user.id)) fail('Sign in to use FieldProof email.', 401, 'fieldproof_email_sign_in'); await fn(q, r, user.id); }
    catch (error) { const status = error instanceof FieldProofError ? error.status : error.statusCode === 401 ? 401 : 503; r.status(status).json({error: error instanceof FieldProofError ? error.message : status === 401 ? 'Sign in again to use FieldProof.' : 'FieldProof could not finish this email request. Refresh before retrying.', code: safeCode(error.code)}); }
  };
  const register = app => {
    app.get(BASE, route(async (_q, r, owner) => r.json(await state(owner))));
    app.put(BASE + '/settings', route(async (q, r, owner) => {
      object(q.body, ['version', 'settings', 'confirmed']); confirmed(q.body); await verifiedIdentity(owner);
      await call(owner, 'save_settings', null, {version: revision(q.body.version), settings: normalizeFieldProofEmailSettings(q.body.settings), confirmed: true}); r.json(await state(owner));
    }));
    app.get(BASE + '/jobs/:jobId', route(async (q, r, owner) => r.json(await jobState(owner, uuid(q.params.jobId)))));
    app.put(BASE + '/jobs/:jobId', route(async (q, r, owner) => {
      object(q.body, ['version', 'job_settings', 'confirmed']); object(q.body.job_settings, ['customer_email', 'enabled']); confirmed(q.body);
      if (typeof q.body.job_settings.enabled !== 'boolean') fail('Choose whether this job may send customer emails.');
      const customer_email = email(q.body.job_settings.customer_email, !q.body.job_settings.enabled); await verifiedIdentity(owner);
      const id = uuid(q.params.jobId); await call(owner, 'save_job', id, {version: revision(q.body.version), job_settings: {customer_email, enabled: q.body.job_settings.enabled}, confirmed: true}); r.json(await jobState(owner, id));
    }));
    app.post(BASE + '/jobs/:jobId/prepare', route(async (q, r, owner) => {
      object(q.body, ['request_key', 'confirmed']); confirmed(q.body); await verifiedIdentity(owner);
      await call(owner, 'prepare_job', uuid(q.params.jobId), {request_key: uuid(q.body.request_key), confirmed: true}); r.status(202).json(await jobState(owner, uuid(q.params.jobId)));
    }));
    app.get(BASE + '/deliveries/:id', route(async (q, r, owner) => r.json({delivery: publicDelivery(await ownedDelivery(owner, uuid(q.params.id)), now(), true)})));
    app.get(BASE + '/deliveries/:id/report', route(async (q, r, owner) => {
      const row = await ownedDelivery(owner, uuid(q.params.id)); if (!row.attachment_path) fail('This email has no prepared PDF report.', 404, 'fieldproof_email_report_not_found');
      const bytes = await reportBytes(row); r.set({'Content-Type': 'application/pdf', 'X-Content-Type-Options': 'nosniff', 'Content-Disposition': `attachment; filename="KORLIX-FieldProof-${row.id}.pdf"`}); r.send(bytes);
    }));
    for (const action of ['approve', 'cancel', 'retry']) app.post(BASE + '/deliveries/:id/' + action, route(async (q, r, owner) => {
      object(q.body, ['version', 'confirmed']); confirmed(q.body); if (action !== 'cancel') await verifiedIdentity(owner);
      const id = uuid(q.params.id); await call(owner, action, id, {version: revision(q.body.version), confirmed: true}); r.json({delivery: publicDelivery(await ownedDelivery(owner, id), now(), true)});
    }));
    const publicHeaders = r => r.set({'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': "default-src 'none'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'; style-src 'unsafe-inline'"});
    app.get(BASE + '/unsubscribe', (q, r) => {
      publicHeaders(r); const token = typeof q.query.token === 'string' && /^[A-Za-z0-9_-]{43}$/.test(q.query.token) ? q.query.token : '';
      r.type('html').send(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>FieldProof email preferences</title></head><body style="font-family:Arial;padding:32px;max-width:560px;margin:auto"><h1>FieldProof email preferences</h1><p>Stop job reports, follow-ups and summaries from this business to this email address.</p>${token ? `<form method="post" action="${BASE}/unsubscribe"><input type="hidden" name="token" value="${token}"><button type="submit">Stop these emails</button></form>` : '<p>Open the preferences link in your FieldProof email.</p>'}</body></html>`);
    });
    app.post(BASE + '/unsubscribe', urlencoded({extended: false, limit: '2kb', parameterLimit: 2}), async (q, r) => {
      publicHeaders(r);
      try { const token = q.body?.token; if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(token)) fail('Open the preferences link in your FieldProof email.'); await call(null, 'unsubscribe', null, {token_hash: sha(token)}); r.type('html').send('<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>FieldProof email preferences</title></head><body><h1>Email preference saved</h1><p>If this link is valid, further FieldProof emails from this business to this address have been stopped.</p></body></html>'); }
      catch { r.status(503).type('html').send('<!doctype html><html><body><h1>Please try again</h1><p>Your email preference could not be saved. Reopen the link and try again shortly.</p></body></html>'); }
    });
    return service;
  };
  const suppressProviderEvent = ({providerId, deliveryId, reason}) => call(null, 'suppress', deliveryId || null, {provider_id: providerId, delivery_id: deliveryId || null, reason});
  const stop = () => { stopped = true; if (timer) clearInterval(timer); timer = null; };
  const service = {register, tick, stop, capabilities, suppressProviderEvent};
  if (autoStart && database?.rpc) { timer = setInterval(() => { void tick(); }, 30000); timer.unref?.(); }
  return service;
}
export function registerFieldProofEmails(app, options) { const service = createFieldProofEmails(options); service.register(app); return service; }
