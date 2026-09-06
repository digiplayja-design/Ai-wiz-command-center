'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { createMemoryStore } = require('../k136s_learning/adapters/memory_store.cjs');
const { createApprovalService } = require('../k136s_learning/services/approval_service.cjs');
const { createFakeMemoryWriter, createBackendMemoryWriter, toBackendSaveBody, deriveMemoryKey } = require('../k136s_learning/adapters/memory_writer.cjs');
const { createApprovalRoutes } = require('../k136s_learning/http/approval_routes.cjs');
const { createPreviewHandler } = require('../k136s_learning/http/preview_handler.cjs');
const { mintGrant } = require('../k136s_learning/http/grant.cjs');
const { createServer } = require('../k136s_learning/http/preview_server.cjs');
const { normalize, contentHash } = require('../k136s_learning/domain/normalize_diff.cjs');

const KEY = 'test-key-0123456789-abcdef';
const T0 = Date.UTC(2026, 8, 6, 12, 0, 0);
const ID = { userId: 'mgr-1', accountId: 'acct-1' };
const AGENT = 'agent-1';

function fixture({ writer, identity, now } = {}) {
  let t = now === undefined ? T0 : now;
  const clock = () => t; const tick = (ms) => { t += ms; };
  const store = createMemoryStore();
  const approvals = createApprovalService({ store, now: clock });
  const w = writer === undefined ? createFakeMemoryWriter({ now: clock }) : writer;
  const idf = identity === undefined ? () => ID : identity;
  const routes = createApprovalRoutes({ store, approvals, writer: w, identity: idf, now: clock });
  const handler = createPreviewHandler({ key: KEY, now: clock, approvalRoutes: routes });
  const grant = (agentId = AGENT, at = t) => mintGrant({ agentId, now: at, key: KEY }).token;
  const grantPayload = (agentId = AGENT, at = t) => mintGrant({ agentId, now: at, key: KEY }).payload;
  return { store, approvals, writer: w, routes, handler, grant, grantPayload, tick, clock };
}
function changeFor(text, extra = {}) {
  const normalizedText = normalize(text);
  const type = extra.type || 'MEMORY', category = extra.category || 'preference', sensitivity = extra.sensitivity || 'low', expiresAt = extra.expiresAt || null;
  return { preview: { normalizedText, type, category, sensitivity, expiresAt, memoryKey: extra.memoryKey }, contentHash: contentHash({ agentId: AGENT, text: normalizedText, type, category, sensitivity, expiresAt }) };
}
const H = () => ({ 'x-k136s-grant': 'unused-in-direct-calls' });

// ---------- writer adapter ----------
test('writer: toBackendSaveBody maps a change onto the memories columns, sets the confirmation flag, and records supersede info', () => {
  const change = { normalizedText: 'Acme prefers morning calls.', type: 'MEMORY', category: 'preference', sensitivity: 'low', expiresAt: null, contentHash: 'h1' };
  const body = toBackendSaveBody({ change, memoryKey: 'k1', previous: { contentHash: 'h0', content: 'Old.', at: 'then' }, sessionId: 's1', approvalId: 'a1' });
  assert.equal(body.memory_key, 'k1'); assert.equal(body.key, 'k1'); assert.equal(body.content, change.normalizedText); assert.equal(body.memory_text, change.normalizedText);
  assert.equal(body.memory_type, 'memory'); assert.equal(body.kind, 'fact'); assert.equal(body.scope, 'agent'); assert.equal(body.source, 'k136s_spoken_learning');
  assert.equal(body.confirm, true); assert.equal(body.metadata.k136s.contentHash, 'h1'); assert.equal(body.metadata.k136s.approvalId, 'a1');
  assert.deepEqual(body.metadata.k136s.superseded, { previousContentHash: 'h0', previousContent: 'Old.', at: 'then' });
  const alt = toBackendSaveBody({ change, memoryKey: 'k1', confirmationField: 'confirmed' });
  assert.equal(alt.confirmed, true); assert.equal('confirm' in alt, false);
});

