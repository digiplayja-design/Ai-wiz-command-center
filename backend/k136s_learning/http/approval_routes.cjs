'use strict';
// K136S-E approval routes — the approve → write → verify leg of the secure flow, over HTTP.
//
//   POST /k136s/approve/request  { sessionId, agentId, contentHash, elevated? }
//       → issues a single-use approval token (120 s, SHA-256 stored only) bound to
//         session + user + account + agent + contentHash.
//   POST /k136s/approve/confirm  { sessionId, agentId, contentHash, approvalToken, channel, preview }
//       → consumes the token atomically (replay = ALREADY_CONSUMED), enforces the elevated rule
//         (typed channel + a grant minted within 60 s), writes through the injected writer, reads
//         back by key, verifies content + hash → VERIFIED, else REJECTED + ALERT. Every outcome is
//         appended to the insert-only audit store.
//
// Invariants (from K136S-B): a write happens only after a consumed approval; approvals are bound and
// single-use; elevated changes never go through on voice; a mismatched read-back is a rejection.
// Identity and the writer are injected: the preview server stubs them (env-gated dev only); F binds
// the backend's auth and korlixAgentSaveMemoryV1.
const { check: checkPolicy } = require('../domain/policy_check.cjs');
const { normalize, contentHash: computeHash } = require('../domain/normalize_diff.cjs');
const { deriveMemoryKey } = require('../adapters/memory_writer.cjs');

const ELEVATED_FRESHNESS_MS = 60000;
const CHANNELS = Object.freeze(['typed', 'voice']);

function json(status, obj) { return { status, json: obj }; }
const isStr = (v) => typeof v === 'string' && v.length > 0;

// Rebuild the change from the client-supplied preview and re-derive its hash; the client cannot
// forge a hash because we recompute it from the normalized text + classification it claims.
function reconstructChange(agentId, preview) {
  if (!preview || typeof preview !== 'object') return { ok: false, code: 'PREVIEW_REQUIRED' };
  const text = isStr(preview.normalizedText) ? preview.normalizedText : (isStr(preview.proposedText) ? normalize(preview.proposedText) : '');
  if (!text) return { ok: false, code: 'PREVIEW_TEXT_REQUIRED' };
  const type = isStr(preview.type) ? preview.type : 'MEMORY';
  const category = isStr(preview.category) ? preview.category : null;
  const sensitivity = isStr(preview.sensitivity) ? preview.sensitivity : 'low';
  const expiresAt = isStr(preview.expiresAt) ? preview.expiresAt : null;
  const hash = computeHash({ agentId, text, type, category, sensitivity, expiresAt });
  return { ok: true, change: { normalizedText: text, type, category, sensitivity, expiresAt, contentHash: hash, memoryKey: isStr(preview.memoryKey) ? preview.memoryKey : undefined } };
}

