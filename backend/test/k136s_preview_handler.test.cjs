'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { createPreviewHandler } = require('../k136s_learning/http/preview_handler.cjs');
const { mintGrant, signGrant, verifyGrant } = require('../k136s_learning/http/grant.cjs');
const { createServer } = require('../k136s_learning/http/preview_server.cjs');

const KEY = 'test-key-0123456789-abcdef'; // >= 16 chars
const NOW = Date.UTC(2026, 8, 6, 12, 0, 0);
const at = (t) => () => t;

// ---------- grant crypto ----------
test('grant: mint then verify round-trips and is bound to the agent and audience', () => {
  const { token, payload } = mintGrant({ agentId: 'agent-1', now: NOW, key: KEY });
  assert.equal(payload.aud, 'k136s-preview');
  const v = verifyGrant(token, { now: NOW, key: KEY });
  assert.equal(v.ok, true); assert.equal(v.payload.agentId, 'agent-1');
});

test('grant: expiry, tampering, wrong key and wrong audience all fail closed', () => {
  const { token } = mintGrant({ agentId: 'agent-1', now: NOW, ttlMs: 60000, key: KEY });
  assert.equal(verifyGrant(token, { now: NOW + 63000, key: KEY }).code, 'EXPIRED'); // past ttl + skew
  assert.equal(verifyGrant(token.slice(0, -2) + 'AA', { now: NOW, key: KEY }).code, 'BAD_SIGNATURE');
  assert.equal(verifyGrant(token, { now: NOW, key: 'another-key-0123456789' }).code, 'BAD_SIGNATURE');
  const wrongAud = signGrant({ aud: 'something-else', agentId: 'agent-1', iat: NOW, exp: NOW + 60000 }, KEY);
  assert.equal(verifyGrant(wrongAud, { now: NOW, key: KEY }).code, 'WRONG_AUDIENCE');
  assert.equal(verifyGrant('not-a-token', { now: NOW, key: KEY }).code, 'MALFORMED');
  assert.equal(verifyGrant(signGrant({ aud: 'k136s-preview', agentId: 'a', iat: NOW + 10000, exp: NOW + 70000 }, KEY), { now: NOW, key: KEY }).code, 'NOT_YET_VALID');
});

// ---------- pure handler ----------
function handler(allowDevGrant = true) { return createPreviewHandler({ key: KEY, allowDevGrant, now: at(NOW) }); }
function grantFor(agentId) { return mintGrant({ agentId, now: NOW, key: KEY }).token; }

test('handler: health reports the version and dev-grant flag', () => {
  const r = handler(true)({ method: 'GET', path: '/k136s/health' });
  assert.equal(r.status, 200); assert.equal(r.json.ok, true); assert.equal(r.json.version, 'C1'); assert.equal(r.json.devGrant, true);
});

test('handler: preview requires a valid grant', () => {
  const h = handler(true);
  const noGrant = h({ method: 'POST', path: '/k136s/preview', headers: {}, rawBody: JSON.stringify({ agentId: 'a1', proposedText: 'Always greet callers warmly.' }) });
  assert.equal(noGrant.status, 401); assert.equal(noGrant.json.code, 'MALFORMED');
  const expired = mintGrant({ agentId: 'a1', now: NOW - 120000, ttlMs: 60000, key: KEY }).token;
  const r = h({ method: 'POST', path: '/k136s/preview', headers: { 'x-k136s-grant': expired }, rawBody: JSON.stringify({ agentId: 'a1', proposedText: 'Always greet callers warmly.' }) });
  assert.equal(r.status, 401); assert.equal(r.json.code, 'EXPIRED');
});

test('handler: a grant issued for one agent cannot preview another', () => {
  const r = handler(true)({ method: 'POST', path: '/k136s/preview', headers: { 'x-k136s-grant': grantFor('a1') }, rawBody: JSON.stringify({ agentId: 'a2', proposedText: 'Remember Acme prefers mornings.' }) });
  assert.equal(r.status, 403); assert.equal(r.json.code, 'AGENT_MISMATCH');
});

test('handler: happy-path preview returns classification, policy, diff and a content hash — and no approval token', () => {
  const r = handler(true)({ method: 'POST', path: '/k136s/preview', headers: { 'x-k136s-grant': grantFor('a1') },
    rawBody: JSON.stringify({ agentId: 'a1', proposedText: 'nova, remember that Acme prefers morning calls', currentText: 'Acme prefers afternoon calls.' }) });
  assert.equal(r.status, 200);
  assert.equal(r.json.normalizedText, 'Remember that Acme prefers morning calls.');
  assert.equal(r.json.classification.type, 'MEMORY');
  assert.equal(r.json.policy.allowed, true);
  assert.match(r.json.contentHash, /^[0-9a-f]{64}$/);
  assert.equal(r.json.diff.changed, true);
  assert.ok(!('approvalToken' in r.json) && !('token' in r.json), 'preview must not issue an approval token');
});

test('handler: a preview is pure — identical inputs yield an identical hash', () => {
  const body = JSON.stringify({ agentId: 'a1', proposedText: 'Always escalate billing disputes to Maria.' });
  const one = handler(true)({ method: 'POST', path: '/k136s/preview', headers: { 'x-k136s-grant': grantFor('a1') }, rawBody: body });
  const two = handler(true)({ method: 'POST', path: '/k136s/preview', headers: { 'x-k136s-grant': grantFor('a1') }, rawBody: body });
  assert.equal(one.json.contentHash, two.json.contentHash);
  assert.equal(one.json.classification.type, 'TRAINING');
});

