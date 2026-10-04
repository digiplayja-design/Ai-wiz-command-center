import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import express from 'express';
import { registerFieldProofEmailWebhook } from '../fieldproof/email_webhook.mjs';

const PATH = '/api/agent-email/resend/webhook';
const secretBytes = Buffer.from('fieldproof-webhook-test-signature-secret');
const secret = `whsec_${secretBytes.toString('base64')}`;
const providerId = 'bb8ef0f3-5a47-4df4-b06c-755f43398a54';
const deliveryId = '89a1a3ec-0fcd-4fcf-85a2-31e9b0128523';
const event = (kind = 'email.bounced', extra = {}) => ({ type: kind, created_at: new Date().toISOString(), data: {
  email_id: providerId, to: ['private-customer@example.test'], from: 'private-owner@example.test',
  bounce: { message: 'Private provider diagnostic' }, tags: { fieldproof_delivery: deliveryId }, ...extra,
} });
function signed(payload, { timestamp = Math.floor(Date.now() / 1000), id = 'test-provider-event', bytes = secretBytes } = {}) {
  const signature = createHmac('sha256', bytes).update(`${id}.${timestamp}.${payload}`).digest('base64');
  return { 'Content-Type': 'application/json', 'svix-id': id, 'svix-timestamp': String(timestamp), 'svix-signature': `v1,${signature}` };
}

async function setup(t, { persist = async () => {}, environment = { KORLIX_AGENT_EMAIL_RESEND_WEBHOOK_SECRET: secret }, raw = true, legacyFails = () => false } = {}) {
  const app = express(), calls = [], warnings = [];
  let nextCalls = 0;
  app.use(express.json({ verify(req, _res, buffer) { if (raw) req.korlixAgentEmailRawBody = Buffer.from(buffer); } }));
  registerFieldProofEmailWebhook(app, { environment, logger: { warn: (...args) => warnings.push(args) }, emailService: { suppressProviderEvent: async input => { calls.push(input); return persist(input); } } });
  app.post(PATH, (_req, res) => {
    nextCalls++;
    res.status(legacyFails() ? 503 : 200).json({ legacyAgentEmail: true });
  });
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const url = `http://127.0.0.1:${server.address().port}${PATH}`;
  return { calls, warnings, nextCalls: () => nextCalls, async post(value, options = {}) {
    const body = typeof value === 'string' ? value : JSON.stringify(value);
    const response = await fetch(url, { method: 'POST', headers: options.headers || signed(body, options), body });
    return { response, body: await response.json() };
  } };
}

test('signed failure events fan out using only provider ID, signed delivery tag and fixed reason', async t => {
  const harness = await setup(t);
  for (const type of ['email.bounced', 'email.complained', 'email.suppressed']) {
    const result = await harness.post(event(type));
    assert.equal(result.response.status, 200);
    assert.equal(result.response.headers.get('cache-control'), 'no-store');
    assert.deepEqual(result.body, { legacyAgentEmail: true });
  }
  assert.deepEqual(harness.calls, ['email.bounced', 'email.complained', 'email.suppressed'].map(reason => ({ providerId, deliveryId, reason })));
  assert.equal(harness.nextCalls(), 3);
  assert.deepEqual(harness.warnings, []);
});

test('forged, stale and tampered signed bodies cannot suppress or reach legacy handler', async t => {
  const harness = await setup(t);
  const original = JSON.stringify(event());
  const cases = [
    { headers: { ...signed(original), 'svix-signature': 'v1,forged' } },
    { timestamp: Math.floor(Date.now() / 1000) - 3600 },
    { headers: signed(original.replace('email.bounced', 'email.sent')) },
    { bytes: Buffer.from('different-endpoint-signing-secret') },
    { headers: { 'Content-Type': 'application/json' } },
  ];
  for (const options of cases) assert.equal((await harness.post(original, options)).response.status, 401);
  assert.deepEqual(harness.calls, []);
  assert.equal(harness.nextCalls(), 0);
});

test('captured raw body is required and parsed JSON is never reserialized as signature input', async t => {
  const harness = await setup(t, { raw: false });
  assert.equal((await harness.post(event())).response.status, 400);
  assert.deepEqual(harness.calls, []);
  assert.equal(harness.nextCalls(), 0);
});

