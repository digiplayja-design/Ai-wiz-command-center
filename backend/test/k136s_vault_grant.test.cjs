'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { issueVaultGrant, createHttpVerifier, parseRelayHeaders } = require('../k136s_learning/http/vault_grant_issuer.cjs');
const { createPreviewHandler } = require('../k136s_learning/http/preview_handler.cjs');
const { verifyGrant } = require('../k136s_learning/http/grant.cjs');
const { createServer } = require('../k136s_learning/http/preview_server.cjs');

const KEY = 'test-key-0123456789-abcdef';
const NOW = Date.UTC(2026, 8, 6, 12, 0, 0);
const PW = 'correct-horse-battery-staple-XYZ'; // the fixture password; must never appear in any output
const OK_BODY = { success: true, verified: true, managerMode: 'account_owner', passwordVersion: 3, unlockExpiresAt: '2026-09-06T12:15:00.000Z' };

// capture console output for the leak assertions
function withCapturedConsole(fn) {
  const lines = [];
  const orig = { log: console.log, error: console.error, warn: console.warn, info: console.info };
  for (const k of Object.keys(orig)) console[k] = (...a) => lines.push(a.map(String).join(' '));
  return Promise.resolve().then(fn).finally(() => { for (const k of Object.keys(orig)) console[k] = orig[k]; }).then((r) => ({ result: r, lines }));
}
const fakeVerifier = (status, body) => async () => ({ status, body });
const base = (over = {}) => Object.assign({ agentId: 'agent-1', vaultPassword: PW, headers: { authorization: 'Bearer tok-abc', cookie: 'sid=1' }, key: KEY, now: () => NOW }, over);

// ---------- issuer outcomes ----------
test('issuer: success && verified mints a grant bound to the agent, carrying passwordVersion and managerMode', async () => {
  const r = await issueVaultGrant(base({ verify: fakeVerifier(200, OK_BODY) }));
  assert.equal(r.status, 200);
  assert.equal(r.json.managerMode, 'account_owner'); assert.equal(r.json.passwordVersion, 3);
  const v = verifyGrant(r.json.grant, { now: NOW, key: KEY });
  assert.equal(v.ok, true); assert.equal(v.payload.agentId, 'agent-1'); assert.equal(v.payload.pv, 3); assert.equal(v.payload.mgr, 'account_owner');
  assert.equal(r.json.expiresAt, NOW + 60000);
});

test('issuer: backend 401 incorrect -> 401 with the backend code and no grant', async () => {
  const r = await issueVaultGrant(base({ verify: fakeVerifier(401, { success: false, code: 'brain_vault_password_incorrect' }) }));
  assert.equal(r.status, 401); assert.equal(r.json.code, 'brain_vault_password_incorrect'); assert.ok(!('grant' in r.json));
});

test('issuer: backend 429 rate-limited -> 429, lockout relayed, no grant', async () => {
  const r = await issueVaultGrant(base({ verify: fakeVerifier(429, { success: false, code: 'brain_vault_password_rate_limited', lockedUntil: '2026-09-06T12:15:00.000Z' }) }));
  assert.equal(r.status, 429); assert.equal(r.json.code, 'brain_vault_password_rate_limited'); assert.equal(r.json.lockedUntil, '2026-09-06T12:15:00.000Z'); assert.ok(!('grant' in r.json));
});

test('issuer: 409 not-configured and 403 not-manager are relayed without a grant', async () => {
  const a = await issueVaultGrant(base({ verify: fakeVerifier(409, { code: 'brain_vault_password_not_configured' }) }));
  assert.equal(a.status, 409); assert.equal(a.json.code, 'brain_vault_password_not_configured'); assert.ok(!('grant' in a.json));
  const b = await issueVaultGrant(base({ verify: fakeVerifier(403, { code: 'brain_vault_forbidden' }) }));
  assert.equal(b.status, 403); assert.ok(!('grant' in b.json));
});

