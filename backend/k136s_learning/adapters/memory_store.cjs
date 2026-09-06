'use strict';
// K136S - in-memory store. Mirrors the semantics the Supabase adapter must provide later:
//   approvals.consumeIfValid == `UPDATE ... SET consumed_at = now() WHERE token_hash = $1 AND consumed_at IS NULL
//                               AND expires_at > now() AND session_id = $2 AND user_id = $3 AND account_id = $4
//                               AND agent_id = $5 AND content_hash = $6 RETURNING *`
// Nothing here is wired to a network or a database.
function createMemoryStore() {
  const approvals = new Map(); // tokenHash -> record
  const sessions = new Map();  // id -> session
  const audit = [];            // insert-only

  const api = {
    approvals: {
      insert(record) {
        if (!record || !record.tokenHash) throw new TypeError('approval record requires tokenHash');
        if (approvals.has(record.tokenHash)) throw new Error('duplicate token hash');
        approvals.set(record.tokenHash, Object.assign({}, record));
        return record.id;
      },
      findById(id) { for (const r of approvals.values()) if (r.id === id) return Object.assign({}, r); return null; },
      consumeIfValid(tokenHash, binding, nowMs) {
        const r = approvals.get(tokenHash);
        if (!r) return { ok: false, code: 'NOT_FOUND' };
        if (r.consumedAt !== null) return { ok: false, code: 'ALREADY_CONSUMED' };
        if (!(r.expiresAt > nowMs)) return { ok: false, code: 'EXPIRED' };
        for (const k of ['sessionId', 'userId', 'accountId', 'agentId', 'contentHash']) if (r[k] !== binding[k]) return { ok: false, code: 'BINDING_MISMATCH' };
        r.consumedAt = nowMs;
        return { ok: true, record: Object.assign({}, r) };
      },
      count() { return approvals.size; },
      dump() { return Array.from(approvals.values()).map((r) => Object.assign({}, r)); },
    },
    sessions: {
      put(session) { sessions.set(session.id, session); return session.id; },
      get(id) { return sessions.get(id) || null; },
      activeFor(userId, agentId, terminalStates) {
        for (const s of sessions.values()) if (s.userId === userId && s.agentId === agentId && !terminalStates.has(s.state)) return s;
        return null;
      },
    },
    audit: {
      append(event) {
        if (!event || typeof event.eventType !== 'string') throw new TypeError('audit event requires eventType');
        const row = Object.assign({ id: audit.length + 1, at: Date.now() }, event);
        audit.push(Object.freeze(row));
        return row.id;
      },
      list() { return audit.slice(); },
    },
    reset() { approvals.clear(); sessions.clear(); audit.length = 0; },
  };
  return Object.freeze(api);
}

module.exports = { createMemoryStore };
