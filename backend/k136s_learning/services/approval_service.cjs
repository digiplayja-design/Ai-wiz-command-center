'use strict';
// K136S - approval tokens: 32 random bytes, stored only as SHA-256, TTL 120 s, single-use, bound to
// (userId, accountId, agentId, sessionId, contentHash). Consumption is atomic in the store.
const crypto = require('node:crypto');

const DEFAULT_TTL_MS = 120 * 1000;
function hashToken(token) { return crypto.createHash('sha256').update(String(token), 'utf8').digest('hex'); }
function isStr(v) { return typeof v === 'string' && v.length > 0; }

function createApprovalService(deps) {
  const store = deps && deps.store;
  if (!store || !store.approvals) throw new TypeError('approval service requires a store with approvals');
  const now = (deps.now) || (() => Date.now());
  const random = deps.randomBytes || ((n) => crypto.randomBytes(n));
  const ttlMs = Number.isFinite(deps.ttlMs) ? deps.ttlMs : DEFAULT_TTL_MS;

  function issue(input) {
    for (const k of ['sessionId', 'userId', 'accountId', 'agentId', 'contentHash']) if (!isStr(input[k])) return { ok: false, code: 'INVALID_INPUT', field: k };
    const at = now();
    const token = random(32).toString('base64url');
    const record = {
      id: crypto.randomUUID(), sessionId: input.sessionId, userId: input.userId, accountId: input.accountId, agentId: input.agentId,
      tokenHash: hashToken(token), contentHash: input.contentHash, elevated: input.elevated === true,
      createdAt: at, expiresAt: at + ttlMs, consumedAt: null,
    };
    store.approvals.insert(record);
    return { ok: true, approvalId: record.id, token, expiresAt: record.expiresAt, elevated: record.elevated };
  }

  function consume(input) {
    for (const k of ['token', 'sessionId', 'userId', 'accountId', 'agentId', 'contentHash']) if (!isStr(input[k])) return { ok: false, code: 'INVALID_INPUT' };
    const at = now();
    const result = store.approvals.consumeIfValid(hashToken(input.token), {
      sessionId: input.sessionId, userId: input.userId, accountId: input.accountId, agentId: input.agentId, contentHash: input.contentHash,
    }, at);
    if (!result.ok) return { ok: false, code: result.code };
    const r = result.record;
    return { ok: true, approvalId: r.id, contentHash: r.contentHash, userId: r.userId, accountId: r.accountId, agentId: r.agentId, sessionId: r.sessionId, elevated: r.elevated, consumedAt: r.consumedAt };
  }

  return Object.freeze({ issue, consume, ttlMs });
}

module.exports = { createApprovalService, hashToken, DEFAULT_TTL_MS };