test('writer: deriveMemoryKey is stable, prefers an explicit key, and differs across type/category/text', () => {
  const a = deriveMemoryKey({ agentId: AGENT, type: 'MEMORY', category: 'preference', normalizedText: 'Acme prefers morning calls.' });
  assert.equal(a, deriveMemoryKey({ agentId: AGENT, type: 'MEMORY', category: 'preference', normalizedText: 'Acme prefers morning calls.' }));
  assert.match(a, /^k136s:memory:preference:[0-9a-f]{16}$/);
  assert.notEqual(a, deriveMemoryKey({ agentId: AGENT, type: 'TRAINING', category: 'preference', normalizedText: 'Acme prefers morning calls.' }));
  assert.equal(deriveMemoryKey({ agentId: AGENT, memoryKey: '  Billing-Escalation ' }), 'billing-escalation');
});

test('writer: the fake mirrors upsert-by-key and refuses without the confirmation flag; the backend adapter calls the injected helpers with the backend shape', async () => {
  const fake = createFakeMemoryWriter({ now: () => T0 });
  const change = { normalizedText: 'One.', type: 'MEMORY', category: 'c', sensitivity: 'low', expiresAt: null, contentHash: 'h1' };
  const r1 = await fake.write({ userId: 'u', agentId: AGENT, change, memoryKey: 'k' });
  const r2 = await fake.write({ userId: 'u', agentId: AGENT, change: Object.assign({}, change, { normalizedText: 'Two.', contentHash: 'h2' }), memoryKey: 'k' });
  assert.equal(r1.id, r2.id, 'same key updates in place'); assert.equal((await fake.readByKey({ agentId: AGENT, memoryKey: 'k' })).content, 'Two.');
  assert.equal(fake._rows().length, 1);
  const calls = [];
  const backend = createBackendMemoryWriter({
    saveMemory: async (args) => { calls.push(['save', args]); return { id: 'm-9', memory_key: args.body.memory_key, content: args.body.content, metadata: args.body.metadata, enabled: true, active: true }; },
    loadMemoryByKey: async (args) => { calls.push(['load', args]); return null; },
  });
  const out = await backend.write({ userId: 'u', agentId: AGENT, change, memoryKey: 'k', sessionId: 's', approvalId: 'a' });
  assert.equal(out.id, 'm-9'); assert.equal(out.contentHash, 'h1');
  assert.equal(calls[0][0], 'save'); assert.equal(calls[0][1].userId, 'u'); assert.equal(calls[0][1].agentId, AGENT); assert.equal(calls[0][1].body.confirm, true);
  await backend.readByKey({ userId: 'u', agentId: AGENT, memoryKey: 'k' });
  assert.deepEqual(calls[1][1], { userId: 'u', agentId: AGENT, memoryKey: 'k', key: 'k' });
});

// ---------- request ----------
test('request: issues a bound single-use token; refuses agent mismatch, missing identity, and bad input', async () => {
  const f = fixture();
  const ch = changeFor('Acme prefers morning calls.');
  const ok = await f.routes.request({ headers: H(), body: { sessionId: 's1', agentId: AGENT, contentHash: ch.contentHash }, grantPayload: f.grantPayload() });
  assert.equal(ok.status, 200); assert.match(ok.json.approvalToken, /^[A-Za-z0-9_-]{43}$/); assert.equal(ok.json.expiresAt, T0 + 120000); assert.equal(ok.json.elevated, false);
  assert.equal(f.store.approvals.count(), 1); assert.equal(JSON.stringify(f.store.approvals.dump()).includes(ok.json.approvalToken), false, 'raw token never stored');
  assert.equal((await f.routes.request({ headers: H(), body: { sessionId: 's1', agentId: 'other', contentHash: ch.contentHash }, grantPayload: f.grantPayload() })).json.code, 'AGENT_MISMATCH');
  assert.equal((await f.routes.request({ headers: H(), body: { sessionId: 's1', agentId: AGENT }, grantPayload: f.grantPayload() })).status, 400);
  const noId = fixture({ identity: null });
  assert.equal((await noId.routes.request({ headers: H(), body: { sessionId: 's1', agentId: AGENT, contentHash: ch.contentHash }, grantPayload: noId.grantPayload() })).json.code, 'IDENTITY_NOT_CONFIGURED');
  const unauth = fixture({ identity: () => null });
  assert.equal((await unauth.routes.request({ headers: H(), body: { sessionId: 's1', agentId: AGENT, contentHash: ch.contentHash }, grantPayload: unauth.grantPayload() })).status, 401);
  assert.equal(f.store.audit.list().filter((e) => e.eventType === 'APPROVAL_ISSUED').length, 1);
});

