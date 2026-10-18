import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, randomUUID, verify } from 'node:crypto';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import express from 'express';
import { createSocialNativePush, nativePushOwner, nativeDeliveryOutcome, nativeDeliveryPayload } from '../social/native_push.mjs';
import { createApnsHttp2Transport, createNativePushSender, nativeRetryAfter, socialNativePushConfig, validateSocialNativeSubscription } from '../social/native_push_providers.mjs';
import { EventEmitter } from 'node:events';

const env = { SUPABASE_URL: 'https://project.supabase.co', SOCIAL_NATIVE_PUSH_ENABLED: 'true', SOCIAL_NATIVE_FCM_ENABLED: 'true',
  SOCIAL_NATIVE_FCM_PROJECT_ID: 'korlix-test', SOCIAL_NATIVE_FCM_APP_ID: 'com.korlix.app', SOCIAL_NATIVE_FCM_SERVICE_ACCOUNT_FILE: '/private/fcm.json',
  SOCIAL_NATIVE_APNS_ENABLED: 'true', SOCIAL_NATIVE_APNS_APP_ID: 'com.korlix.app', SOCIAL_NATIVE_APNS_TEAM_ID: 'TEAM123456', SOCIAL_NATIVE_APNS_KEY_ID: 'KEY1234567', SOCIAL_NATIVE_APNS_PRIVATE_KEY_FILE: '/private/apns.p8' };
const actor = randomUUID();
const owner = JSON.stringify(['https://project.supabase.co/auth/v1', actor]);
const jwt = (sub = actor, iss = 'https://project.supabase.co/auth/v1') => `header.${Buffer.from(JSON.stringify({ sub, iss })).toString('base64url')}.verified-by-auth-fixture`;
const sub = (provider = 'fcm') => ({ provider, app_id: 'com.korlix.app', environment: 'production', token: provider === 'fcm' ? 'test-fcm-token-1234567890123456' : 'a'.repeat(64) });
const delivery = (extra = {}) => ({ owner, binding: randomUUID(), kind: 'peer', id: randomUUID(), type: 'message', event_id: randomUUID(),
  expires_at: new Date(Date.now() + 300000).toISOString(), subscription: sub(), ...extra });

test('mobile providers require explicit independent flags and expose no credentials', () => {
  assert.equal(socialNativePushConfig({}).enabled, false);
  assert.equal(socialNativePushConfig({ ...env, SOCIAL_NATIVE_PUSH_ENABLED: 'false' }).enabled, false);
  const config = socialNativePushConfig({ ...env, SOCIAL_NATIVE_FCM_ENABLED: 'false' });
  assert.equal(config.providers.fcm.enabled, false);
  assert.equal(config.providers.apns.enabled, true);
  assert(!JSON.stringify(config).includes('/private/'));
  assert.equal(socialNativePushConfig({ ...env, SUPABASE_URL: 'https://user:pass@project.supabase.co' }).enabled, false);
});

test('native subscription validator rejects URLs, wrong packages, malformed tokens and unapproved APNs sandbox', () => {
  assert.deepEqual(validateSocialNativeSubscription(sub(), env), sub());
  for (const patch of [{ token: 'https://attacker.test/token' }, { provider: 'web' }, { app_id: 'com.other.app' }, { environment: 'sandbox' }, { token: 'a'.repeat(2049) }]) {
    assert.throws(() => validateSocialNativeSubscription({ ...sub(), ...patch }, env));
  }
  assert.throws(() => validateSocialNativeSubscription({ ...sub('apns'), environment: 'sandbox' }, env));
  assert.equal(validateSocialNativeSubscription({ ...sub('apns'), environment: 'sandbox', token: 'B'.repeat(80) }, { ...env, SOCIAL_NATIVE_APNS_ALLOW_SANDBOX: 'true' }).token, 'b'.repeat(80));
});

test('owner uses the verified user and trusted issuer, not caller identity fields', () => {
  assert.equal(nativePushOwner({ headers: { authorization: `Bearer ${jwt()}` }, body: { owner: 'spoofed' } }, { id: actor }, env), owner);
  assert.throws(() => nativePushOwner({ headers: { authorization: `Bearer ${jwt(randomUUID())}` } }, { id: actor }, env));
  assert.throws(() => nativePushOwner({ headers: { authorization: `Bearer ${jwt(actor, 'https://other.supabase.co/auth/v1')}` } }, { id: actor }, env));
});

