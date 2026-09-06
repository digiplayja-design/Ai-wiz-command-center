'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createSupabaseStore, TABLES } = require('../k136s_learning/adapters/supabase_store.cjs');
const { createApprovalService, hashToken } = require('../k136s_learning/services/approval_service.cjs');

function fakeClient({ failInsert = false } = {}) {
  const writes = [];
  return { writes, from(table) {
    return {
      insert: async (row) => { writes.push({ op: 'insert', table, row }); return failInsert ? { data: null, error: { message: 'boom' } } : { data: row, error: null }; },
      update: (vals) => ({ eq: async (col, v) => { writes.push({ op: 'update', table, vals, col, v }); return { data: null, error: null }; } }),
    };
  } };
}
const T0 = Date.UTC(2026, 8, 6, 12, 0, 0);
const quiet = { warn() {}, log() {} };

test('store: requires a client; exposes kind, sessions, reset, stats, pending', () => {
  assert.throws(() => createSupabaseStore({}), /client/);
  const s = createSupabaseStore({ client: fakeClient(), log: quiet });
  assert.equal(s.kind, 'supabase'); assert.ok(s.sessions && s.audit && s.approvals); assert.deepEqual(s.stats(), { mirrored: 0, failed: 0 });
});

test('store: approvals keep in-memory single-use semantics and mirror issue + consume to k136s_approvals with hashed token only', async () => {
  const client = fakeClient(); const s = createSupabaseStore({ client, now: () => T0, log: quiet });
  const svc = createApprovalService({ store: s, now: () => T0 });
  const b = { sessionId: 's1', userId: 'u1', accountId: 'a1', agentId: 'g1', contentHash: 'h1' };
  const issued = svc.issue(Object.assign({ elevated: true }, b));
  assert.equal(issued.ok, true);
  const c1 = svc.consume(Object.assign({ token: issued.token }, b)); assert.equal(c1.ok, true);
  const c2 = svc.consume(Object.assign({ token: issued.token }, b)); assert.equal(c2.code, 'ALREADY_CONSUMED');
  await s.pending();
  const ins = client.writes.find((w) => w.op === 'insert' && w.table === TABLES.approvals);
  assert.equal(ins.row.id, issued.approvalId); assert.equal(ins.row.token_hash, hashToken(issued.token)); assert.equal(ins.row.elevated, true);
  assert.equal(ins.row.session_id, 's1'); assert.equal(ins.row.account_id, 'a1'); assert.equal(ins.row.expires_at, new Date(T0 + 120000).toISOString()); assert.equal(ins.row.consumed_at, null);
  const upd = client.writes.find((w) => w.op === 'update' && w.table === TABLES.approvals);
  assert.equal(upd.col, 'id'); assert.equal(upd.v, issued.approvalId); assert.equal(upd.vals.consumed_at, new Date(T0).toISOString());
  assert.equal(JSON.stringify(client.writes).includes(issued.token), false, 'raw token never leaves the process');
  assert.equal(s.stats().mirrored, 2); assert.equal(s.stats().failed, 0);
});

test('store: audit events are kept in memory and mirrored to k136s_audit_events with known columns split from detail', async () => {
  const client = fakeClient(); const s = createSupabaseStore({ client, now: () => T0, log: quiet });
  const id = s.audit.append({ eventType: 'WRITE', at: T0, sessionId: 's1', userId: 'u1', accountId: 'a1', agentId: 'g1', approvalId: 'ap1', memoryKey: 'k', contentHash: 'h', memoryId: 'm1', superseded: true });
  assert.equal(id, 1); assert.equal(s.audit.list().length, 1);
  await s.pending();
  const row = client.writes.find((w) => w.table === TABLES.audit).row;
  assert.equal(row.event_type, 'WRITE'); assert.equal(row.at, new Date(T0).toISOString()); assert.equal(row.session_id, 's1'); assert.equal(row.approval_id, 'ap1'); assert.equal(row.memory_key, 'k'); assert.equal(row.content_hash, 'h');
  assert.deepEqual(row.detail, { memoryId: 'm1', superseded: true });
});

test('store: a failing mirror never breaks the caller and is counted', async () => {
  const s = createSupabaseStore({ client: fakeClient({ failInsert: true }), now: () => T0, log: quiet });
  assert.equal(typeof s.audit.append({ eventType: 'ALERT', at: T0 }), 'number');
  s.approvals.insert({ id: 'x', sessionId: 's', userId: 'u', accountId: 'a', agentId: 'g', tokenHash: 'th', contentHash: 'h', elevated: false, createdAt: T0, expiresAt: T0 + 1000, consumedAt: null });
  assert.equal(s.approvals.count(), 1);
  await s.pending();
  assert.equal(s.stats().failed, 2); assert.equal(s.stats().mirrored, 0);
  const throwing = { from() { throw new Error('client exploded'); } };
  const s2 = createSupabaseStore({ client: throwing, log: quiet });
  assert.doesNotThrow(() => s2.audit.append({ eventType: 'X' }));
  await s2.pending(); assert.equal(s2.stats().failed, 1);
});
