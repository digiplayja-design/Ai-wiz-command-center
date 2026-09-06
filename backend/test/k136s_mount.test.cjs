'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { mountK136S, identityFromUser, augmentSaveBody, ROUTES } = require('../k136s_learning/http/mount.cjs');
const { verifyGrant } = require('../k136s_learning/http/grant.cjs');

const KEY = 'backend-grant-key-0123456789';
const OK_VAULT = async () => ({ status: 200, body: { success: true, verified: true, managerMode: 'account_owner', passwordVersion: 2 } });

// ---- a minimal Express-like stub: records routes, lets tests invoke them with fake req/res ----
function stubApp() {
  const routes = new Map();
  const app = { get: (p, h) => routes.set(`GET ${p}`, h), post: (p, h) => routes.set(`POST ${p}`, h) };
  async function call(method, path, { headers = {}, body } = {}) {
    const h = routes.get(`${method} ${path}`); if (!h) return { status: 404, json: { error: 'no route' } };
    const req = { method, originalUrl: path, url: path, path, headers: Object.assign({}, headers), body };
    let status = 200, json = null; const set = {};
    const res = { status(s) { status = s; return res; }, json(j) { json = j; return res; }, set(k, v) { set[k] = v; return res; } };
    await h(req, res); return { status, json, set };
  }
  return { app, routes, call };
}

// ---- fakes for the backend deps ----
function fakes() {
  const saved = []; const rows = [];
  const supabaseAdmin = { from() { throw new Error('should not be used directly by K136S'); }, tag: 'admin-client' };
  const requireUser = async (req) => {
    const a = req.headers.authorization || '';
    if (a === 'Bearer good') return { id: 'user-1', app_metadata: { account_id: 'acct-9' } };
    if (a === 'Bearer owner') return { id: 'user-2' };
    const e = new Error('unauthenticated'); e.status = 401; throw e;
  };
  const korlixAgentSaveMemoryV1 = async ({ client, userId, agentId, body }) => {
    saved.push({ client, userId, agentId, body });
    if (body.confirmed !== true && body.approved !== true) { const e = new Error('Confirm before saving.'); e.code = 'agent_memory_confirmation_required'; throw e; }
    const existing = rows.find((r) => r.agent_id === agentId && r.memory_key === body.memory_key);
    const row = Object.assign(existing || { id: `mem-${rows.length + 1}` }, { agent_id: agentId, user_id: userId, memory_key: body.memory_key, key: body.memory_key, kind: body.kind, content: body.content, summary: body.label, metadata: body.metadata, enabled: true, active: true, updated_at: new Date().toISOString() });
    if (!existing) rows.push(row);
    return row; // the domain object shape is tolerated by E's toReadBackView
  };
  const korlixAgentListMemoriesV1 = async ({ client, userId, agentId }) => ({ items: rows.filter((r) => r.agent_id === agentId) });
  return { supabaseAdmin, requireUser, korlixAgentSaveMemoryV1, korlixAgentListMemoriesV1, saved, rows };
}
const env = (over = {}) => Object.assign({ K136S_GRANT_KEY: KEY, PORT: '8787' }, over);
const quiet = { log() {}, warn() {} };

test('identityFromUser: account-owner rule and tolerant shapes', () => {
  assert.deepEqual(identityFromUser({ id: 'u', app_metadata: { account_id: 'a' } }), { userId: 'u', accountId: 'a' });
  assert.deepEqual(identityFromUser({ id: 'u', user_metadata: { account_id: 'b' } }), { userId: 'u', accountId: 'b' });
  assert.deepEqual(identityFromUser({ id: 'u' }), { userId: 'u', accountId: 'u' });
  assert.deepEqual(identityFromUser({ user: { id: 'u' } }), { userId: 'u', accountId: 'u' });
  assert.equal(identityFromUser(null), null); assert.equal(identityFromUser({}), null);
});

test('augmentSaveBody: adds label/expiresAt/memoryKey and a memory mirror; keeps confirmed', () => {
  const b = augmentSaveBody({ memory_key: 'k', summary: 'S', expires_at: '2026-10-01T00:00:00Z', content: 'C', kind: 'fact', confirmed: true });
  assert.equal(b.label, 'S'); assert.equal(b.expiresAt, '2026-10-01T00:00:00Z'); assert.equal(b.memoryKey, 'k'); assert.equal(b.confirmed, true);
  assert.equal(b.memory.content, 'C'); assert.equal(b.memory.label, 'S'); assert.equal('memory' in b.memory, false);
});

test('mount: registers the five routes and reports mounted + memory store; dev endpoints are hard-off', async () => {
  const { app, routes, call } = stubApp(); const f = fakes();
  const r = mountK136S(app, Object.assign({ env: env(), log: quiet, vaultVerifier: OK_VAULT }, f));
  assert.equal(r.ok, true); assert.equal(r.configured, true); assert.equal(r.store, 'memory');
  assert.deepEqual([...routes.keys()].sort(), ROUTES.map(([m, p]) => `${m.toUpperCase()} ${p}`).sort());
  const h = await call('GET', '/k136s/health');
  assert.equal(h.status, 200); assert.equal(h.json.mounted, true); assert.equal(h.json.stage, 'F1'); assert.equal(h.json.devGrant, false); assert.equal(h.json.vaultGrant, true); assert.equal(h.json.approvals, true);
  assert.equal(h.set['cache-control'], 'no-store');
  assert.equal((await call('POST', '/k136s/grant/dev', { body: { agentId: 'a' } })).status, 404, 'dev grant is not even routed');
});

