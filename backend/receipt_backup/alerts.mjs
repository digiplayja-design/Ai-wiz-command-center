import {safeBackupCode, SOURCE_PROJECT} from './config.mjs';

export const BACKUP_ALERT_RECIPIENT = 'support@korlixdeveloper.com';
const WINDOW_MS = 6 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const DASHBOARD = 'https://dashboard.render.com/web/srv-d8csvkkp3tds73emfikg';

function senderAddress(value) {
  if (typeof value !== 'string' || value.length > 200 || /[\r\n]/.test(value)) return null;
  const sender = value.trim();
  const address = sender.match(/^[^<>]+<([^<>]+)>$/)?.[1] || sender;
  return /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@korlixdeveloper\.com$/i.test(address) ? sender : null;
}

// These alerts are sent only to the address Ricardo explicitly approved.
// Never include receipt data, user identifiers, provider error messages or credentials.
export function createReceiptBackupAlerts({env = process.env, logger = console, fetchImpl = fetch,
  now = () => new Date(), signal, scope = 'receipt', sleep = (ms, abortSignal) => new Promise((resolve, reject) => {
    if (abortSignal?.aborted) return reject(new Error('aborted'));
    const timer = setTimeout(() => { abortSignal?.removeEventListener('abort', abort); resolve(); }, ms);
    function abort() { clearTimeout(timer); reject(new Error('aborted')); }
    abortSignal?.addEventListener('abort', abort, {once: true});
  })} = {}) {
  const disabled = {failure: async () => ({accepted: false, disabled: true}), test: async () => ({accepted: false, disabled: true})};
  if (!['receipt', 'application'].includes(scope)) return disabled;
  const eventPrefix = scope === 'application' ? 'application_backup' : 'receipt_backup';
  const label = scope === 'application' ? 'Application' : 'Receipt';
  const recipient = (env.RECEIPT_BACKUP_ALERT_EMAIL || '').trim().toLowerCase();
  if (!recipient) return disabled;
  const log = (event, fields, failed = false) => logger[failed ? 'error' : 'info'](JSON.stringify({event, ...fields}));
  const from = senderAddress(env.RECEIPT_BACKUP_ALERT_FROM || env.KORLIX_SUPPORT_FROM_EMAIL
    || env.KORLIX_REPORT_FROM_EMAIL || env.KORLIX_AGENT_EMAIL_FROM || '');
  const apiKey = (env.RESEND_API_KEY || '').trim();
  const keyConfigured = /^re_[A-Za-z0-9_-]{10,200}$/.test(apiKey);
  const configurationCode = recipient !== BACKUP_ALERT_RECIPIENT ? 'BACKUP_ALERT_RECIPIENT_INVALID'
    : !from ? 'BACKUP_ALERT_SENDER_NOT_CONFIGURED' : !keyConfigured ? 'BACKUP_ALERT_PROVIDER_NOT_CONFIGURED' : null;
  if (configurationCode) {
    log(eventPrefix + '_alert_configuration', {status: 'blocked', code: configurationCode}, true);
    return disabled;
  }
  log(eventPrefix + '_alert_configuration', {status: 'ready', recipient, provider: 'resend',
    repeatWindowHours: 6, externalOutageMonitoring: false});
  const accepted = new Map(), inFlight = new Map();

  async function attempt(payload, idempotencyKey) {
    if (signal?.aborted) return {accepted: false, aborted: true};
    try {
      const timeout = AbortSignal.timeout(8000);
      const response = await fetchImpl('https://api.resend.com/emails', {
        method: 'POST', redirect: 'error', signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
        headers: {'Authorization': 'Bearer ' + apiKey, 'Content-Type': 'application/json', 'Idempotency-Key': idempotencyKey},
        body: JSON.stringify(payload),
      });
      const text = await response.text();
      let data = null;
      if (text.length <= 16384) { try { data = JSON.parse(text); } catch {} }
      if (response.ok && UUID.test(data?.id || '')) return {accepted: true, emailId: data.id};
      const retryable = response.status === 429 || response.status >= 500
        || (response.status === 409 && data?.name === 'concurrent_idempotent_requests');
      return {accepted: false, retryable, httpStatus: response.status,
        code: response.ok ? 'BACKUP_ALERT_RESPONSE_INVALID' : 'BACKUP_ALERT_PROVIDER_REJECTED'};
    } catch {
      return {accepted: false, retryable: !signal?.aborted, aborted: Boolean(signal?.aborted), code: 'BACKUP_ALERT_REQUEST_FAILED'};
    }
  }

  async function send(kind, idempotencyKey, subject, lines) {
    for (const [key, expiry] of accepted) if (expiry <= now().getTime()) accepted.delete(key);
    if (accepted.has(idempotencyKey)) return {accepted: true, suppressed: true};
    if (inFlight.has(idempotencyKey)) return inFlight.get(idempotencyKey);
    const payload = {from, to: [recipient], subject, text: lines.join('\n'),
      tags: [{name: 'category', value: eventPrefix}, {name: 'kind', value: kind}]};
    const pending = (async () => {
      let result;
      for (let index = 0; index < 3; index++) {
        result = await attempt(payload, idempotencyKey);
        if (result.accepted || !result.retryable || signal?.aborted) break;
        if (index < 2) { try { await sleep(1000 * (index + 1), signal); } catch { break; } }
      }
      if (result.accepted) {
        accepted.set(idempotencyKey, now().getTime() + DAY_MS);
        while (accepted.size > 32) accepted.delete(accepted.keys().next().value);
        log(eventPrefix + '_alert', {kind, status: 'accepted', recipient, provider: 'resend', emailId: result.emailId,
          inboxDeliveryVerified: false});
      } else if (!signal?.aborted) {
        log(eventPrefix + '_alert', {kind, status: 'failed', code: result.code || 'BACKUP_ALERT_REQUEST_FAILED',
          ...(result.httpStatus ? {httpStatus: result.httpStatus} : {})}, true);
      }
      return result;
    })();
    inFlight.set(idempotencyKey, pending);
    try { return await pending; } finally { inFlight.delete(idempotencyKey); }
  }

  return {
    async failure(error) {
      const code = safeBackupCode(error), window = Math.floor(now().getTime() / WINDOW_MS);
      const windowStart = new Date(window * WINDOW_MS).toISOString();
      // Stable payloads also deduplicate retries and overlapping instances at Resend.
      return send('failure', `korlix-${scope}-backup/${SOURCE_PROJECT}/failure/${code}/${window}`,
        `[KORLIX] ${label} backup needs attention`, [
          `At least one KORLIX ${scope} backup attempt failed during this monitoring window.`,
          '', `Monitoring window starts (UTC): ${windowStart}`, `Failure code: ${code}`,
          'A complete, verified backup was not confirmed for the affected attempt.',
          `Earlier successful backups remain the last recovery point; review the latest ${eventPrefix}_run log.`,
          'Run failures normally retry after 15 minutes. Configuration errors require correction and a restart.',
          '', `Open the backend logs: ${DASHBOARD}`,
          'Repeated occurrences of this error are grouped into six-hour UTC windows.',
          'This email contains no receipt contents, user records, application keys or recovery keys.',
        ]);
    },
    async test() {
      if (scope !== 'receipt') return {accepted: false, skipped: true};
      const id = env.RECEIPT_BACKUP_ALERT_TEST_ID || '';
      if (!id) return {accepted: false, skipped: true};
      const expiry = Date.parse(env.RECEIPT_BACKUP_ALERT_TEST_EXPIRES_AT || '');
      const remaining = expiry - now().getTime();
      if (!UUID.test(id) || !Number.isFinite(expiry) || remaining > 2 * 60 * 60 * 1000) {
        log('receipt_backup_alert', {kind: 'test', status: 'blocked', code: 'BACKUP_ALERT_TEST_INVALID'}, true);
        return {accepted: false, skipped: true};
      }
      if (remaining <= 0) return {accepted: false, skipped: true};
      return send('test', `korlix-receipt-backup/${SOURCE_PROJECT}/test/${id}`,
        '[KORLIX] Receipt backup alert test', [
          'This is the notification test requested during KORLIX receipt-backup setup.',
          'Receipt-backup run failures are configured to alert support@korlixdeveloper.com.',
          'No backup failure was simulated, and this test does not change or delete any receipt.',
          '', 'Successful backups are checked approximately hourly while the backend is running.',
          'These emails report detected run failures. A complete backend outage needs an independent monitor.',
          '', `Backend dashboard: ${DASHBOARD}`, `Test reference: ${id}`,
          'Keep the recovery key in your independent secure recovery location. Do not email that key.',
        ]);
    },
  };
}
