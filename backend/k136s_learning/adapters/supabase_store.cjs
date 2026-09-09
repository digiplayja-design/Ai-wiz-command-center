'use strict';
// K136S-F4: Supabase is the ONLY approval authority in this adapter.
// No approval cache/fallback. Use approvalService (async), not B's synchronous service.
// Consumption is one filtered UPDATE ... RETURNING. Audit mirroring remains best-effort.
const crypto = require('node:crypto');
const { createMemoryStore } = require('./memory_store.cjs');
const { hashToken, DEFAULT_TTL_MS } = require('../services/approval_service.cjs');
const TABLES = Object.freeze({ approvals: 'k136s_approvals', audit: 'k136s_audit_events', sessions: 'k136s_learning_sessions' });
const BIND = Object.freeze({ sessionId: 'session_id', userId: 'user_id', accountId: 'account_id', agentId: 'agent_id', contentHash: 'content_hash' });
const COLS = 'id,session_id,user_id,account_id,agent_id,token_hash,content_hash,elevated,created_at,expires_at,consumed_at';
const AUDIT_COLUMNS = ['sessionId', 'userId', 'accountId', 'agentId', 'approvalId', 'memoryKey', 'contentHash'];
const DETAIL_KEYS = ['reason', 'memoryId', 'superseded', 'elevated', 'expectedHash', 'readBackHash', 'claimed', 'computed', 'violations'];
const str = (v) => typeof v === 'string' && v.trim().length > 0;
const iso = (v) => new Date(v).toISOString();
const unavailable = () => ({ ok: false, code: 'APPROVAL_STORE_UNAVAILABLE' });
function decode(r) {
  if (!r || !str(r.id) || !/^[0-9a-f]{64}$/.test(r.token_hash) || typeof r.elevated !== 'boolean') return null;
  const out = { id: r.id, tokenHash: r.token_hash, elevated: r.elevated,
    createdAt: Date.parse(r.created_at), expiresAt: Date.parse(r.expires_at),
    consumedAt: r.consumed_at === null ? null : Date.parse(r.consumed_at) };
  for (const [k, col] of Object.entries(BIND)) { if (!str(r[col])) return null; out[k] = r[col]; }
  if (!Number.isFinite(out.createdAt) || !Number.isFinite(out.expiresAt) || out.expiresAt <= out.createdAt ||
      (out.consumedAt !== null && !Number.isFinite(out.consumedAt))) return null;
  return out;
}
function createSupabaseStore({ client, now = Date.now, log = null, memory = null, timeoutMs = 5000 } = {}) {
  if (!client || typeof client.from !== 'function') throw new TypeError('supabase store requires a client with from()');
  if (!Number.isFinite(timeoutMs) || timeoutMs < 1 || timeoutMs > 10000) throw new TypeError('invalid store timeout');
  const mem = memory || createMemoryStore(); // sessions/audit only; NEVER mem.approvals
  const stats = { mirrored: 0, failed: 0 };
  const inflight = new Set();
  async function query(build) {
    const controller = new AbortController();
    let timer;
    try {
      const task = Promise.resolve().then(() => build().abortSignal(controller.signal));
      const timeout = new Promise((_, reject) => { timer = setTimeout(() => { controller.abort(); reject(new Error('store timeout')); }, timeoutMs); });
      const r = await Promise.race([task, timeout]);
      if (!r || r.error) throw new Error('store rejected');
      return r;
    } catch {
      stats.failed++;
      // Never copy a database error, row, request, or token into a log or response.
      try { (log || console).warn('[k136s] durable store operation failed'); } catch {}
      return null;
    } finally { clearTimeout(timer); }
  }
  async function issue(input) {
    for (const k of Object.keys(BIND)) if (!input || !str(input[k])) return { ok: false, code: 'INVALID_INPUT', field: k };
    try {
      const at = now();
      if (!Number.isFinite(at)) return unavailable();
      const token = crypto.randomBytes(32).toString('base64url');
      const row = { id: crypto.randomUUID(), token_hash: hashToken(token), elevated: input.elevated === true,
        created_at: iso(at), expires_at: iso(at + DEFAULT_TTL_MS), consumed_at: null };
      for (const [k, col] of Object.entries(BIND)) row[col] = input[k];
      const r = await query(() => client.from(TABLES.approvals).insert(row).select(COLS));
      if (!r || !Array.isArray(r.data) || r.data.length !== 1) return unavailable();
      const rec = decode(r.data[0]);
      if (!rec || rec.id !== row.id || rec.tokenHash !== row.token_hash || rec.consumedAt !== null ||
          rec.createdAt !== at || rec.expiresAt !== at + DEFAULT_TTL_MS || rec.elevated !== row.elevated ||
          Object.keys(BIND).some((k) => rec[k] !== input[k])) return unavailable();
      if (!(rec.expiresAt > now())) return { ok: false, code: 'EXPIRED' };
      return { ok: true, approvalId: rec.id, token, expiresAt: rec.expiresAt, elevated: rec.elevated };
    } catch { return unavailable(); }
  }
  async function consume(input) {
    for (const k of ['token', ...Object.keys(BIND)]) if (!input || !str(input[k])) return { ok: false, code: 'INVALID_INPUT' };
    try {
      const tokenHash = hashToken(input.token);
      // 'now' is a timestamptz input evaluated by PostgreSQL for this request.
      // All bindings, unused state, and expiry are conditions of the SAME UPDATE.
      const r = await query(() => {
        let q = client.from(TABLES.approvals).update({ consumed_at: 'now' }).eq('token_hash', tokenHash);
        for (const [k, col] of Object.entries(BIND)) q = q.eq(col, input[k]);
        return q.is('consumed_at', null).gt('expires_at', 'now').select(COLS);
      });
      if (!r || !Array.isArray(r.data) || r.data.length > 1) return unavailable();
      if (r.data.length === 1) {
        const rec = decode(r.data[0]);
        if (!rec || rec.tokenHash !== tokenHash || rec.consumedAt === null ||
            Object.keys(BIND).some((k) => rec[k] !== input[k])) return unavailable();
        if (!(rec.consumedAt < rec.expiresAt) || !(rec.expiresAt > now())) return { ok: false, code: 'EXPIRED' };
        return { ok: true, approvalId: rec.id, contentHash: rec.contentHash, userId: rec.userId, accountId: rec.accountId,
          agentId: rec.agentId, sessionId: rec.sessionId, elevated: rec.elevated, consumedAt: rec.consumedAt };
      }
      // Diagnostic read ONLY after losing the update. It can NEVER authorize a write.
      const d = await query(() => client.from(TABLES.approvals).select(COLS).eq('token_hash', tokenHash).limit(2));
      if (!d || !Array.isArray(d.data) || d.data.length > 1) return unavailable();
      if (!d.data.length) return { ok: false, code: 'NOT_FOUND' };
      const rec = decode(d.data[0]);
      if (!rec || rec.tokenHash !== tokenHash) return unavailable();
      if (Object.keys(BIND).some((k) => rec[k] !== input[k])) return { ok: false, code: 'BINDING_MISMATCH' };
      if (rec.consumedAt !== null) return { ok: false, code: 'ALREADY_CONSUMED' };
      if (!(rec.expiresAt > now())) return { ok: false, code: 'EXPIRED' };
      return unavailable(); // no returned update row means no authority, even if a read looks valid
    } catch { return unavailable(); }
  }
  const audit = {
    append(event) {
      const clean = { eventType: event.eventType, at: Number.isFinite(event.at) ? event.at : now() };
      for (const k of [...AUDIT_COLUMNS, ...DETAIL_KEYS]) if (event[k] !== undefined) clean[k] = event[k];
      const id = mem.audit.append(clean);
      const detail = {};
      for (const k of DETAIL_KEYS) if (clean[k] !== undefined) detail[k] = clean[k];
      const row = { event_type: clean.eventType, at: iso(clean.at), session_id: clean.sessionId || null,
        user_id: clean.userId || null, account_id: clean.accountId || null, agent_id: clean.agentId || null,
        approval_id: clean.approvalId || null, memory_key: clean.memoryKey || null, content_hash: clean.contentHash || null, detail };
      const p = query(() => client.from(TABLES.audit).insert(row)).then((r) => { if (r) stats.mirrored++; });
      inflight.add(p); p.finally(() => inflight.delete(p));
      return id;
    },
    list() { return mem.audit.list(); },
  };
  // Fail synchronously if somebody accidentally wires B's synchronous service to this store.
  const unsupported = () => { throw new Error('K136S_DURABLE_SERVICE_REQUIRED'); };
  return Object.freeze({ kind: 'supabase', authority: 'supabase_atomic',
    approvalService: Object.freeze({ issue, consume, ttlMs: DEFAULT_TTL_MS }),
    approvals: Object.freeze({ insert: unsupported, consumeIfValid: unsupported }),
    audit, sessions: mem.sessions, reset() { mem.reset(); },
    stats() { return { ...stats }; }, pending() { return Promise.allSettled([...inflight]); } });
}
module.exports = Object.freeze({ createSupabaseStore, TABLES });