// ---------- confirm: happy path ----------
async function issueFor(f, ch, extra = {}) {
  const r = await f.routes.request({ headers: H(), body: Object.assign({ sessionId: 's1', agentId: AGENT, contentHash: ch.contentHash }, extra), grantPayload: f.grantPayload() });
  assert.equal(r.status, 200); return r.json.approvalToken;
}
function confirmBody(ch, token, extra = {}) { return Object.assign({ sessionId: 's1', agentId: AGENT, contentHash: ch.contentHash, approvalToken: token, channel: 'voice', preview: ch.preview }, extra); }

test('confirm: consumed approval → write → read-back → VERIFIED, with a full audit trail and the row present in the writer', async () => {
  const f = fixture();
  const ch = changeFor('nova, remember that Acme prefers morning calls');
  const tok = await issueFor(f, ch);
  const r = await f.routes.confirm({ headers: H(), body: confirmBody(ch, tok), grantPayload: f.grantPayload() });
  assert.equal(r.status, 200, JSON.stringify(r.json)); assert.equal(r.json.state, 'VERIFIED'); assert.equal(r.json.contentHash, ch.contentHash); assert.equal(r.json.superseded, null);
  const row = await f.writer.readByKey({ agentId: AGENT, memoryKey: r.json.memoryKey });
  assert.equal(row.content, 'Remember that Acme prefers morning calls.'); assert.equal(row.contentHash, ch.contentHash);
  const types = f.store.audit.list().map((e) => e.eventType);
  assert.deepEqual(types, ['APPROVAL_ISSUED', 'WRITE', 'VERIFIED']);
});

test('confirm: a second confirmation with the same token is a replay (ALREADY_CONSUMED) and writes nothing', async () => {
  const f = fixture();
  const ch = changeFor('Always confirm the callback number.', { type: 'TRAINING', category: 'workflow' });
  const tok = await issueFor(f, ch);
  assert.equal((await f.routes.confirm({ headers: H(), body: confirmBody(ch, tok), grantPayload: f.grantPayload() })).status, 200);
  const again = await f.routes.confirm({ headers: H(), body: confirmBody(ch, tok), grantPayload: f.grantPayload() });
  assert.equal(again.status, 409); assert.equal(again.json.code, 'ALREADY_CONSUMED');
  assert.equal(f.store.audit.list().filter((e) => e.eventType === 'WRITE').length, 1);
});

test('confirm: supersede — a change to an existing key updates in place and records the previous content/hash', async () => {
  const f = fixture();
  const a = changeFor('Acme prefers morning calls.', { memoryKey: 'acme-call-time' });
  const b = changeFor('Acme prefers afternoon calls.', { memoryKey: 'acme-call-time' });
  const ra = await f.routes.confirm({ headers: H(), body: confirmBody(a, await issueFor(f, a)), grantPayload: f.grantPayload() });
  const rb = await f.routes.confirm({ headers: H(), body: confirmBody(b, await issueFor(f, b)), grantPayload: f.grantPayload() });
  assert.equal(ra.status, 200); assert.equal(rb.status, 200);
  assert.equal(ra.json.memoryId, rb.json.memoryId, 'same row updated in place');
  assert.deepEqual(rb.json.superseded, { previousContentHash: a.contentHash });
  const rows = f.writer._rows(); assert.equal(rows.length, 1);
  assert.equal(rows[0].metadata.k136s.superseded.previousContent, 'Acme prefers morning calls.');
});

