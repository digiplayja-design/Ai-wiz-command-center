import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID, createHash} from 'node:crypto';
import express from 'express';
import {createFieldProofEmails, FIELDPROOF_EMAIL_DEFAULTS, fieldProofSummaryWindow, normalizeFieldProofEmailSettings, renderFieldProofSupervisorSummary} from '../fieldproof/emails.mjs';
const hash = x => createHash('sha256').update(x).digest('hex');
const pdf = Buffer.from('%PDF-1.7\nfixed fixture\n%%EOF\n');
const clone = x => structuredClone(x);
function fixture(extra = {}) {
  const owner = randomUUID(), other = randomUUID(), jobId = randomUUID();
  const f = {owner, other, jobId, time: new Date('2026-10-05T22:00:00Z'), settings: {...FIELDPROOF_EMAIL_DEFAULTS, version: 1, customer_mode: 'automatic', ...extra.settings}, deliveries: [], objects: new Map(), sends: [], calls: [], tokenHashes: [], reads: [], providerReady: true, senderFingerprint: hash('KORLIX <mail@example.com>'), finishFailures: 0};
  f.user = {id: owner, email: 'owner@example.com', email_confirmed_at: '2026-01-01T00:00:00Z'};
  f.snapshot = {job: {id: jobId, user_id: owner, state: 'completed', version: 3, completion: {completedAt: f.time.toISOString()}, data: {title: 'Meter service', customer: 'Test customer', summary: 'Recorded completed work', checks: [], issues: []}}, evidence: []};
  f.row = changes => ({id: randomUUID(), owner_id: owner, kind: 'customer_report', state: 'pending', delivery_mode: 'automatic', version: 1, job_id: jobId, job_version: 3, recipient: 'customer@example.com', created_at: f.time.toISOString(), scheduled_at: f.time.toISOString(), settings_version: 1, payload: null, ...changes});
  f.add = changes => {const row = f.row(changes); f.deliveries.push(row); return row;};
  f.database = {
    auth: {admin: {getUserById: async id => { if (f.authHook) await f.authHook(id); return {data: {user: id === owner ? clone(f.user) : {id: other, email: 'other@example.com', email_confirmed_at: '2026-01-01T00:00:00Z'}}}; }}},
    rpc: async (name, p) => {
      f.calls.push({name, ...clone(p)});
      try {
        if (f.rpcHook) {const intercepted = await f.rpcHook(name, p); if (intercepted !== undefined) return intercepted;}
        if (name === 'korlix_fieldproof_v1') {
          if (p.p_actor !== owner) throw Object.assign(Error('Job not found.'), {code: 'P0002'});
          return {data: p.p_action === 'list' ? clone(f.jobs || [f.snapshot.job]) : clone(f.snapshot)};
        }
        const row = f.deliveries.find(d => d.id === p.p_id);
        if (['delivery', 'approve', 'cancel', 'retry', 'prepare', 'authorize', 'finish', 'recipient_token'].includes(p.p_action) && (!row || row.owner_id !== p.p_actor)) throw Object.assign(Error('Email not found.'), {code: 'P0002'});
        switch (p.p_action) {
          case 'delivery': return {data: clone(row)};
          case 'state': return {data: {settings: clone(f.settings), deliveries: clone(f.deliveries.filter(d => d.owner_id === p.p_actor))}};
          case 'save_settings': f.settings = {...p.p_data.settings, version: f.settings.version + 1}; return {data: clone(f.settings)};
          case 'job_state': if (p.p_actor !== owner || p.p_id !== jobId) throw Object.assign(Error('Job not found.'), {code: 'P0002'}); return {data: {job_settings: {version: 0, customer_email: '', enabled: false}, deliveries: clone(f.deliveries)}};
          case 'due_accounts': return {data: f.accounts || []};
          case 'enqueue_summary': if (!f.deliveries.some(d => d.event_key === p.p_data.event_key)) f.add({...p.p_data, event_key: p.p_data.event_key, kind: 'supervisor_summary', job_id: null, delivery_mode: f.settings.supervisor_mode}); return {data: []};
          case 'claim': {const candidate = f.deliveries.find(d => ['pending', 'ready', 'retry'].includes(d.state) && (!d.retry_at || Date.parse(d.retry_at) <= f.time.getTime())); if (!candidate) return {data: null}; candidate.state = candidate.payload ? 'sending' : 'preparing'; candidate.lease = p.p_data.lease_token; return {data: clone(candidate)};}
          case 'recipient_token': f.tokenHashes.push(p.p_data.token_hash); return {data: {created: true, suppressed: f.suppressed || false}};
          case 'prepare': assert.equal(row.lease, p.p_data.lease_token); Object.assign(row, clone(p.p_data), {state: row.delivery_mode === 'draft' ? 'draft' : 'ready', version: row.version + 1}); delete row.lease; return {data: clone(row)};
          case 'authorize': assert.equal(row.lease, p.p_data.lease_token); if (f.pauseOnAuthorize || f.suppressed) {row.state = 'cancelled'; return {data: clone(row)};} row.first_attempt_at ||= f.time.toISOString(); return {data: clone(row)};
          case 'finish': if (f.finishFailures-- > 0) throw Error('database temporarily unavailable'); assert.equal(row.lease, p.p_data.lease_token); Object.assign(row, clone(p.p_data), {version: row.version + 1}); delete row.lease; if (row.state === 'accepted') row.accepted_at = f.time.toISOString(); return {data: clone(row)};
          case 'approve': if (row.state !== 'draft') throw Object.assign(Error('Refresh this delivery.'), {code: '40001'}); row.state = 'ready'; row.version++; return {data: clone(row)};
          case 'cancel': row.state = 'cancelled'; return {data: clone(row)};
          case 'retry': if (!row.payload || !['unknown', 'retry'].includes(row.state) || f.time.getTime() - Date.parse(row.first_attempt_at) >= 23 * 3600000) throw Object.assign(Error('Retry window expired.'), {code: '40001'}); row.state = 'ready'; row.version++; return {data: clone(row)};
          case 'cleanup': return {data: []};
          case 'unsubscribe': f.suppressed = f.tokenHashes.includes(p.p_data.token_hash); return {data: {suppressed: f.suppressed}};
          case 'suppress': return {data: {suppressed: true}};
          default: throw Error('Unhandled fixture RPC ' + p.p_action);
        }
      } catch (error) { return {error}; }
    },
  };
  f.storage = {storage: {from: bucket => ({
    upload: async (path, bytes, options) => {assert.equal(bucket, 'korlix-fieldproof-mail'); assert.equal(options.upsert, false); if (f.uploadFailure) return {error: Error('offline')}; if (f.objects.has(path)) return {error: Error('duplicate')}; f.objects.set(path, Buffer.from(bytes)); return {data: {path}};},
    download: async path => {f.reads.push({bucket, path}); if (f.downloadHook) await f.downloadHook(path); if (f.downloadFailure || !f.objects.has(path)) return {error: Error('offline')}; return {data: new Blob([f.objects.get(path)])};},
    remove: async paths => {for (const p of paths) f.objects.delete(p); return {data: []};},
  })}};
  f.renderer = async input => {f.renderInput = input; if (f.renderFailure) throw Error('renderer unavailable'); return {subject: 'FieldProof report', text: 'Saved job facts.', html: '<html><body><p>Saved job facts.</p></body></html>', attachments: [{filename: 'FieldProof-report.pdf', content: pdf}]};};
  f.provider = {status: () => ({ready: f.providerReady, reason: f.providerReady ? null : 'sender_unavailable', senderFingerprint: f.senderFingerprint}), send: async payload => {f.sends.push(clone(payload)); if (f.sendHook) return f.sendHook(payload); return {accepted: true, providerId: randomUUID()};}};
  f.service = createFieldProofEmails({database: f.database, storageDatabase: f.storage, requireUser: async q => [owner, other].includes(q.headers.authorization) ? {id: q.headers.authorization} : null, provider: f.provider, renderer: f.renderer, now: () => f.time, publicRoot: 'https://backend.example.com', autoStart: false, logger: {warn() {}}});
  f.open = async () => {
    const app = express(); app.use(express.json()); f.service.register(app); f.server = app.listen(0, '127.0.0.1'); await new Promise(r => f.server.once('listening', r));
    f.base = `http://127.0.0.1:${f.server.address().port}/api/fieldproof/email`;
    f.api = async (path = '', {body, method = body ? 'POST' : 'GET', actor = owner, status = 200} = {}) => {const r = await fetch(f.base + path, {method, headers: {Authorization: actor, 'Content-Type': 'application/json'}, ...(body ? {body: JSON.stringify(body)} : {})}); const data = await r.json(); assert.equal(r.status, status, JSON.stringify(data)); assert.equal(r.headers.get('cache-control'), 'no-store'); return data;};
  };
  f.close = async () => {f.service.stop(); if (f.server) await new Promise(r => f.server.close(r));};
  return f;
}