test('mount: not configured (no grant key / missing deps) -> routes exist but every call is 503, and the host is never thrown at', async () => {
  const { app, call } = stubApp(); const f = fakes();
  const r = mountK136S(app, Object.assign({ env: env({ K136S_GRANT_KEY: '' }), log: quiet }, f, { requireUser: undefined }));
  assert.equal(r.ok, false); assert.equal(r.mounted, true); assert.equal(r.configured, false);
  assert.ok(r.problems.some((p) => /K136S_GRANT_KEY/.test(p)) && r.problems.some((p) => /requireUser/.test(p)));
  for (const [m, p] of ROUTES) { const x = await call(m.toUpperCase(), p, { body: {} }); assert.equal(x.status, 503); assert.equal(x.json.code, 'K136S_NOT_CONFIGURED'); }
  const bad = mountK136S({ get() { throw new Error('boom'); }, post() {} }, Object.assign({ env: env(), log: quiet }, f));
  assert.equal(bad.ok, false); assert.equal(bad.mounted, false);
  assert.equal(mountK136S(null, {}).ok, false);
});

test('mount: full flow through the mounted routes — grant (vault loopback) -> preview -> approve/request -> approve/confirm -> VERIFIED, bound to the real identity', async () => {
  const { app, call } = stubApp(); const f = fakes();
  const m = mountK136S(app, Object.assign({ env: env(), log: quiet, vaultVerifier: OK_VAULT }, f));
  const auth = { authorization: 'Bearer good' };
  const g = await call('POST', '/k136s/grant', { headers: auth, body: { agentId: 'agent-x', vaultPassword: 'the-real-vault-password' } });
  assert.equal(g.status, 200, JSON.stringify(g.json)); assert.equal(verifyGrant(g.json.grant, { key: KEY }).ok, true); assert.equal(g.json.passwordVersion, 2);
  const gh = { 'x-k136s-grant': g.json.grant };
  const p = await call('POST', '/k136s/preview', { headers: gh, body: { agentId: 'agent-x', proposedText: 'nova, remember that Acme prefers morning calls' } });
  assert.equal(p.status, 200); assert.equal(p.json.classification.type, 'MEMORY');
  const preview = { normalizedText: p.json.normalizedText, type: p.json.classification.type, category: p.json.classification.category, sensitivity: p.json.classification.sensitivity, expiresAt: p.json.classification.expiresAt };
  // identity required: no bearer -> 401 via requireUser throwing
  const noAuth = await call('POST', '/k136s/approve/request', { headers: gh, body: { sessionId: 's1', agentId: 'agent-x', contentHash: p.json.contentHash } });
  assert.equal(noAuth.status, 401); assert.equal(noAuth.json.code, 'UNAUTHENTICATED');
  const rq = await call('POST', '/k136s/approve/request', { headers: Object.assign({}, gh, auth), body: { sessionId: 's1', agentId: 'agent-x', contentHash: p.json.contentHash } });
  assert.equal(rq.status, 200, JSON.stringify(rq.json));
  const cf = await call('POST', '/k136s/approve/confirm', { headers: Object.assign({}, gh, auth), body: { sessionId: 's1', agentId: 'agent-x', contentHash: p.json.contentHash, approvalToken: rq.json.approvalToken, channel: 'voice', preview } });
  assert.equal(cf.status, 200, JSON.stringify(cf.json)); assert.equal(cf.json.state, 'VERIFIED');
  // the backend helper was called with the service client, the resolved user, the confirmed flag and the augmented body
  assert.equal(f.saved.length, 1);
  const s = f.saved[0];
  assert.equal(s.client, f.supabaseAdmin); assert.equal(s.userId, 'user-1'); assert.equal(s.agentId, 'agent-x');
  assert.equal(s.body.confirmed, true); assert.equal('confirm' in s.body, false);
  assert.equal(s.body.label, s.body.summary); assert.equal(s.body.memory.content, 'Remember that Acme prefers morning calls.'); assert.equal(s.body.source, 'k136s_spoken_learning');
  assert.equal(s.body.metadata.k136s.contentHash, p.json.contentHash);
  // approval was bound to the account from app_metadata
  const issued = m._internals.store.audit.list().find((e) => e.eventType === 'APPROVAL_ISSUED');
  assert.equal(issued.userId, 'user-1'); assert.equal(issued.accountId, 'acct-9');
  // replay refused
  const again = await call('POST', '/k136s/approve/confirm', { headers: Object.assign({}, gh, auth), body: { sessionId: 's1', agentId: 'agent-x', contentHash: p.json.contentHash, approvalToken: rq.json.approvalToken, channel: 'voice', preview } });
  assert.equal(again.status, 409); assert.equal(again.json.code, 'ALREADY_CONSUMED');
  // a different user cannot consume an approval issued to user-1 (binding)
  const rq2 = await call('POST', '/k136s/approve/request', { headers: Object.assign({}, gh, auth), body: { sessionId: 's2', agentId: 'agent-x', contentHash: p.json.contentHash } });
  const other = await call('POST', '/k136s/approve/confirm', { headers: Object.assign({}, gh, { authorization: 'Bearer owner' }), body: { sessionId: 's2', agentId: 'agent-x', contentHash: p.json.contentHash, approvalToken: rq2.json.approvalToken, channel: 'voice', preview } });
  assert.equal(other.status, 403); assert.equal(other.json.code, 'BINDING_MISMATCH');
});