// ---------- confirm: refusals ----------
test('confirm: refuses a forged/mismatched hash, an expired token, a wrong binding, and bad input — nothing written', async () => {
  const f = fixture();
  const ch = changeFor('Acme prefers morning calls.');
  const tok = await issueFor(f, ch);
  const forged = await f.routes.confirm({ headers: H(), body: confirmBody(ch, tok, { preview: Object.assign({}, ch.preview, { normalizedText: 'Acme prefers evening calls.' }) }), grantPayload: f.grantPayload() });
  assert.equal(forged.status, 409); assert.equal(forged.json.code, 'HASH_MISMATCH');
  const wrongSession = await f.routes.confirm({ headers: H(), body: confirmBody(ch, tok, { sessionId: 's2' }), grantPayload: f.grantPayload() });
  assert.equal(wrongSession.status, 403); assert.equal(wrongSession.json.code, 'BINDING_MISMATCH');
  f.tick(120001);
  const expired = await f.routes.confirm({ headers: H(), body: confirmBody(ch, tok), grantPayload: f.grantPayload() });
  assert.equal(expired.status, 410); assert.equal(expired.json.code, 'EXPIRED');
  assert.equal((await f.routes.confirm({ headers: H(), body: { sessionId: 's1' }, grantPayload: f.grantPayload() })).status, 400);
  assert.equal((await f.routes.confirm({ headers: H(), body: confirmBody(ch, tok, { channel: 'carrier-pigeon' }), grantPayload: f.grantPayload() })).json.code, 'INVALID_CHANNEL');
  assert.equal(f.writer._rows().length, 0); assert.equal(f.store.audit.list().filter((e) => e.eventType === 'WRITE').length, 0);
});

test('confirm: prohibited/secret-like content is denied by policy even if an approval was issued', async () => {
  const f = fixture();
  const ch = changeFor('Remember the client password is hunter2.', { type: 'PROHIBITED', category: 'credential' });
  const tok = await issueFor(f, ch);
  const r = await f.routes.confirm({ headers: H(), body: confirmBody(ch, tok), grantPayload: f.grantPayload() });
  assert.equal(r.status, 422); assert.equal(r.json.code, 'POLICY_DENIED'); assert.equal(f.writer._rows().length, 0);
});

test('confirm: elevated changes require a typed channel, a grant minted within 60s, and an approval issued as elevated', async () => {
  const f = fixture();
  const ch = changeFor('Update the agent persona to be more formal.', { type: 'PROFILE', category: 'persona', sensitivity: 'medium' });
  // voice → refused
  const t1 = await issueFor(f, ch, { elevated: true });
  const voice = await f.routes.confirm({ headers: H(), body: confirmBody(ch, t1, { channel: 'voice' }), grantPayload: f.grantPayload() });
  assert.equal(voice.status, 403); assert.equal(voice.json.code, 'ELEVATED_REQUIRES_TYPED');
  // typed but stale grant (minted 61s ago) → refused
  const stale = await f.routes.confirm({ headers: H(), body: confirmBody(ch, t1, { channel: 'typed' }), grantPayload: f.grantPayload(AGENT, f.clock() - 61000) });
  assert.equal(stale.status, 403); assert.equal(stale.json.code, 'ELEVATED_REQUIRES_FRESH_VAULT');
  // typed + fresh, but approval NOT issued as elevated → refused (token consumed, nothing written)
  const t2 = await issueFor(f, ch);
  const undeclared = await f.routes.confirm({ headers: H(), body: confirmBody(ch, t2, { channel: 'typed' }), grantPayload: f.grantPayload() });
  assert.equal(undeclared.status, 403); assert.equal(undeclared.json.code, 'ELEVATED_NOT_DECLARED');
  assert.equal(f.writer._rows().length, 0);
  // typed + fresh + declared elevated → VERIFIED
  const ok = await f.routes.confirm({ headers: H(), body: confirmBody(ch, t1, { channel: 'typed' }), grantPayload: f.grantPayload() });
  assert.equal(ok.status, 200); assert.equal(ok.json.state, 'VERIFIED');
});