function createApprovalRoutes({ store, approvals, writer = null, identity = null, now = Date.now } = {}) {
  if (!store || !store.audit) throw new TypeError('approval routes require a store with audit');
  if (!approvals || typeof approvals.issue !== 'function' || typeof approvals.consume !== 'function') throw new TypeError('approval routes require an approval service');
  const clock = typeof now === 'function' ? now : () => now;

  function audit(eventType, fields) { try { store.audit.append(Object.assign({ eventType, at: clock() }, fields)); } catch { /* audit must never break the flow */ } }

  async function resolveIdentity(headers) {
    if (typeof identity !== 'function') return { ok: false, status: 503, code: 'IDENTITY_NOT_CONFIGURED' };
    let id = null;
    try { id = await identity(headers || {}); } catch { id = null; }
    if (!id || !isStr(id.userId) || !isStr(id.accountId)) return { ok: false, status: 401, code: 'UNAUTHENTICATED' };
    return { ok: true, userId: id.userId, accountId: id.accountId };
  }

  // grantPayload: the verified preview grant ({ agentId, iat, exp, pv, mgr }) supplied by the handler.
  async function request({ headers, body, grantPayload }) {
    if (!body || !isStr(body.sessionId) || !isStr(body.agentId) || !isStr(body.contentHash)) return json(400, { error: 'sessionId, agentId and contentHash are required', code: 'INVALID_INPUT' });
    if (!grantPayload || grantPayload.agentId !== body.agentId) return json(403, { error: 'grant not valid for this agent', code: 'AGENT_MISMATCH' });
    const who = await resolveIdentity(headers);
    if (!who.ok) return json(who.status, { error: 'identity required', code: who.code });
    const r = approvals.issue({ sessionId: body.sessionId, userId: who.userId, accountId: who.accountId, agentId: body.agentId, contentHash: body.contentHash, elevated: body.elevated === true });
    if (!r.ok) return json(400, { error: 'cannot issue approval', code: r.code, field: r.field });
    audit('APPROVAL_ISSUED', { sessionId: body.sessionId, userId: who.userId, accountId: who.accountId, agentId: body.agentId, contentHash: body.contentHash, approvalId: r.approvalId, elevated: r.elevated });
    return json(200, { approvalToken: r.token, approvalId: r.approvalId, expiresAt: r.expiresAt, elevated: r.elevated, note: 'single-use; expires in 120s' });
  }

  async function confirm({ headers, body, grantPayload }) {
    if (!body || !isStr(body.sessionId) || !isStr(body.agentId) || !isStr(body.contentHash) || !isStr(body.approvalToken)) {
      return json(400, { error: 'sessionId, agentId, contentHash and approvalToken are required', code: 'INVALID_INPUT' });
    }
    if (!grantPayload || grantPayload.agentId !== body.agentId) return json(403, { error: 'grant not valid for this agent', code: 'AGENT_MISMATCH' });
    const channel = isStr(body.channel) ? body.channel : 'typed';
    if (!CHANNELS.includes(channel)) return json(400, { error: 'channel must be typed or voice', code: 'INVALID_CHANNEL' });
    const who = await resolveIdentity(headers);
    if (!who.ok) return json(who.status, { error: 'identity required', code: who.code });

    // 1) rebuild the change and refuse if the claimed hash does not match what we recompute
    const rc = reconstructChange(body.agentId, body.preview);
    if (!rc.ok) return json(400, { error: 'preview required to confirm', code: rc.code });
    const change = rc.change;
    if (change.contentHash !== body.contentHash) {
      audit('CONFIRM_REJECTED', { sessionId: body.sessionId, agentId: body.agentId, reason: 'HASH_MISMATCH', claimed: body.contentHash, computed: change.contentHash });
      return json(409, { error: 'preview does not match contentHash', code: 'HASH_MISMATCH' });
    }

    // 2) policy re-check on the final text (defense in depth) + elevated-channel rule
    const policy = checkPolicy({ classification: { type: change.type, category: change.category, sensitivity: change.sensitivity, expiresAt: change.expiresAt }, finalText: change.normalizedText });
    if (!policy.allowed) {
      audit('CONFIRM_REJECTED', { sessionId: body.sessionId, agentId: body.agentId, reason: 'POLICY', violations: policy.violations.map((v) => v.code) });
      return json(422, { error: 'policy denies this change', code: policy.requiresQueue ? 'REQUIRES_QUEUE' : 'POLICY_DENIED', violations: policy.violations });
    }
    if (policy.elevated) {
      if (channel !== 'typed') { audit('CONFIRM_REJECTED', { sessionId: body.sessionId, agentId: body.agentId, reason: 'ELEVATED_VOICE' }); return json(403, { error: 'elevated changes require a typed confirmation', code: 'ELEVATED_REQUIRES_TYPED' }); }
      const iat = Number(grantPayload.iat) || 0;
      if (clock() - iat > ELEVATED_FRESHNESS_MS) { audit('CONFIRM_REJECTED', { sessionId: body.sessionId, agentId: body.agentId, reason: 'ELEVATED_STALE_VAULT' }); return json(403, { error: 'elevated changes require a vault verification within 60 seconds', code: 'ELEVATED_REQUIRES_FRESH_VAULT' }); }
    }

    // 3) consume the approval — atomic, single-use, bound
    const c = approvals.consume({ token: body.approvalToken, sessionId: body.sessionId, userId: who.userId, accountId: who.accountId, agentId: body.agentId, contentHash: body.contentHash });
    if (!c.ok) {
      audit('CONFIRM_REJECTED', { sessionId: body.sessionId, agentId: body.agentId, reason: 'APPROVAL_' + c.code });
      const status = c.code === 'EXPIRED' ? 410 : c.code === 'ALREADY_CONSUMED' ? 409 : c.code === 'BINDING_MISMATCH' ? 403 : 401;
      return json(status, { error: 'approval not valid', code: c.code });
    }
    if (policy.elevated && c.elevated !== true) {
      audit('CONFIRM_REJECTED', { sessionId: body.sessionId, agentId: body.agentId, reason: 'ELEVATED_NOT_DECLARED', approvalId: c.approvalId });
      return json(403, { error: 'this change is elevated but the approval was not issued as elevated', code: 'ELEVATED_NOT_DECLARED' });
    }

    // 4) write — only here, only after the consumed approval
    if (!writer || typeof writer.write !== 'function' || typeof writer.readByKey !== 'function') {
      audit('WRITE_SKIPPED', { sessionId: body.sessionId, agentId: body.agentId, approvalId: c.approvalId, reason: 'WRITER_NOT_CONFIGURED' });
      return json(503, { error: 'memory writer not configured', code: 'WRITER_NOT_CONFIGURED', approvalId: c.approvalId, approvalConsumed: true });
    }
    const memoryKey = deriveMemoryKey({ agentId: body.agentId, type: change.type, category: change.category, normalizedText: change.normalizedText, memoryKey: change.memoryKey });
    let previous = null;
    try {
      const before = await writer.readByKey({ userId: who.userId, agentId: body.agentId, memoryKey });
      if (before && before.content !== null && before.content !== change.normalizedText) previous = { contentHash: before.contentHash, content: before.content, at: before.updatedAt };
    } catch { previous = null; }
    let written;
    try {
      written = await writer.write({ userId: who.userId, agentId: body.agentId, change, memoryKey, previous, sessionId: body.sessionId, approvalId: c.approvalId });
    } catch (e) {
      audit('WRITE_FAILED', { sessionId: body.sessionId, agentId: body.agentId, approvalId: c.approvalId, memoryKey, error: String(e && e.message || e).slice(0, 200) });
      audit('ALERT', { sessionId: body.sessionId, agentId: body.agentId, reason: 'WRITE_FAILED', approvalId: c.approvalId });
      return json(502, { error: 'write failed', code: 'WRITE_FAILED', approvalId: c.approvalId, approvalConsumed: true });
    }
    audit('WRITE', { sessionId: body.sessionId, userId: who.userId, accountId: who.accountId, agentId: body.agentId, approvalId: c.approvalId, memoryKey, memoryId: written && written.id, contentHash: change.contentHash, superseded: !!previous });

    // 5) read back and verify — a mismatch is a REJECTED terminal with an ALERT
    let back = null;
    try { back = await writer.readByKey({ userId: who.userId, agentId: body.agentId, memoryKey }); } catch { back = null; }
    const verified = !!back && back.content === change.normalizedText && back.contentHash === change.contentHash && back.enabled && back.active && !back.deletedAt && !back.forgottenAt;
    if (!verified) {
      audit('VERIFICATION_FAILED', { sessionId: body.sessionId, agentId: body.agentId, approvalId: c.approvalId, memoryKey, expectedHash: change.contentHash, readBackHash: back && back.contentHash });
      audit('ALERT', { sessionId: body.sessionId, agentId: body.agentId, reason: 'VERIFICATION_FAILED', approvalId: c.approvalId, memoryKey });
      return json(409, { error: 'write could not be verified', code: 'VERIFICATION_FAILED', approvalId: c.approvalId, memoryKey, state: 'REJECTED' });
    }
    audit('VERIFIED', { sessionId: body.sessionId, agentId: body.agentId, approvalId: c.approvalId, memoryKey, memoryId: back.id, contentHash: change.contentHash });
    return json(200, { state: 'VERIFIED', memoryId: back.id, memoryKey, contentHash: change.contentHash, verifiedAt: clock(), superseded: previous ? { previousContentHash: previous.contentHash } : null, approvalId: c.approvalId });
  }

  return Object.freeze({ request, confirm, ELEVATED_FRESHNESS_MS });
}

module.exports = Object.freeze({ createApprovalRoutes, reconstructChange, ELEVATED_FRESHNESS_MS, CHANNELS });