test('issuer: a 200 that is not success&&verified is refused (502), never granted', async () => {
  for (const body of [{ success: true, verified: false }, { success: false, verified: true }, { ok: true }, null]) {
    const r = await issueVaultGrant(base({ verify: fakeVerifier(200, body) }));
    assert.equal(r.status, 502, JSON.stringify(body)); assert.equal(r.json.code, 'BACKEND_UNEXPECTED'); assert.ok(!('grant' in r.json));
  }
});

test('issuer: backend unreachable / timeout -> 503, no grant; missing verifier -> 503 not configured', async () => {
  const r = await issueVaultGrant(base({ verify: async () => { throw new Error('ECONNREFUSED'); } }));
  assert.equal(r.status, 503); assert.equal(r.json.code, 'BACKEND_UNAVAILABLE'); assert.ok(!('grant' in r.json));
  const n = await issueVaultGrant(base({ verify: undefined }));
  assert.equal(n.status, 503); assert.equal(n.json.code, 'VAULT_ISSUER_NOT_CONFIGURED');
});

test('issuer: missing agentId or vaultPassword is a 400 and the backend is never called', async () => {
  let calls = 0; const spy = async () => { calls++; return { status: 200, body: OK_BODY }; };
  assert.equal((await issueVaultGrant(base({ agentId: '', verify: spy }))).status, 400);
  assert.equal((await issueVaultGrant(base({ vaultPassword: '', verify: spy }))).status, 400);
  assert.equal(calls, 0);
});

// ---------- header relay allow-list ----------
test('relay: only allow-listed headers are forwarded; everything else is dropped; the list is configurable', async () => {
  let seen = null; const spy = async ({ relayHeaders }) => { seen = relayHeaders; return { status: 200, body: OK_BODY }; };
  await issueVaultGrant(base({ headers: { Authorization: 'Bearer tok-abc', Cookie: 'sid=1', 'x-forwarded-for': '1.2.3.4', 'x-k136s-grant': 'should-not-relay', host: 'evil' }, verify: spy }));
  assert.deepEqual(seen, { authorization: 'Bearer tok-abc', cookie: 'sid=1' });
  await issueVaultGrant(base({ headers: { authorization: 'Bearer x', 'x-korlix-session': 's-1' }, verify: spy, relayHeaderNames: 'x-korlix-session' }));
  assert.deepEqual(seen, { 'x-korlix-session': 's-1' });
  assert.deepEqual([...parseRelayHeaders('')], ['authorization', 'cookie']);
  assert.deepEqual([...parseRelayHeaders(' Authorization , X-Custom ')], ['authorization', 'x-custom']);
});

// ---------- the password never leaks ----------
test('safety: the password appears in no response and no console line, across every outcome', async () => {
  const outcomes = [fakeVerifier(200, OK_BODY), fakeVerifier(401, { code: 'brain_vault_password_incorrect' }), fakeVerifier(429, { code: 'brain_vault_password_rate_limited' }), fakeVerifier(200, null), async () => { throw new Error('boom ' + 'x'); }];
  const { result, lines } = await withCapturedConsole(async () => {
    const outs = [];
    for (const verify of outcomes) outs.push(await issueVaultGrant(base({ verify })));
    return outs;
  });
  for (const r of result) assert.equal(JSON.stringify(r).includes(PW), false, 'password leaked into a response');
  assert.equal(lines.join('\n').includes(PW), false, 'password leaked into console output');
  // and it is not inside the grant token payload either
  const ok = result[0]; const payload = JSON.parse(Buffer.from(ok.json.grant.split('.')[0], 'base64url').toString('utf8'));
  assert.equal(JSON.stringify(payload).includes(PW), false);
});