test('confirm: a write failure or a read-back mismatch is REJECTED with an ALERT; the approval stays consumed', async () => {
  const failing = createFakeMemoryWriter({ now: () => T0, failOn: () => true });
  const f = fixture({ writer: failing });
  const ch = changeFor('Acme prefers morning calls.');
  const r = await f.routes.confirm({ headers: H(), body: confirmBody(ch, await issueFor(f, ch)), grantPayload: f.grantPayload() });
  assert.equal(r.status, 502); assert.equal(r.json.code, 'WRITE_FAILED'); assert.equal(r.json.approvalConsumed, true);
  assert.deepEqual(f.store.audit.list().map((e) => e.eventType), ['APPROVAL_ISSUED', 'WRITE_FAILED', 'ALERT']);
  // a writer that "succeeds" but reads back different content → VERIFICATION_FAILED + ALERT
  const lying = { write: async () => ({ id: 'x' }), readByKey: async () => ({ id: 'x', content: 'Something else.', contentHash: 'nope', enabled: true, active: true }) };
  const g = fixture({ writer: lying });
  const r2 = await g.routes.confirm({ headers: H(), body: confirmBody(ch, await issueFor(g, ch)), grantPayload: g.grantPayload() });
  assert.equal(r2.status, 409); assert.equal(r2.json.code, 'VERIFICATION_FAILED'); assert.equal(r2.json.state, 'REJECTED');
  assert.ok(g.store.audit.list().some((e) => e.eventType === 'ALERT' && e.reason === 'VERIFICATION_FAILED'));
});

test('confirm: without a writer the approval is consumed but the write is refused (503) — never a silent no-op', async () => {
  const f = fixture({ writer: null });
  const ch = changeFor('Acme prefers morning calls.');
  const r = await f.routes.confirm({ headers: H(), body: confirmBody(ch, await issueFor(f, ch)), grantPayload: f.grantPayload() });
  assert.equal(r.status, 503); assert.equal(r.json.code, 'WRITER_NOT_CONFIGURED'); assert.equal(r.json.approvalConsumed, true);
});

// ---------- handler wiring ----------
test('handler: approve routes require a valid grant, are absent (503) when not configured, and health reports stage E1', async () => {
  const f = fixture();
  const ch = changeFor('Acme prefers morning calls.');
  const h = f.handler;
  assert.equal((h({ method: 'GET', path: '/k136s/health' })).json.stage, 'E1'); assert.equal((h({ method: 'GET', path: '/k136s/health' })).json.build, 'D1'); assert.equal((h({ method: 'GET', path: '/k136s/health' })).json.approvals, true);
  const noGrant = await h.async({ method: 'POST', path: '/k136s/approve/request', headers: {}, rawBody: JSON.stringify({ sessionId: 's1', agentId: AGENT, contentHash: ch.contentHash }) });
  assert.equal(noGrant.status, 401);
  const req = await h.async({ method: 'POST', path: '/k136s/approve/request', headers: { 'x-k136s-grant': f.grant() }, rawBody: JSON.stringify({ sessionId: 's1', agentId: AGENT, contentHash: ch.contentHash }) });
  assert.equal(req.status, 200);
  const conf = await h.async({ method: 'POST', path: '/k136s/approve/confirm', headers: { 'x-k136s-grant': f.grant() }, rawBody: JSON.stringify(confirmBody(ch, req.json.approvalToken)) });
  assert.equal(conf.status, 200); assert.equal(conf.json.state, 'VERIFIED');
  const off = createPreviewHandler({ key: KEY, now: f.clock });
  assert.equal((await off.async({ method: 'POST', path: '/k136s/approve/request', headers: { 'x-k136s-grant': f.grant() }, rawBody: '{}' })).json.code, 'APPROVALS_NOT_CONFIGURED');
  assert.equal((off({ method: 'GET', path: '/k136s/health' })).json.approvals, false);
});