test('secondary webhook secret is supported; missing configuration fails closed', async t => {
  const fallback = await setup(t, { environment: { RESEND_WEBHOOK_SECRET: secret } });
  assert.equal((await fallback.post(event())).response.status, 200);
  assert.equal(fallback.calls.length, 1);
  const missing = await setup(t, { environment: {} });
  assert.equal((await missing.post(event())).response.status, 503);
  assert.deepEqual(missing.calls, []);
});

test('unrelated events and invalid provider IDs preserve the existing Agent Email route', async t => {
  const harness = await setup(t, { persist: async () => { throw Error('FieldProof unavailable'); } });
  for (const value of [event('email.sent'), event('email.delivered'), event('email.failed'), event('domain.created'), event('email.bounced', { email_id: 'not-a-provider-uuid' }), { type: 'email.bounced', data: null }]) {
    assert.equal((await harness.post(value)).response.status, 200);
  }
  assert.deepEqual(harness.calls, []);
  assert.equal(harness.nextCalls(), 6);
});

test('unknown IDs never suppress by webhook email or owner fields', async t => {
  const known = new Map(), suppressed = [];
  const harness = await setup(t, { persist: async input => {
    const row = known.get(input.providerId);
    if (!row) return { matched: false };
    suppressed.push(row.recipient);
  } });
  const result = await harness.post(event('email.bounced', { owner_id: 'forged-owner', to: ['another-account@example.test'] }));
  assert.equal(result.response.status, 200);
  assert.deepEqual(suppressed, []);
  assert.deepEqual(Object.keys(harness.calls[0]).sort(), ['deliveryId', 'providerId', 'reason']);
});

test('signed server delivery tag can suppress dispatch before its receipt is persisted', async t => {
  const rows = new Map([[deliveryId, { dispatchAuthorized: true, providerId: null, recipient: 'original-authorized-recipient', suppressed: false }]]);
  const harness = await setup(t, { persist: async input => {
    const row = rows.get(input.deliveryId);
    if (!row?.dispatchAuthorized || (row.providerId && row.providerId !== input.providerId)) return { matched: false };
    row.providerId = input.providerId;
    row.suppressed = true;
  } });
  assert.equal((await harness.post(event())).response.status, 200);
  assert.equal(rows.get(deliveryId).suppressed, true);
  assert.equal(rows.get(deliveryId).providerId, providerId);
});

test('invalid or nonobject tags cannot provide a delivery ID', async t => {
  const harness = await setup(t);
  for (const tags of [undefined, { fieldproof_delivery: '../other-owner' }, [{ name: 'fieldproof_delivery', value: deliveryId }], 'not-an-object']) {
    assert.equal((await harness.post(event('email.bounced', { tags }))).response.status, 200);
  }
  assert(harness.calls.every(input => input.deliveryId === null));
});

test('persistence failures return retryable HTTP status without logging payloads or acknowledging either consumer', async t => {
  const harness = await setup(t, { persist: async () => { throw Error('secret private-customer@example.test'); } });
  const result = await harness.post(event());
  assert.equal(result.response.status, 503);
  assert.equal(harness.nextCalls(), 0);
  assert.equal(result.body.code, 'fieldproof_email_webhook_persistence_unavailable');
  const output = JSON.stringify({ body: result.body, warnings: harness.warnings });
  assert(!output.includes('private-customer'));
  assert(!output.includes('Private provider'));
  assert(!output.includes('secret'));
});

test('redelivery after downstream failure safely repeats durable idempotent suppression', async t => {
  const suppressed = new Set();
  let effects = 0, failLegacy = true;
  const harness = await setup(t, { legacyFails: () => failLegacy, persist: async input => {
    if (!suppressed.has(input.deliveryId)) { suppressed.add(input.deliveryId); effects++; }
  } });
  const payload = event();
  assert.equal((await harness.post(payload)).response.status, 503);
  failLegacy = false;
  assert.equal((await harness.post(payload)).response.status, 200);
  assert.equal(harness.calls.length, 2);
  assert.equal(effects, 1);
  assert.equal(harness.nextCalls(), 2);
});