// ---------- handler wiring ----------
test('handler: POST /k136s/grant is served by handle.async; sync handle and C routes are unchanged', async () => {
  const h = createPreviewHandler({ key: KEY, allowDevGrant: false, now: () => NOW, vaultVerifier: fakeVerifier(200, OK_BODY) });
  const health = h({ method: 'GET', path: '/k136s/health' });
  assert.equal(health.json.version, 'C1'); assert.equal(health.json.build, 'D1'); assert.equal(health.json.vaultGrant, true); assert.equal(health.json.devGrant, false);
  const g = await h.async({ method: 'POST', path: '/k136s/grant', headers: { authorization: 'Bearer t' }, rawBody: JSON.stringify({ agentId: 'a1', vaultPassword: PW }) });
  assert.equal(g.status, 200); assert.equal(verifyGrant(g.json.grant, { now: NOW, key: KEY }).ok, true);
  // the grant then unlocks a preview
  const p = await h.async({ method: 'POST', path: '/k136s/preview', headers: { 'x-k136s-grant': g.json.grant }, rawBody: JSON.stringify({ agentId: 'a1', proposedText: 'Always confirm the callback number.' }) });
  assert.equal(p.status, 200); assert.equal(p.json.policy.allowed, true);
  // without a verifier the issuer is off (503), and dev-grant stays absent unless enabled
  const off = createPreviewHandler({ key: KEY, now: () => NOW });
  assert.equal((await off.async({ method: 'POST', path: '/k136s/grant', headers: {}, rawBody: JSON.stringify({ agentId: 'a1', vaultPassword: PW }) })).json.code, 'VAULT_ISSUER_NOT_CONFIGURED');
  assert.equal((off({ method: 'GET', path: '/k136s/health' })).json.vaultGrant, false);
  assert.equal((await off.async({ method: 'POST', path: '/k136s/grant/dev', headers: {}, rawBody: '{"agentId":"a1"}' })).status, 404);
  assert.equal((await off.async({ method: 'POST', path: '/k136s/grant', headers: {}, rawBody: '{bad' })).status, 400);
});

// ---------- real socket: forward to an in-process fake backend ----------
function fakeBackend(onReq) {
  return http.createServer((req, res) => {
    const chunks = []; req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      let body = {}; try { body = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'); } catch { body = {}; }
      const out = onReq({ method: req.method, url: req.url, headers: req.headers, body });
      const payload = Buffer.from(JSON.stringify(out.body), 'utf8');
      res.writeHead(out.status, { 'content-type': 'application/json', 'content-length': payload.length }); res.end(payload);
    });
  });
}
function request(port, method, path, { headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : Buffer.from(body, 'utf8');
    const req = http.request({ host: '127.0.0.1', port, method, path, headers: Object.assign({ 'content-type': 'application/json' }, headers, data ? { 'content-length': data.length } : {}) }, (res) => {
      const c = []; res.on('data', (x) => c.push(x)); res.on('end', () => { let j = null; try { j = JSON.parse(Buffer.concat(c).toString('utf8')); } catch { /* null */ } resolve({ status: res.statusCode, json: j }); });
    });
    req.on('error', reject); if (data) req.write(data); req.end();
  });
}
const listen = (srv) => new Promise((r) => srv.listen(0, '127.0.0.1', () => r(srv.address().port)));
const close = (srv) => new Promise((r) => srv.close(r));