test('native routes authenticate, strip supplied actor/owner, require preferences, and bind unsubscribe', async () => {
  const calls = [], app = express(); app.use(express.json());
  const push = createSocialNativePush({ env, autoStart: false, database: { rpc: async (name, args) => { calls.push({ name, ...args }); return { data: args.p_action === 'state' ? { subscriptions: [] } : { ok: true } }; } },
    authenticate: async (req, res) => { if (req.headers.authorization !== `Bearer ${jwt()}`) { res.status(401).json({ error: 'Sign in' }); return null; } return { id: actor }; } });
  push.register(app);
  const server = app.listen(0, '127.0.0.1'); await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}/api/social/native_push_`;
  const data = { device: randomUUID(), binding: randomUUID(), messages: true, calls: true, online: false, subscription: sub(), owner: 'spoofed', p_actor: randomUUID() };
  const send = (action, body, auth = true, method = 'POST') => fetch(base + action, { method, headers: { 'Content-Type': 'application/json', ...(auth ? { Authorization: `Bearer ${jwt()}` } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
  try {
    assert.equal((await send('subscribe', data, false)).status, 401); assert.equal(calls.length, 0);
    const response = await send('subscribe', data); assert.equal(response.status, 200); assert.equal(response.headers.get('Cache-Control'), 'no-store');
    assert.equal(calls[0].name, 'korlix_social_native_push_v1'); assert.equal(calls[0].p_actor, actor); assert.equal(calls[0].p_data.owner_key, owner); assert.equal(calls[0].p_data.owner, undefined);
    assert.equal((await send('subscribe', { ...data, online: 'false' })).status, 400);
    assert.equal((await send('unsubscribe', { device: data.device })).status, 400);
    assert.equal((await send('unsubscribe', { device: data.device, binding: data.binding, owner: 'spoofed' })).status, 200);
    assert.deepEqual(calls.at(-1).p_data, { device: data.device, binding: data.binding });
    assert.equal((await send('state', undefined, true, 'GET')).status, 200);
  } finally { push.stop(); await new Promise(resolve => server.close(resolve)); }
});

test('native worker reauthorizes leases and only sends generic private payloads', async () => {
  const id = randomUUID(), lease = randomUUID(), sent = [], finishes = [];
  const item = delivery({ body: 'secret private body', name: 'Private Person', silent: true, type: 'online', expires_at: new Date(Date.now() + 90000).toISOString() });
  const push = createSocialNativePush({ env, autoStart: false, sender: async (...args) => sent.push(args), database: { rpc: async (_, args) => {
    if (args.p_action === 'claim') return { data: { items: [{ id, lease }] } };
    if (args.p_action === 'authorize') { assert.deepEqual(args.p_data, { id, lease }); return { data: { delivery: item } }; }
    finishes.push(args.p_data); return { data: { ok: true } };
  } } });
  await push.tick(); push.stop();
  assert.equal(sent.length, 1); assert.equal(sent[0][1].owner, owner); assert.equal(sent[0][1].silent, true); assert(sent[0][2].ttl <= 90);
  assert(!JSON.stringify(sent[0][1]).includes('Private Person')); assert(!JSON.stringify(sent[0][1]).includes('secret private body'));
  assert.deepEqual(finishes, [{ id, lease, status: 'accepted' }]);
});

test('native worker skips revoked/expired deliveries and never sends while disabled', async () => {
  let sent = 0, calls = 0;
  const push = createSocialNativePush({ env: {}, autoStart: false, sender: async () => sent++, database: { rpc: async () => { calls++; } } });
  await push.tick(); assert.equal(calls, 0); push.stop();
  const active = createSocialNativePush({ env, autoStart: false, sender: async () => sent++, database: { rpc: async (_, args) => ({ data: args.p_action === 'claim' ? { items: [{ id: randomUUID(), lease: randomUUID() }] } : args.p_action === 'authorize' ? { delivery: null } : { ok: true } }) } });
  await active.tick(); active.stop(); assert.equal(sent, 0);
  for (const [settings, queued] of [
    [env, delivery({ expires_at: new Date(Date.now() - 1000).toISOString() })],
    [{ ...env, SOCIAL_NATIVE_FCM_ENABLED: 'false' }, delivery()],
  ]) {
    const finished = [];
    const candidate = createSocialNativePush({ env: settings, autoStart: false, sender: async () => sent++, database: { rpc: async (_, args) => {
      if (args.p_action === 'claim') return { data: { items: [{ id: randomUUID(), lease: randomUUID() }] } };
      if (args.p_action === 'authorize') return { data: { delivery: queued } };
      finished.push(args.p_data.status); return { data: { ok: true } };
    } } });
    await candidate.tick(); candidate.stop(); assert.deepEqual(finished, ['cancelled']);
  }
  assert.equal(sent, 0);
});

test('delivery outcomes remove only dead device tokens and do not retry uncertain delivery', () => {
  assert.equal(nativeDeliveryOutcome({ statusCode: 404, providerCode: 'UNREGISTERED' }, true), 'expired');
  assert.equal(nativeDeliveryOutcome({ statusCode: 400, providerCode: 'BadDeviceToken' }, true), 'expired');
  assert.equal(nativeDeliveryOutcome({ statusCode: 404, providerCode: 'NOT_FOUND' }, true), 'failed');
  assert.equal(nativeDeliveryOutcome({ statusCode: 401 }, true), 'failed');
  assert.equal(nativeDeliveryOutcome({ statusCode: 503 }, true), 'retry');
  assert.equal(nativeDeliveryOutcome(Error('connection lost'), true), 'unknown');
});

test('FCM is data-only with a package restriction, bounded lifetime and OAuth', async () => {
  const requests = [];
  const sender = createNativePushSender({ env, googleToken: async () => 'fixture-oauth', fetcher: async (...args) => { requests.push(args); return { ok: true, status: 200 }; } });
  const payload = nativeDeliveryPayload(delivery());
  await sender(sub(), payload, { ttl: 42 });
  const [url, options] = requests[0], request = JSON.parse(options.body);
  assert.equal(url, 'https://fcm.googleapis.com/v1/projects/korlix-test/messages:send'); assert.equal(options.headers.Authorization, 'Bearer fixture-oauth');
  assert.equal(request.message.notification, undefined); assert.equal(request.message.android.notification, undefined);
  assert.equal(request.message.data.owner, owner); assert.equal(request.message.data.silent, 'false'); assert.equal(request.message.android.ttl, '42s');
  assert.equal(request.message.android.restricted_package_name, 'com.korlix.app'); assert.equal(request.message.android.priority, 'HIGH');
  assert.equal(options.redirect, 'error');
  const rejected = createNativePushSender({ env, googleToken: async () => 'fixture-oauth', fetcher: async () => new Response(JSON.stringify({ error: { details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'UNREGISTERED' }] } }), { status: 404 }) });
  await assert.rejects(rejected(sub(), payload, { ttl: 30 }), error => nativeDeliveryOutcome(error, true) === 'expired');
});

test('provider retry delay honors seconds/date headers and OAuth failures remain known pre-send', async () => {
  assert.equal(nativeRetryAfter('120'), 120); assert.equal(nativeRetryAfter(''), 60);
  assert.equal(nativeRetryAfter(new Date(200000).toUTCString(), 100000), 100);
  let requests = 0, refreshes = 0;
  const sender = createNativePushSender({ env, googleToken: async () => { refreshes++; await new Promise(resolve => setTimeout(resolve, 5)); throw Error('OAuth unavailable'); }, fetcher: async () => requests++ });
  const results = await Promise.allSettled(Array.from({ length: 4 }, () => sender(sub(), nativeDeliveryPayload(delivery()), { ttl: 60 })));
  assert.equal(requests, 0); assert.equal(refreshes, 1);
  for (const result of results) { assert.equal(result.status, 'rejected'); assert.equal(nativeDeliveryOutcome(result.reason, true), 'retry'); }
  const throttled = createNativePushSender({ env, googleToken: async () => 'oauth', fetcher: async () => new Response('x'.repeat(18000), { status: 503, headers: { 'Retry-After': '125' } }) });
  await assert.rejects(throttled(sub(), nativeDeliveryPayload(delivery()), { ttl: 180 }), error => error.retryAfterSeconds === 125 && nativeDeliveryOutcome(error, true) === 'retry');
  for (const body of ['null', '{"error":{"details":{}}}', '{"error":{"details":[null]}}']) {
    const malformed = createNativePushSender({ env, googleToken: async () => 'oauth', fetcher: async () => new Response(body, { status: 503, headers: { 'Retry-After': '125' } }) });
    await assert.rejects(malformed(sub(), nativeDeliveryPayload(delivery()), { ttl: 180 }), error => error.retryAfterSeconds === 125 && nativeDeliveryOutcome(error, true) === 'retry');
  }
  const accepted = createNativePushSender({ env, googleToken: async () => 'oauth', fetcher: async () => ({ ok: true, status: 200, body: { cancel: async () => { throw Error('cleanup'); } } }) });
  assert.equal((await accepted(sub(), nativeDeliveryPayload(delivery()), { ttl: 100 })).statusCode, 200);
});

test('APNs reuses one session per environment and closes bounded sessions on stop', async () => {
  const sessions = [];
  const transport = createApnsHttp2Transport({ connector: origin => {
    const session = new EventEmitter(); session.origin = origin; session.closed = false; session.destroyed = false;
    session.close = () => { session.closed = true; session.emit('close'); };
    session.destroy = () => { session.destroyed = true; session.emit('close'); };
    session.request = () => {
      const stream = new EventEmitter(); stream.setEncoding = () => {}; stream.close = () => {};
      stream.end = () => queueMicrotask(() => { stream.emit('response', { ':status': 200 }); stream.emit('end'); });
      return stream;
    };
    sessions.push(session); return session;
  } });
  const request = { origin: 'https://api.push.apple.com', headers: {}, body: '{}' };
  await Promise.all([transport(request), transport(request)]);
  await transport(request); assert.equal(sessions.length, 1); assert.equal(sessions[0].closed, false);
  await transport({ ...request, origin: 'https://api.sandbox.push.apple.com' }); assert.equal(sessions.length, 2);
  sessions[0].emit('goaway'); await transport(request); assert.equal(sessions.length, 3); assert.equal(sessions[0].closed, true);
  transport.close(); assert(sessions.slice(1).every(session => session.destroyed));
});

test('APNs uses ES256 HTTP/2 alert, generic content, message-only reply category and sandbox guard', async () => {
  const folder = await mkdtemp(join(tmpdir(), 'korlix-apns-test-'));
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const path = join(folder, 'test.p8'); await writeFile(path, privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600 });
  const requests = [];
  const sender = createNativePushSender({ env: { ...env, SOCIAL_NATIVE_APNS_PRIVATE_KEY_FILE: path }, apnsRequest: async args => requests.push(args) });
  try {
    await sender(sub('apns'), nativeDeliveryPayload(delivery({ silent: true })), { ttl: 50 });
    const request = requests[0], payload = JSON.parse(request.body);
    assert.equal(request.origin, 'https://api.push.apple.com'); assert.equal(request.headers['apns-push-type'], 'alert');
    assert.equal(payload.aps.category, 'KORLIX_SOCIAL_MESSAGE'); assert.equal(payload.aps.sound, undefined); assert.equal(payload.owner, owner);
    const token = request.headers.authorization.slice(7), [head, body, signature] = token.split('.');
    assert.equal(JSON.parse(Buffer.from(head, 'base64url')).alg, 'ES256');
    assert(verify('sha256', Buffer.from(`${head}.${body}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')));
    await sender(sub('apns'), nativeDeliveryPayload(delivery({ type: 'call' })), { ttl: 40 });
    assert.equal(JSON.parse(requests[1].body).aps.category, 'KORLIX_SOCIAL_OPEN');
  } finally { await rm(folder, { recursive: true, force: true }); }
});
