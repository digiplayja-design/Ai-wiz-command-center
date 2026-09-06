'use strict';
// K136S-F1 Supabase-backed store.
//
// B's approval service uses the store SYNCHRONOUSLY (insert / consumeIfValid), so this adapter keeps
// the in-memory store as the authoritative, atomic source of truth for the running process and
// MIRRORS to the K136S tables asynchronously:
//   • k136s_approvals     — inserted on issue, consumed_at set on consume (visibility, not atomicity)
//   • k136s_audit_events  — every audit event (durable trail; this is the main reason to opt in)
//   • sessions            — memory only (E does not persist sessions; F2/F3 may)
// Mirror failures are counted and logged; they never break the request path. A process restart
// loses unconsumed approvals (they live 120 s anyway). Making approvals DB-atomic needs an async
// approval service — a follow-up with its own approval, because it edits a B module.
//
// Opt-in only: the mount selects this store when K136S_STORE=supabase AND a client is present, which
// is meaningful only after supabase/migrations/202609060001_k136s_learning_build136.sql is applied.
const { createMemoryStore } = require('./memory_store.cjs');

const TABLES = Object.freeze({ approvals: 'k136s_approvals', audit: 'k136s_audit_events', sessions: 'k136s_learning_sessions' });
const AUDIT_COLUMNS = Object.freeze(['sessionId', 'userId', 'accountId', 'agentId', 'approvalId', 'memoryKey', 'contentHash']);
const iso = (ms) => (Number.isFinite(ms) ? new Date(ms).toISOString() : null);

function createSupabaseStore({ client, now = Date.now, log = null, memory = null } = {}) {
  if (!client || typeof client.from !== 'function') throw new TypeError('supabase store requires a client with from()');
  const mem = memory || createMemoryStore();
  const stats = { mirrored: 0, failed: 0 };
  let inflight = [];
  const warn = (m) => { try { (log || console).warn(`[k136s] store mirror: ${m}`); } catch { /* ignore */ } };

  // fire-and-forget with bookkeeping; never throws into the caller
  function mirror(label, fn) {
    let p;
    try { p = Promise.resolve().then(fn); } catch (e) { p = Promise.reject(e); }
    const tracked = p.then((r) => {
      if (r && r.error) { stats.failed += 1; warn(`${label}: ${r.error.message || String(r.error)}`); }
      else stats.mirrored += 1;
    }).catch((e) => { stats.failed += 1; warn(`${label}: ${e && e.message || e}`); });
    inflight.push(tracked);
    if (inflight.length > 200) inflight = inflight.slice(-100);
    return tracked;
  }

  const approvals = {
    insert(record) {
      const r = mem.approvals.insert(record);
      mirror('approvals.insert', () => client.from(TABLES.approvals).insert({
        id: record.id, session_id: record.sessionId, user_id: record.userId, account_id: record.accountId, agent_id: record.agentId,
        token_hash: record.tokenHash, content_hash: record.contentHash, elevated: record.elevated === true,
        created_at: iso(record.createdAt), expires_at: iso(record.expiresAt), consumed_at: null,
      }));
      return r;
    },
    findById(id) { return mem.approvals.findById(id); },
    consumeIfValid(tokenHash, binding, nowMs) {
      const result = mem.approvals.consumeIfValid(tokenHash, binding, nowMs);
      if (result && result.ok && result.record) {
        const rec = result.record;
        mirror('approvals.consume', () => client.from(TABLES.approvals).update({ consumed_at: iso(rec.consumedAt || nowMs) }).eq('id', rec.id));
      }
      return result;
    },
    count() { return mem.approvals.count(); },
    dump() { return mem.approvals.dump(); },
  };

  const audit = {
    append(event) {
      const id = mem.audit.append(event);
      const detail = {};
      for (const k of Object.keys(event)) if (k !== 'eventType' && k !== 'at' && !AUDIT_COLUMNS.includes(k)) detail[k] = event[k];
      mirror('audit.append', () => client.from(TABLES.audit).insert({
        event_type: event.eventType, at: iso(Number.isFinite(event.at) ? event.at : now()),
        session_id: event.sessionId || null, user_id: event.userId || null, account_id: event.accountId || null, agent_id: event.agentId || null,
        approval_id: event.approvalId || null, memory_key: event.memoryKey || null, content_hash: event.contentHash || null,
        detail,
      }));
      return id;
    },
    list() { return mem.audit.list(); },
  };

  return Object.freeze({
    kind: 'supabase',
    approvals, audit,
    sessions: mem.sessions,
    reset() { return mem.reset(); },
    stats() { return Object.assign({}, stats); },
    pending() { return Promise.allSettled(inflight.slice()); },
  });
}

module.exports = Object.freeze({ createSupabaseStore, TABLES });