test('socket: grant forwards exactly once to the real verify path with relayed auth, then unlocks a preview', async () => {
  const received = [];
  const backend = fakeBackend(({ url, headers, body }) => {
    received.push({ url, auth: headers.authorization, extra: headers['x-k136s-grant'], pw: body.vaultPassword });
    if (url !== '/api/brain-vault/password/verify') return { status: 404, body: { code: 'nope' } };
    if (!headers.authorization) return { status: 401, body: { success: false, code: 'unauthenticated' } };
    if (body.vaultPassword !== PW) return { status: 401, body: { success: false, code: 'brain_vault_password_incorrect' } };
    return { status: 200, body: OK_BODY };
  });
  const bport = await listen(backend);
  const preview = createServer({ key: KEY, now: Date.now, vaultVerifier: createHttpVerifier({ backendUrl: `http://127.0.0.1:${bport}`, timeoutMs: 2000 }) });
  const pport = await listen(preview);
  try {
    const ok = await request(pport, 'POST', '/k136s/grant', { headers: { authorization: 'Bearer real-tok', 'x-k136s-grant': 'junk' }, body: JSON.stringify({ agentId: 'agent-x', vaultPassword: PW }) });
    assert.equal(ok.status, 200); assert.ok(ok.json.grant); assert.equal(ok.json.passwordVersion, 3);
    assert.equal(received.length, 1, 'forwarded exactly once');
    assert.equal(received[0].url, '/api/brain-vault/password/verify');
    assert.equal(received[0].auth, 'Bearer real-tok', 'authorization relayed');
    assert.equal(received[0].extra, undefined, 'non-allow-listed header NOT relayed');
    assert.equal(received[0].pw, PW, 'backend received the password field as vaultPassword');

    const bad = await request(pport, 'POST', '/k136s/grant', { headers: { authorization: 'Bearer real-tok' }, body: JSON.stringify({ agentId: 'agent-x', vaultPassword: 'wrong' }) });
    assert.equal(bad.status, 401); assert.equal(bad.json.code, 'brain_vault_password_incorrect'); assert.ok(!bad.json.grant);

    const noauth = await request(pport, 'POST', '/k136s/grant', { body: JSON.stringify({ agentId: 'agent-x', vaultPassword: PW }) });
    assert.equal(noauth.status, 401); assert.equal(noauth.json.code, 'unauthenticated');

    const prev = await request(pport, 'POST', '/k136s/preview', { headers: { 'x-k136s-grant': ok.json.grant }, body: JSON.stringify({ agentId: 'agent-x', proposedText: 'Remember Acme prefers morning calls.' }) });
    assert.equal(prev.status, 200); assert.equal(prev.json.classification.type, 'MEMORY');
    assert.equal(received.length, 3, 'preview did not contact the backend');
  } finally { await close(preview); await close(backend); }
});

test('socket: backend refusing/hanging -> 503, never a grant (deterministic: no reliance on an unbound port)', async () => {
  // "down" backend: accepts the TCP connection and immediately destroys it -> ECONNRESET every time.
  // (An unbound ephemeral port can be re-bound by a parallel test process; this cannot.)
  const resetting = http.createServer(() => {});
  resetting.on('connection', (sock) => sock.destroy());
  const rport = await listen(resetting);
  const down = createServer({ key: KEY, now: Date.now, vaultVerifier: createHttpVerifier({ backendUrl: `http://127.0.0.1:${rport}`, timeoutMs: 1000 }) });
  // "hanging" backend: accepts and never answers -> verifier timeout.
  const sockets = new Set();
  const hanging = http.createServer(() => { /* never responds */ });
  hanging.on('connection', (sock) => { sockets.add(sock); sock.on('close', () => sockets.delete(sock)); });
  const hport = await listen(hanging);
  const slow = createServer({ key: KEY, now: Date.now, vaultVerifier: createHttpVerifier({ backendUrl: `http://127.0.0.1:${hport}`, timeoutMs: 200 }) });
  const dport = await listen(down); const sport = await listen(slow);
  try {
    const r1 = await request(dport, 'POST', '/k136s/grant', { headers: { authorization: 'Bearer t' }, body: JSON.stringify({ agentId: 'a', vaultPassword: PW }) });
    assert.equal(r1.status, 503); assert.equal(r1.json.code, 'BACKEND_UNAVAILABLE'); assert.ok(!r1.json.grant);
    const r2 = await request(sport, 'POST', '/k136s/grant', { headers: { authorization: 'Bearer t' }, body: JSON.stringify({ agentId: 'a', vaultPassword: PW }) });
    assert.equal(r2.status, 503); assert.equal(r2.json.code, 'BACKEND_UNAVAILABLE'); assert.ok(!r2.json.grant);
  } finally {
    await close(down); await close(slow);
    for (const sock of sockets) sock.destroy();
    await close(hanging); await close(resetting);
  }
});
