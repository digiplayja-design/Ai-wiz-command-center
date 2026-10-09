import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createReceiptBackupAlerts, BACKUP_ALERT_RECIPIENT} from '../receipt_backup/alerts.mjs';
import {startReceiptBackupRuntime} from '../receipt_backup/runtime.mjs';
import {SOURCE_PROJECT} from '../receipt_backup/config.mjs';

const TIME = new Date('2026-10-09T06:30:00.000Z');
const EMAIL_ID = '10000000-0000-4000-8000-000000000001';
const TEST_ID = '20000000-0000-4000-8000-000000000002';
function environment() {
  return {RECEIPT_BACKUP_ALERT_EMAIL: BACKUP_ALERT_RECIPIENT, RESEND_API_KEY: 're_syntheticKeyForUnitTestsOnly',
    KORLIX_SUPPORT_FROM_EMAIL: 'Korlix <support@korlixdeveloper.com>'};
}
function setup(overrides = {}) {
  const calls = [], logs = [];
  const ctx = {env: environment(), now: () => TIME, sleep: async () => {},
    logger: {info: line => logs.push(JSON.parse(line)), error: line => logs.push(JSON.parse(line))},
    fetchImpl: async (url, options) => { calls.push({url, ...options}); return Response.json({id: EMAIL_ID}); }, ...overrides};
  return {alerts: createReceiptBackupAlerts(ctx), calls, logs};
}
const failure = () => Object.assign(new Error('private-receipt-content-must-not-leak'), {code: 'BACKUP_ACCESS_DENIED'});

test('no email is sent unless the user-approved recipient is configured', async () => {
  for (const recipient of ['', 'another@example.com', 'support@korlixdeveloper.com,another@example.com']) {
    const ctx = setup({env: {...environment(), RECEIPT_BACKUP_ALERT_EMAIL: recipient}});
    await ctx.alerts.failure(failure()); await ctx.alerts.test();
    assert.equal(ctx.calls.length, 0);
    assert(!JSON.stringify(ctx.logs).includes('another@example.com'));
  }
});

test('missing credentials, unsupported senders and header injection fail closed without secrets in logs', async () => {
  const invalid = [{RESEND_API_KEY: ''}, {RESEND_API_KEY: 're_secret\r\nheader'},
    {KORLIX_SUPPORT_FROM_EMAIL: 'wrong@example.com'}, {KORLIX_SUPPORT_FROM_EMAIL: 'support@korlixdeveloper.com\r\nBcc: wrong@example.com'}];
  for (const change of invalid) {
    const ctx = setup({env: {...environment(), ...change}}); await ctx.alerts.failure(failure());
    assert.equal(ctx.calls.length, 0); assert(ctx.logs.some(v => v.status === 'blocked'));
    assert(!JSON.stringify(ctx.logs).includes('re_secret')); assert(!JSON.stringify(ctx.logs).includes('wrong@example.com'));
  }
});

test('failure email uses the pinned endpoint and recipient with only redacted diagnostic fields', async () => {
  const ctx = setup(); const result = await ctx.alerts.failure(failure());
  assert.equal(result.accepted, true); assert.equal(ctx.calls.length, 1);
  const call = ctx.calls[0], body = JSON.parse(call.body);
  assert.equal(call.url, 'https://api.resend.com/emails'); assert.equal(call.redirect, 'error');
  assert.deepEqual(body.to, [BACKUP_ALERT_RECIPIENT]); assert.match(body.subject, /needs attention/);
  assert.match(body.text, /BACKUP_ACCESS_DENIED/); assert(!body.text.includes('private-receipt-content'));
  assert(!JSON.stringify(ctx.logs).includes(environment().RESEND_API_KEY));
  assert(!body.text.includes('syntheticKey')); assert.equal(body.attachments, undefined);
  assert(ctx.logs.some(v => v.status === 'accepted' && v.inboxDeliveryVerified === false));
});

test('unknown errors cannot put provider messages or URLs in the email', async () => {
  const ctx = setup(); await ctx.alerts.failure(new Error('https://customer/private?token=secret'));
  const body = JSON.parse(ctx.calls[0].body);
  assert.match(body.text, /BACKUP_OPERATION_FAILED/); assert(!body.text.includes('token=secret'));
});