test('settings reject spoofed routing, invalid schedules and limits; addresses normalize', () => {
  const defaults = {...FIELDPROOF_EMAIL_DEFAULTS}; delete defaults.version;
  assert.equal(normalizeFieldProofEmailSettings(defaults).customer_mode, 'off');
  assert.deepEqual(normalizeFieldProofEmailSettings({...defaults, supervisor_emails: ['Boss@EXAMPLE.COM', 'boss@example.com']}).supervisor_emails, ['boss@example.com']);
  for (const patch of [{from: 'attacker@example.com'}, {replyTo: 'attacker@example.com'}, {daily_limit: 101}, {timezone: 'Not/AZone'}, {summary_days: [8]}, {summary_time: '24:00'}, {supervisor_emails: ['a@example.com\r\nBcc:steal@example.com']}, {customer_mode: 'yes'}, {followup_days: 0}]) assert.throws(() => normalizeFieldProofEmailSettings({...defaults, ...patch}));
});
test('summary windows use exact previous local calendar day across spring and fall DST', () => {
  const s = {...FIELDPROOF_EMAIL_DEFAULTS, supervisor_mode: 'draft', summary_days: [0, 1, 2, 3, 4, 5, 6]};
  const spring = fieldProofSummaryWindow(s, new Date('2026-03-09T22:00:00Z'));
  assert.equal(spring.report_date, '2026-03-08'); assert.equal(spring.period_start, '2026-03-08T05:00:00.000Z'); assert.equal(spring.period_end, '2026-03-09T04:00:00.000Z');
  const fall = fieldProofSummaryWindow(s, new Date('2026-11-02T23:00:00Z'));
  assert.equal(Date.parse(fall.period_end) - Date.parse(fall.period_start), 25 * 3600000);
  assert.equal(fieldProofSummaryWindow(s, new Date('2026-10-05T20:59:59Z')), null);
  assert.equal(fieldProofSummaryWindow({...s, paused: true}, new Date('2026-10-05T22:00:00Z')), null);
  assert.equal(fieldProofSummaryWindow({...s, summary_days: [2]}, new Date('2026-10-05T22:00:00Z')), null);
});
test('nonexistent schedule time advances to first real minute; repeated time emits one daily key', () => {
  const s = {...FIELDPROOF_EMAIL_DEFAULTS, supervisor_mode: 'draft', summary_days: [0], summary_time: '02:30'};
  assert.equal(fieldProofSummaryWindow(s, new Date('2026-03-08T07:10:00Z')).scheduled_at, '2026-03-08T07:00:00.000Z');
  const a = fieldProofSummaryWindow({...s, summary_time: '01:30'}, new Date('2026-11-01T05:45:00Z'));
  const b = fieldProofSummaryWindow({...s, summary_time: '01:30'}, new Date('2026-11-01T06:45:00Z'));
  assert.equal(a.event_key, b.event_key); assert.equal(a.scheduled_at, b.scheduled_at);
});
test('supervisor summary counts closeout timestamps and current issues; escapes customer input', () => {
  const settings = {...FIELDPROOF_EMAIL_DEFAULTS, business_name: '<img src=x onerror=alert(1)>'};
  const row = {report_date: '2026-10-04', period_start: '2026-10-04T04:00:00Z', period_end: '2026-10-05T04:00:00Z'};
  const result = renderFieldProofSupervisorSummary({settings, delivery: row, now: new Date('2026-10-05T22:00:00Z'), jobs: [
    {state: 'completed', completion: {completedAt: '2026-10-05T03:59:59Z'}, data: {title: '<script>evil</script>', issues: []}},
    {state: 'completed', completion: {completedAt: '2026-10-05T04:00:00Z'}, data: {title: 'Next period'}},
    {state: 'active', data: {title: 'Overdue', dueOn: '2026-10-04', issues: [{label: 'Seal', resolved: false}]}},
    {state: 'deleting', data: {title: 'Being removed', dueOn: '2026-10-03', issues: [{label: 'Removed issue', resolved: false}]}},
  ]});
  assert.match(result.text, /Completed: 1 \| Currently overdue: 1 \| Jobs with open items: 1/); assert.doesNotMatch(result.html, /<script>|<img/); assert.match(result.html, /&lt;script&gt;/);
});
test('account and job routes enforce authenticated ownership; private payload never escapes previews', async () => {
  const f = fixture(); const row = f.add({delivery_mode: 'draft'}); await f.service.tick(); await f.open();
  try {
    await f.api('', {actor: '', status: 401}); await f.api(`/jobs/${f.jobId}`, {actor: f.other, status: 404});
    await f.api(`/deliveries/${row.id}`, {actor: f.other, status: 404}); await f.api(`/deliveries/${row.id}/report`, {actor: f.other, status: 404});
    const detail = await f.api(`/deliveries/${row.id}`); assert.equal(detail.delivery.can_approve, true); assert.equal(detail.delivery.recipient, 'customer@example.com'); assert.equal(detail.delivery.has_report, true);
    const serialized = JSON.stringify(detail); assert.doesNotMatch(serialized, /token=|report\.pdf|owner_id|senderFingerprint|lease/);
    const r = await fetch(f.base + `/deliveries/${row.id}/report`, {headers: {Authorization: f.owner}}); assert.equal(r.status, 200); assert.match(r.headers.get('content-type'), /application\/pdf/); assert.deepEqual(Buffer.from(await r.arrayBuffer()), pdf);
  } finally { await f.close(); }
});
test('verified account email supplies Reply-To; editable user metadata never authorizes sending', async () => {
  const f = fixture(); f.user.email_confirmed_at = null; f.user.user_metadata = {email: 'verified@example.com', email_verified: true}; const row = f.add();
  await f.service.tick(); assert.equal(row.state, 'failed'); assert.equal(row.code, 'fieldproof_email_identity_unverified'); assert.equal(f.sends.length, 0);
  await f.open(); try {const state = await f.api(); assert.equal(state.capabilities.ready, false); assert.equal(state.capabilities.reply_to, null);} finally {await f.close();}
});
test('draft preparation stores immutable report and requires explicit owner approval before send', async () => {
  const f = fixture(); const row = f.add({delivery_mode: 'draft'}); await f.service.tick(); assert.equal(row.state, 'draft'); assert.equal(f.sends.length, 0); assert.equal(f.objects.size, 1);
  await f.service.tick(); assert.equal(f.sends.length, 0); await f.open();
  try {await f.api(`/deliveries/${row.id}/approve`, {body: {confirmed: true, version: row.version}, actor: f.other, status: 404}); await f.api(`/deliveries/${row.id}/approve`, {body: {confirmed: true, version: row.version}}); await f.service.tick(); assert.equal(row.state, 'accepted'); assert.equal(f.sends[0].replyTo, 'owner@example.com'); assert.equal(Buffer.from(f.sends[0].attachments[0].content, 'base64').equals(pdf), true);}
  finally {await f.close();}
});
test('automatic report renders once and duplicate or overlapping ticks send only one ID', async () => {
  const f = fixture(); const row = f.add(); let release; const gate = new Promise(r => release = r); f.authHook = async () => gate;
  const first = f.service.tick(); assert.deepEqual(await f.service.tick(), {skipped: true}); release(); await first; await f.service.tick();
  assert.equal(f.sends.length, 1); assert.equal(f.sends[0].id, row.id); assert.equal(row.state, 'accepted');
});
test('renderer or attachment upload failure never reaches provider authorization', async () => {
  for (const problem of ['renderFailure', 'uploadFailure']) {
    const f = fixture(); f[problem] = true; const row = f.add(); await f.service.tick(); assert.equal(row.state, 'failed'); assert.equal(f.sends.length, 0); assert.equal(f.calls.some(x => x.p_action === 'authorize'), false);
  }
});
test('normalized photo previews are scope checked and hash verified; originals never downloaded', async () => {
  const f = fixture({settings: {include_photos: true}}), photoId = randomUUID(), bytes = Buffer.from('normalized preview fixture');
  const path = `${f.owner}/${f.jobId}/${photoId}/preview.jpg`;
  f.snapshot.evidence = [{id: photoId, user_id: f.owner, job_id: f.jobId, state: 'ready', preview_path: path, preview_sha256: hash(bytes), preview_bytes: bytes.length, path: 'never/original.jpg'}]; f.objects.set(path, bytes); f.add({delivery_mode: 'draft'}); await f.service.tick();
  assert.deepEqual(f.renderInput.previews.get(photoId), bytes); assert.equal(f.reads.every(r => r.path.endsWith('preview.jpg')), true);
  const bad = fixture({settings: {include_photos: true}}); bad.snapshot.evidence = [f.snapshot.evidence[0]]; const row = bad.add(); await bad.service.tick(); assert.equal(row.state, 'failed'); assert.equal(row.code, 'fieldproof_email_photo_scope'); assert.equal(bad.reads.length, 0);
});
test('saved report integrity failure blocks dispatch and fresh authorization', async () => {
  const f = fixture(); const row = f.add({delivery_mode: 'draft'}); await f.service.tick(); f.objects.set(row.attachment_path, Buffer.from('corrupted bytes')); row.state = 'ready'; await f.service.tick();
  assert.equal(row.state, 'failed'); assert.equal(row.code, 'fieldproof_email_attachment_integrity'); assert.equal(f.sends.length, 0); assert.equal(f.calls.some(x => x.p_action === 'authorize'), false);
});
test('fresh authorize prevents sending when pause or suppression happens after preparation', async () => {
  const f = fixture(); const row = f.add({delivery_mode: 'draft'}); await f.service.tick(); row.state = 'ready'; f.pauseOnAuthorize = true; await f.service.tick(); assert.equal(row.state, 'cancelled'); assert.equal(f.sends.length, 0);
});
test('uncertain provider outcome remains unknown and only explicit same-payload retry can reconcile', async () => {
  const f = fixture(); const row = f.add(); f.sendHook = async () => {throw Object.assign(Error('connection lost'), {outcome: 'uncertain', retryable: true, code: 'fieldproof_email_transport_uncertain'});}; await f.service.tick();
  assert.equal(row.state, 'unknown'); assert.equal(f.sends.length, 1); const original = clone(f.sends[0]); await f.service.tick(); assert.equal(f.sends.length, 1);
  await f.open(); try {f.sendHook = null; await f.api(`/deliveries/${row.id}/retry`, {body: {confirmed: true, version: row.version}}); await f.service.tick(); assert.equal(row.state, 'accepted'); assert.deepEqual(f.sends[1], original); assert.equal(f.tokenHashes.length, 1);} finally {await f.close();}
});
test('provider acceptance plus repeated receipt-save failures must never become not-sent', async () => {
  const f = fixture(); const row = f.add(); f.sendHook = async () => {f.finishFailures = 2; return {accepted: true, providerId: randomUUID()};}; await f.service.tick(); assert.equal(f.sends.length, 1); assert.equal(row.state, 'unknown');
});
test('changed verified owner email or configured sender blocks stale payload dispatch', async () => {
  for (const change of ['email', 'from']) {const f = fixture(); const row = f.add({delivery_mode: 'draft'}); await f.service.tick(); row.state = 'ready'; if (change === 'email') f.user.email = 'changed@example.com'; else f.senderFingerprint = hash('different sender'); await f.service.tick(); assert.equal(row.state, 'cancelled'); assert.equal(row.code, 'fieldproof_email_sender_changed'); assert.equal(f.sends.length, 0);}
});
test('expired 23-hour retry window never contacts provider and UI disables retry', async () => {
  const f = fixture(); const row = f.add({delivery_mode: 'draft'}); await f.service.tick(); row.state = 'ready'; row.first_attempt_at = new Date(f.time.getTime() - 23 * 3600000).toISOString(); await f.service.tick(); assert.equal(row.state, 'unknown'); assert.equal(f.sends.length, 0);
  await f.open(); try {assert.equal((await f.api(`/deliveries/${row.id}`)).delivery.can_retry, false);} finally {await f.close();}
});
test('single courtesy follow-up is factual, uses same recipient and has no attachment', async () => {
  const f = fixture(); const row = f.add({kind: 'customer_followup'}); await f.service.tick(); assert.equal(row.state, 'accepted'); assert.equal(f.sends.length, 1); assert.deepEqual(f.sends[0].attachments, []); assert.match(f.sends[0].text, /single service follow-up/); assert.equal(f.sends[0].to, row.recipient);
});
test('scheduled summary enqueue is one selected-day event, no historical backlog or repeated sending', async () => {
  const f = fixture({settings: {supervisor_mode: 'draft', supervisor_emails: ['boss@example.com']}}); f.accounts = [{...f.settings, owner_id: f.owner}]; await f.service.tick(); await f.service.tick(); assert.equal(f.deliveries.length, 1); assert.equal(f.deliveries[0].kind, 'supervisor_summary'); assert.equal(f.deliveries[0].report_date, '2026-10-04'); assert.equal(f.deliveries[0].state, 'draft'); assert.equal(f.sends.length, 0);
});
test('unsubscribe GET is confirmation-only; explicit POST stores only SHA256 and reveals no identity', async () => {
  const f = fixture(); const row = f.add({delivery_mode: 'draft'}); await f.service.tick(); const token = /token=([A-Za-z0-9_-]{43})/.exec(row.payload.text)[1]; assert.equal(f.tokenHashes[0], hash(token)); await f.open();
  try {const page = await fetch(f.base + '/unsubscribe?token=' + token); const body = await page.text(); assert.equal(f.suppressed, undefined); assert.match(body, /method="post"/); assert.doesNotMatch(body, /customer@example|owner@example/); assert.equal(page.headers.get('referrer-policy'), 'no-referrer');
    const response = await fetch(f.base + '/unsubscribe', {method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: 'token=' + token}); assert.equal(response.status, 200); assert.equal(f.suppressed, true);
  } finally {await f.close();}
});
test('per-tick claim bound limits burst work and stopped worker never claims again', async () => {
  const f = fixture(); for (let i = 0; i < 7; i++) f.add({delivery_mode: 'draft'}); await f.service.tick(); assert.equal(f.deliveries.filter(d => d.state === 'draft').length, 4); f.service.stop(); assert.deepEqual(await f.service.tick(), {skipped: true}); assert.equal(f.deliveries.filter(d => d.state === 'pending').length, 3);
});
test('summary schedule expires after six hours and never queues a missed-day backlog', () => {
  const s = {...FIELDPROOF_EMAIL_DEFAULTS, supervisor_mode: 'automatic', summary_days: [0,1,2,3,4,5,6], summary_time: '08:00'};
  const eligible = fieldProofSummaryWindow(s, new Date('2026-10-05T17:59:59Z'));
  assert.equal(eligible.expires_at, '2026-10-05T18:00:00.000Z');
  assert.equal(fieldProofSummaryWindow(s, new Date('2026-10-05T18:00:00Z')), null);
});
test('valid but HTML-expanding supervisor content keeps complete plain text within provider bounds', async () => {
  const f = fixture({settings: {supervisor_mode: 'automatic'}});
  f.jobs = Array.from({length: 200}, () => ({state: 'active', data: {title: '&'.repeat(120), issues: [{label: '&'.repeat(160), resolved: false}, {label: '&'.repeat(160), resolved: false}]}}));
  const row = f.add({kind: 'supervisor_summary', job_id: null, report_date: '2026-10-04', period_start: '2026-10-04T04:00:00Z', period_end: '2026-10-05T04:00:00Z'});
  await f.service.tick(); assert.equal(row.state, 'accepted'); assert.equal(f.sends[0].html, ''); assert.match(f.sends[0].text, /Jobs with open items: 200/); assert.match(f.sends[0].text, /Manage FieldProof emails:/); assert(Buffer.byteLength(f.sends[0].text) < 128 * 1024);
});
test('public settings omit database metadata and normalize SQL time before editing again', async () => {
  const f = fixture({settings: {summary_time: '17:00:00', owner_id: 'private', updated_at: '2026-10-05'}}); await f.open();
  try {const result = await f.api(); assert.equal(result.settings.summary_time, '17:00'); assert.equal(result.settings.owner_id, undefined); assert.equal(result.settings.updated_at, undefined); const {version, ...settings} = result.settings; await f.api('/settings', {method: 'PUT', body: {version, settings, confirmed: true}});}
  finally {await f.close();}
});
test('deleted-delivery garbage collection accepts separate GC ids and acknowledges only removed private reports', async () => {
  const f = fixture(), gcId = randomUUID(), deletedDelivery = randomUUID(), path = `${f.owner}/${deletedDelivery}/report.pdf`; f.objects.set(path, pdf); let ack;
  f.rpcHook = async (_name, p) => {if (p.p_action === 'cleanup') return {data: [{id: gcId, attachment_path: path, gc: true}, {id: randomUUID(), attachment_path: `${f.owner}/../../original.jpg`, gc: true}]}; if (p.p_action === 'cleanup_done') {ack = p.p_data; return {data: {deleted: true}};}};
  await f.service.tick(); assert.equal(f.objects.has(path), false); assert.deepEqual(ack, {ids: [], gc_ids: [gcId]});
});