test('mount: read-back goes through the list helper; a helper that returns nothing yields REJECTED + ALERT, never a silent success', async () => {
  const { app, call } = stubApp(); const f = fakes();
  f.korlixAgentListMemoriesV1 = async () => []; // simulate a write that cannot be read back
  const m = mountK136S(app, Object.assign({ env: env(), log: quiet, vaultVerifier: OK_VAULT }, f));
  const auth = { authorization: 'Bearer good' };
  const g = await call('POST', '/k136s/grant', { headers: auth, body: { agentId: 'a', vaultPassword: 'pw' } });
  const gh = { 'x-k136s-grant': g.json.grant };
  const p = await call('POST', '/k136s/preview', { headers: gh, body: { agentId: 'a', proposedText: 'Always confirm the callback number.' } });
  const preview = { normalizedText: p.json.normalizedText, type: p.json.classification.type, category: p.json.classification.category, sensitivity: p.json.classification.sensitivity, expiresAt: p.json.classification.expiresAt };
  const rq = await call('POST', '/k136s/approve/request', { headers: Object.assign({}, gh, auth), body: { sessionId: 's', agentId: 'a', contentHash: p.json.contentHash } });
  const cf = await call('POST', '/k136s/approve/confirm', { headers: Object.assign({}, gh, auth), body: { sessionId: 's', agentId: 'a', contentHash: p.json.contentHash, approvalToken: rq.json.approvalToken, channel: 'voice', preview } });
  assert.equal(cf.status, 409); assert.equal(cf.json.code, 'VERIFICATION_FAILED');
  assert.ok(m._internals.store.audit.list().some((e) => e.eventType === 'ALERT'));
});

test('mount: K136S_STORE=supabase selects the mirroring store; approvals + audit are mirrored to the K136S tables', async () => {
  const { app, call } = stubApp(); const f = fakes();
  const writes = [];
  f.supabaseAdmin = { tag: 'admin', from(table) { return { insert: async (row) => { writes.push(['insert', table, row]); return { data: row, error: null }; }, update: (vals) => ({ eq: async (col, v) => { writes.push(['update', table, vals, col, v]); return { data: null, error: null }; } }) }; } };
  const m = mountK136S(app, Object.assign({ env: env({ K136S_STORE: 'supabase' }), log: quiet, vaultVerifier: OK_VAULT }, f));
  assert.equal(m.store, 'supabase');
  const auth = { authorization: 'Bearer good' };
  const g = await call('POST', '/k136s/grant', { headers: auth, body: { agentId: 'a', vaultPassword: 'pw' } });
  const gh = { 'x-k136s-grant': g.json.grant };
  const p = await call('POST', '/k136s/preview', { headers: gh, body: { agentId: 'a', proposedText: 'Acme prefers morning calls.' } });
  const preview = { normalizedText: p.json.normalizedText, type: p.json.classification.type, category: p.json.classification.category, sensitivity: p.json.classification.sensitivity, expiresAt: p.json.classification.expiresAt };
  const rq = await call('POST', '/k136s/approve/request', { headers: Object.assign({}, gh, auth), body: { sessionId: 's', agentId: 'a', contentHash: p.json.contentHash } });
  const cf = await call('POST', '/k136s/approve/confirm', { headers: Object.assign({}, gh, auth), body: { sessionId: 's', agentId: 'a', contentHash: p.json.contentHash, approvalToken: rq.json.approvalToken, channel: 'voice', preview } });
  assert.equal(cf.json.state, 'VERIFIED');
  await m._internals.store.pending();
  const tables = writes.map((w) => `${w[0]}:${w[1]}`);
  assert.ok(tables.includes('insert:k136s_approvals')); assert.ok(tables.includes('update:k136s_approvals')); assert.ok(tables.filter((t) => t === 'insert:k136s_audit_events').length >= 3);
  const approvalRow = writes.find((w) => w[0] === 'insert' && w[1] === 'k136s_approvals')[2];
  assert.equal(approvalRow.user_id, 'user-1'); assert.equal(approvalRow.account_id, 'acct-9'); assert.match(approvalRow.token_hash, /^[0-9a-f]{64}$/); assert.equal(approvalRow.consumed_at, null);
  assert.equal(JSON.stringify(writes).includes(rq.json.approvalToken), false, 'raw approval token never mirrored');
  assert.equal(m._internals.store.stats().failed, 0);
});