test('repeated failures are suppressed locally and have stable payloads across restarts', async () => {
  const first = setup(); await first.alerts.failure(failure());
  assert.equal((await first.alerts.failure(failure())).suppressed, true); assert.equal(first.calls.length, 1);
  const restarted = setup({now: () => new Date(TIME.getTime() + 900000)}); await restarted.alerts.failure(failure());
  assert.equal(first.calls[0].headers['Idempotency-Key'], restarted.calls[0].headers['Idempotency-Key']);
  assert.equal(first.calls[0].body, restarted.calls[0].body);
});

test('new errors or a new six-hour UTC window can notify again', async () => {
  let current = TIME; const ctx = setup({now: () => current});
  await ctx.alerts.failure(failure());
  await ctx.alerts.failure({code: 'BACKUP_SOURCE_CHANGED'});
  current = new Date(TIME.getTime() + 6 * 60 * 60 * 1000); await ctx.alerts.failure(failure());
  assert.equal(ctx.calls.length, 3); assert.equal(new Set(ctx.calls.map(c => c.headers['Idempotency-Key'])).size, 3);
});

test('concurrent notification attempts share a single provider request', async () => {
  let resolve, count = 0;
  const ctx = setup({fetchImpl: async () => {count++; await new Promise(r => {resolve = r;}); return Response.json({id: EMAIL_ID});}});
  const one = ctx.alerts.failure(failure()), two = ctx.alerts.failure(failure());
  resolve(); assert.equal((await one).accepted, true); assert.equal((await two).accepted, true); assert.equal(count, 1);
});

test('ambiguous network errors and transient responses retry with exactly the same payload and key', async () => {
  const calls = [];
  const ctx = setup({fetchImpl: async (url, options) => {
    calls.push(options); if (calls.length === 1) throw new Error('provider-secret');
    if (calls.length === 2) return Response.json({message: 'provider-secret'}, {status: 503});
    return Response.json({id: EMAIL_ID});
  }});
  assert.equal((await ctx.alerts.failure(failure())).accepted, true); assert.equal(calls.length, 3);
  assert.equal(new Set(calls.map(c => c.body)).size, 1); assert.equal(new Set(calls.map(c => c.headers['Idempotency-Key'])).size, 1);
  assert(!JSON.stringify(ctx.logs).includes('provider-secret'));
});

test('permanent provider failures do not loop or expose the response body', async () => {
  let calls = 0;
  const ctx = setup({fetchImpl: async () => {calls++; return Response.json({message: 'confidential provider detail'}, {status: 403});}});
  const result = await ctx.alerts.failure(failure()); assert.equal(result.accepted, false); assert.equal(calls, 1);
  assert(ctx.logs.some(v => v.httpStatus === 403)); assert(!JSON.stringify(ctx.logs).includes('confidential'));
});

test('a success response without an email ID is not claimed as accepted', async () => {
  const ctx = setup({fetchImpl: async () => Response.json({})});
  assert.equal((await ctx.alerts.failure(failure())).accepted, false);
  assert(ctx.logs.some(v => v.code === 'BACKUP_ALERT_RESPONSE_INVALID'));
});

test('stopping the service prevents new notifications', async () => {
  const controller = new AbortController(); controller.abort();
  const ctx = setup({signal: controller.signal});
  assert.equal((await ctx.alerts.failure(failure())).accepted, false); assert.equal(ctx.calls.length, 0);
});

test('a labeled test is deduplicated and expires without creating a fake failure', async () => {
  let current = TIME;
  const env = {...environment(), RECEIPT_BACKUP_ALERT_TEST_ID: TEST_ID,
    RECEIPT_BACKUP_ALERT_TEST_EXPIRES_AT: new Date(TIME.getTime() + 3600000).toISOString()};
  const ctx = setup({env, now: () => current});
  assert.equal((await ctx.alerts.test()).accepted, true); await ctx.alerts.test(); assert.equal(ctx.calls.length, 1);
  const body = JSON.parse(ctx.calls[0].body); assert.match(body.subject, /alert test/); assert.match(body.text, /No backup failure was simulated/);
  current = new Date(TIME.getTime() + 3600001); assert.equal((await ctx.alerts.test()).skipped, true); assert.equal(ctx.calls.length, 1);
});

test('an unbounded, invalid or stale test configuration cannot send a test email', async () => {
  for (const expiry of ['invalid', '2030-01-01T00:00:00Z', '2026-01-01T00:00:00Z']) {
    const ctx = setup({env: {...environment(), RECEIPT_BACKUP_ALERT_TEST_ID: TEST_ID, RECEIPT_BACKUP_ALERT_TEST_EXPIRES_AT: expiry}});
    await ctx.alerts.test(); assert.equal(ctx.calls.length, 0);
  }
});