// ---------- real socket ----------
function request(port, method, path, { headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : Buffer.from(body, 'utf8');
    const req = http.request({ host: '127.0.0.1', port, method, path, headers: Object.assign({ 'content-type': 'application/json' }, headers, data ? { 'content-length': data.length } : {}) }, (res) => {
      const c = []; res.on('data', (x) => c.push(x)); res.on('end', () => { let j = null; try { j = JSON.parse(Buffer.concat(c).toString('utf8')); } catch { /* null */ } resolve({ status: res.statusCode, json: j }); });
    });
    req.on('error', reject); if (data) req.write(data); req.end();
  });
}
test('socket: dev-grant → preview → approve/request → approve/confirm → VERIFIED, end to end through the server', async () => {
  const store = createMemoryStore(); const approvals = createApprovalService({ store, now: Date.now });
  const writer = createFakeMemoryWriter({ now: Date.now });
  const identity = (h) => (h['x-k136s-dev-user'] && h['x-k136s-dev-account']) ? { userId: h['x-k136s-dev-user'], accountId: h['x-k136s-dev-account'] } : null;
  const routes = createApprovalRoutes({ store, approvals, writer, identity, now: Date.now });
  const server = createServer({ key: KEY, allowDevGrant: true, now: Date.now, approvalRoutes: routes });
  const port = await new Promise((r) => server.listen(0, '127.0.0.1', () => r(server.address().port)));
  const devH = { 'x-k136s-dev-user': 'mgr-1', 'x-k136s-dev-account': 'acct-1' };
  try {
    const g = await request(port, 'POST', '/k136s/grant/dev', { body: JSON.stringify({ agentId: 'agent-x' }) }); assert.equal(g.status, 200);
    const gh = { 'x-k136s-grant': g.json.grant };
    const p = await request(port, 'POST', '/k136s/preview', { headers: gh, body: JSON.stringify({ agentId: 'agent-x', proposedText: 'nova, always confirm the callback number' }) });
    assert.equal(p.status, 200); assert.equal(p.json.policy.allowed, true);
    const preview = { normalizedText: p.json.normalizedText, type: p.json.classification.type, category: p.json.classification.category, sensitivity: p.json.classification.sensitivity, expiresAt: p.json.classification.expiresAt };
    const rq = await request(port, 'POST', '/k136s/approve/request', { headers: Object.assign({}, gh, devH), body: JSON.stringify({ sessionId: 's-1', agentId: 'agent-x', contentHash: p.json.contentHash }) });
    assert.equal(rq.status, 200, JSON.stringify(rq.json));
    const noId = await request(port, 'POST', '/k136s/approve/confirm', { headers: gh, body: JSON.stringify({ sessionId: 's-1', agentId: 'agent-x', contentHash: p.json.contentHash, approvalToken: rq.json.approvalToken, channel: 'voice', preview }) });
    assert.equal(noId.status, 401, 'identity headers required');
    const cf = await request(port, 'POST', '/k136s/approve/confirm', { headers: Object.assign({}, gh, devH), body: JSON.stringify({ sessionId: 's-1', agentId: 'agent-x', contentHash: p.json.contentHash, approvalToken: rq.json.approvalToken, channel: 'voice', preview }) });
    assert.equal(cf.status, 200, JSON.stringify(cf.json)); assert.equal(cf.json.state, 'VERIFIED');
    assert.equal(writer._rows().length, 1); assert.equal(writer._rows()[0].content, 'Always confirm the callback number.');
    const replay = await request(port, 'POST', '/k136s/approve/confirm', { headers: Object.assign({}, gh, devH), body: JSON.stringify({ sessionId: 's-1', agentId: 'agent-x', contentHash: p.json.contentHash, approvalToken: rq.json.approvalToken, channel: 'voice', preview }) });
    assert.equal(replay.status, 409); assert.equal(replay.json.code, 'ALREADY_CONSUMED');
  } finally { await new Promise((r) => server.close(r)); }
});