test('handler: prohibited content yields a successful preview that shows the rejection', () => {
  const r = handler(true)({ method: 'POST', path: '/k136s/preview', headers: { 'x-k136s-grant': grantFor('a1') },
    rawBody: JSON.stringify({ agentId: 'a1', proposedText: 'Remember the client password is hunter2.' }) });
  assert.equal(r.status, 200);
  assert.equal(r.json.classification.type, 'PROHIBITED');
  assert.equal(r.json.policy.allowed, false);
  assert.ok(r.json.policy.violations.some((v) => v.code === 'PROHIBITED_TYPE'));
});

test('handler: an accepted override is reflected in the preview', () => {
  const r = handler(true)({ method: 'POST', path: '/k136s/preview', headers: { 'x-k136s-grant': grantFor('a1') },
    rawBody: JSON.stringify({ agentId: 'a1', proposedText: 'Acme prefers morning calls.', overrides: { category: 'scheduling' } }) });
  assert.equal(r.status, 200);
  assert.equal(r.json.classification.category, 'scheduling');
  assert.ok(r.json.classification.overrides.some((o) => o.field === 'category' && o.to === 'scheduling'));
});

test('handler: overriding a prohibited classification is refused', () => {
  const r = handler(true)({ method: 'POST', path: '/k136s/preview', headers: { 'x-k136s-grant': grantFor('a1') },
    rawBody: JSON.stringify({ agentId: 'a1', proposedText: 'Remember the api key is 123.', overrides: { type: 'MEMORY' } }) });
  assert.equal(r.status, 422); assert.equal(r.json.code, 'PROHIBITED_IMMUTABLE');
});

test('handler: bad JSON and missing fields are rejected; dev-grant issues a usable grant', () => {
  const h = handler(true);
  assert.equal(h({ method: 'POST', path: '/k136s/preview', headers: { 'x-k136s-grant': grantFor('a1') }, rawBody: '{not json' }).status, 400);
  assert.equal(h({ method: 'POST', path: '/k136s/preview', headers: { 'x-k136s-grant': grantFor('a1') }, rawBody: JSON.stringify({ agentId: 'a1' }) }).status, 400);
  const dev = h({ method: 'POST', path: '/k136s/grant/dev', headers: {}, rawBody: JSON.stringify({ agentId: 'a1' }) });
  assert.equal(dev.status, 200); assert.equal(verifyGrant(dev.json.grant, { now: NOW, key: KEY }).ok, true);
});

test('handler: the dev-grant endpoint is absent unless explicitly enabled', () => {
  const r = handler(false)({ method: 'POST', path: '/k136s/grant/dev', headers: {}, rawBody: JSON.stringify({ agentId: 'a1' }) });
  assert.equal(r.status, 404);
});

test('handler: trailing slashes and query strings are tolerated; unknown routes are 404', () => {
  assert.equal(handler(true)({ method: 'GET', path: '/k136s/health/?x=1' }).status, 200);
  assert.equal(handler(true)({ method: 'GET', path: '/k136s/nope' }).status, 404);
  assert.equal(handler(true)({ method: 'DELETE', path: '/k136s/preview' }).status, 404);
});

// ---------- real node:http server round-trip (ephemeral loopback port) ----------
function request(port, method, path, { headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : Buffer.from(body, 'utf8');
    const req = http.request({ host: '127.0.0.1', port, method, path, headers: Object.assign({ 'content-type': 'application/json' }, headers, data ? { 'content-length': data.length } : {}) }, (res) => {
      const chunks = []; res.on('data', (c) => chunks.push(c)); res.on('end', () => { const t = Buffer.concat(chunks).toString('utf8'); let j = null; try { j = JSON.parse(t); } catch { /* leave null */ } resolve({ status: res.statusCode, json: j }); });
    });
    req.on('error', reject);
    if (data) req.write(data); req.end();
  });
}

test('server: end-to-end over a real socket — health, dev grant, then a gated preview', async () => {
  const server = createServer({ key: KEY, allowDevGrant: true, now: Date.now });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  try {
    const health = await request(port, 'GET', '/k136s/health');
    assert.equal(health.status, 200); assert.equal(health.json.version, 'C1');

    const dev = await request(port, 'POST', '/k136s/grant/dev', { body: JSON.stringify({ agentId: 'agent-x' }) });
    assert.equal(dev.status, 200); assert.ok(dev.json.grant);

    const denied = await request(port, 'POST', '/k136s/preview', { body: JSON.stringify({ agentId: 'agent-x', proposedText: 'Always confirm the callback number.' }) });
    assert.equal(denied.status, 401);

    const ok = await request(port, 'POST', '/k136s/preview', { headers: { 'x-k136s-grant': dev.json.grant }, body: JSON.stringify({ agentId: 'agent-x', proposedText: 'Always confirm the callback number.' }) });
    assert.equal(ok.status, 200); assert.equal(ok.json.classification.type, 'TRAINING'); assert.equal(ok.json.policy.allowed, true);
  } finally {
    await new Promise((r) => server.close(r));
  }
});

test('server: a body over the cap is rejected with 413 and never reaches the handler', async () => {
  const server = createServer({ key: KEY, allowDevGrant: true, now: Date.now, maxBodyBytes: 1024 });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  try {
    const big = 'x'.repeat(4096);
    const res = await request(port, 'POST', '/k136s/preview', { headers: { 'x-k136s-grant': grantFor('a1') }, body: JSON.stringify({ agentId: 'a1', proposedText: big }) });
    assert.equal(res.status, 413);
  } finally {
    await new Promise((r) => server.close(r));
  }
});