function backupEnvironment() {
  const key = Buffer.alloc(32, 1);
  return {RECEIPT_BACKUP_MODE: 'enabled', RECEIPT_BACKUP_B2_ENDPOINT: 'https://s3.us-east-005.backblazeb2.com',
    RECEIPT_BACKUP_B2_REGION: 'us-east-005', RECEIPT_BACKUP_B2_BUCKET: 'korlix-backups', RECEIPT_BACKUP_B2_PREFIX: 'receipts/',
    RECEIPT_BACKUP_B2_KEY_ID: 'syntheticKeyId', RECEIPT_BACKUP_B2_APPLICATION_KEY: 'syntheticApplicationKey',
    RECEIPT_BACKUP_RECOVERY_KEY_BASE64: key.toString('base64'), RECEIPT_BACKUP_RECOVERY_KEY_ESCROWED: 'true',
    RECEIPT_BACKUP_RETENTION_CONFIGURED: 'true', RECEIPT_BACKUP_PRIVACY_DISCLOSURE_READY: 'true',
    RECEIPT_BACKUP_RECOVERY_KEY_FINGERPRINT: createHash('sha256').update(key).digest('hex').slice(0, 16),
    SUPABASE_URL: 'https://' + SOURCE_PROJECT + '.supabase.co'};
}
function runtimeSetup(overrides = {}) {
  const jobs = [], logs = [], failures = [], objects = new Map();
  const store = {async put(name, bytes) {objects.set(name, Buffer.from(bytes)); return {versionId: 'synthetic-version'};},
    async get(name) {return objects.get(name) || null;}, async list(prefix) {return [...objects.keys()].filter(k => k.startsWith(prefix));},
    async assertPrivate() {}, async deleteProbe(name) {objects.delete(name);}, close() {}};
  const runtime = startReceiptBackupRuntime({env: backupEnvironment(),
    logger: {info: v => logs.push(JSON.parse(v)), error: v => logs.push(JSON.parse(v))},
    timers: {setTimeout: (fn, ms) => {jobs.push({fn, ms}); return {unref() {}};}, clearTimeout() {}},
    storeFactory: () => store, sourceFactory: () => ({list: async () => []}),
    alertsFactory: () => ({failure: async e => {failures.push(e.code);}, test: async () => ({accepted: true})}), ...overrides});
  return {runtime, jobs, logs, failures};
}

test('production job failures invoke the alert and keep the backup retry schedule', async () => {
  const ctx = runtimeSetup({sourceFactory: () => ({list: async () => {throw failure();}})});
  await ctx.jobs[0].fn(); assert.deepEqual(ctx.failures, ['BACKUP_ACCESS_DENIED']);
  assert.equal(ctx.jobs[1].ms, 15 * 60 * 1000); assert.equal(ctx.runtime.getStatus().lastSuccessAt, null); ctx.runtime.stop();
});

test('a notification exception cannot invalidate or stop a successful backup', async () => {
  const ctx = runtimeSetup({alertsFactory: () => ({failure: async () => {throw new Error('must not call');},
    test: async () => {throw new Error('mail outage');}})});
  await ctx.jobs[0].fn(); assert(ctx.runtime.getStatus().lastSuccessAt);
  assert.equal(ctx.runtime.getStatus().lastError, null); assert.equal(ctx.jobs[1].ms, 60 * 60 * 1000);
  assert(ctx.logs.some(v => v.event === 'receipt_backup_run' && v.status === 'complete'));
  assert(ctx.logs.some(v => v.event === 'receipt_backup_alert' && v.status === 'failed')); ctx.runtime.stop();
});

test('configuration failures notify in enabled mode without crashing the app', async () => {
  const ctx = runtimeSetup({env: {...backupEnvironment(), RECEIPT_BACKUP_RECOVERY_KEY_ESCROWED: 'false'}});
  await Promise.resolve(); assert.deepEqual(ctx.failures, ['BACKUP_RECOVERY_KEY_CUSTODY_REQUIRED']);
  assert.equal(ctx.jobs.length, 0); ctx.runtime.stop();
});

test('probe mode never sends production failure emails', async () => {
  const ctx = runtimeSetup({env: {...backupEnvironment(), RECEIPT_BACKUP_MODE: 'probe'},
    storeFactory: () => ({async put() {throw failure();}, close() {}})});
  await ctx.jobs[0].fn(); assert.equal(ctx.failures.length, 0); assert.equal(ctx.jobs.length, 1); ctx.runtime.stop();
});
