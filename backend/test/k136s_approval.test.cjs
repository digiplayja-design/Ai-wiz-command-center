'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { createApprovalService, hashToken } = require('../k136s_learning/services/approval_service.cjs');
const { createMemoryStore } = require('../k136s_learning/adapters/memory_store.cjs');

function fixture() {
  const store = createMemoryStore();
  let clock = 1_800_000_000_000;
  const svc = createApprovalService({ store, now: () => clock, ttlMs: 120000 });
  const binding = { sessionId: 's1', userId: 'mgr-1', accountId: 'acct-1', agentId: 'agent-1', contentHash: 'h1' };
  return { store, svc, binding, tick: (ms) => { clock += ms; }, at: () => clock };
}

test('issue returns a token and stores only its hash', () => {
  const { store, svc, binding } = fixture();
  const r = svc.issue(binding);
  assert.equal(r.ok, true); assert.match(r.token, /^[A-Za-z0-9_-]{43}$/);
  const rec = store.approvals.findById(r.approvalId);
  assert.equal(rec.tokenHash, hashToken(r.token));
  assert.equal(rec.token, undefined, 'raw token is never stored');
  assert.equal(JSON.stringify(store.approvals.dump()).includes(r.token), false);
});

test('a valid token consumes exactly once', () => {
  const { svc, binding } = fixture();
  const { token } = svc.issue(binding);
  const c1 = svc.consume(Object.assign({ token }, binding));
  assert.equal(c1.ok, true); assert.equal(c1.contentHash, 'h1'); assert.equal(c1.agentId, 'agent-1');
  const c2 = svc.consume(Object.assign({ token }, binding));
  assert.equal(c2.ok, false); assert.equal(c2.code, 'ALREADY_CONSUMED');
});

test('expired tokens cannot be consumed', () => {
  const { svc, binding, tick } = fixture();
  const { token } = svc.issue(binding);
  tick(120001);
  assert.equal(svc.consume(Object.assign({ token }, binding)).code, 'EXPIRED');
});

test('binding mismatches (session, user, account, agent, content) are rejected', () => {
  const { svc, binding } = fixture();
  for (const field of ['sessionId', 'userId', 'accountId', 'agentId', 'contentHash']) {
    const { token } = svc.issue(binding);
    const bad = Object.assign({ token }, binding, { [field]: 'WRONG' });
    assert.equal(svc.consume(bad).code, 'BINDING_MISMATCH', field);
  }
});

test('an unknown token is NOT_FOUND and never matches by chance', () => {
  const { svc, binding } = fixture();
  svc.issue(binding);
  assert.equal(svc.consume(Object.assign({ token: crypto.randomBytes(32).toString('base64url') }, binding)).code, 'NOT_FOUND');
});

test('two issued tokens are independent; consuming one leaves the other valid', () => {
  const { svc, binding } = fixture();
  const a = svc.issue(binding); const b = svc.issue(Object.assign({}, binding, { contentHash: 'h2' }));
  assert.equal(svc.consume(Object.assign({ token: a.token }, binding)).ok, true);
  assert.equal(svc.consume(Object.assign({ token: b.token }, binding, { contentHash: 'h2' })).ok, true);
});

test('invalid issue input is reported by field', () => {
  const { svc } = fixture();
  assert.equal(svc.issue({ userId: 'u', accountId: 'a', agentId: 'g', contentHash: 'h' }).field, 'sessionId');
  assert.equal(svc.consume({ token: 't', sessionId: 's', userId: 'u', accountId: 'a', agentId: 'g' }).code, 'INVALID_INPUT');
});
