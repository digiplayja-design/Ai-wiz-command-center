'use strict';
// K136S - Nova Secure Spoken Learning: server-authoritative state machine (pure, no I/O).
// IDLE -> TRIGGERED -> AUTH_REQUIRED -> AUTHENTICATED -> CAPTURING -> CLASSIFYING -> PREVIEW_READY
//      -> CONFIRMATION_REQUIRED -> COMMITTING -> VERIFIED     (alternate terminals: CANCELLED, EXPIRED, REJECTED)
// The only transition that emits the WRITE effect is APPROVE, and APPROVE requires a consumed, bound approval.

const STATES = Object.freeze({
  IDLE: 'IDLE', TRIGGERED: 'TRIGGERED', AUTH_REQUIRED: 'AUTH_REQUIRED', AUTHENTICATED: 'AUTHENTICATED',
  CAPTURING: 'CAPTURING', CLASSIFYING: 'CLASSIFYING', PREVIEW_READY: 'PREVIEW_READY',
  CONFIRMATION_REQUIRED: 'CONFIRMATION_REQUIRED', COMMITTING: 'COMMITTING', VERIFIED: 'VERIFIED',
  CANCELLED: 'CANCELLED', EXPIRED: 'EXPIRED', REJECTED: 'REJECTED',
});
const TERMINAL_STATES = Object.freeze(new Set([STATES.VERIFIED, STATES.CANCELLED, STATES.EXPIRED, STATES.REJECTED]));
const EVENTS = Object.freeze({
  TRIGGER: 'TRIGGER', MIC_MUTED: 'MIC_MUTED', VAULT_VERIFIED: 'VAULT_VERIFIED', VAULT_FAILED: 'VAULT_FAILED',
  MIC_UNMUTED: 'MIC_UNMUTED', CAPTURE_TEXT: 'CAPTURE_TEXT', END_CAPTURE: 'END_CAPTURE', CLASSIFIED: 'CLASSIFIED',
  EDIT: 'EDIT', REQUEST_CONFIRMATION: 'REQUEST_CONFIRMATION', APPROVE: 'APPROVE', TOKEN_EXPIRED: 'TOKEN_EXPIRED',
  COMMITTED: 'COMMITTED', COMMIT_FAILED: 'COMMIT_FAILED', CANCEL: 'CANCEL', TICK: 'TICK',
});
const EFFECTS = Object.freeze({
  MUTE_MIC: 'MUTE_MIC', UNMUTE_MIC: 'UNMUTE_MIC', SHOW_VAULT_FIELD: 'SHOW_VAULT_FIELD', CLASSIFY: 'CLASSIFY',
  SHOW_PREVIEW: 'SHOW_PREVIEW', WRITE: 'WRITE', REFRESH_CONTEXT: 'REFRESH_CONTEXT', AUDIT: 'AUDIT', ALERT: 'ALERT',
});
const ENTRY_TYPES = Object.freeze({ MEMORY: 'MEMORY', TRAINING: 'TRAINING', PROFILE: 'PROFILE', TOOL_PERMISSION: 'TOOL_PERMISSION', PROHIBITED: 'PROHIBITED' });
const TTL_MS = Object.freeze({
  SESSION: 10 * 60 * 1000, AUTH_REQUIRED: 2 * 60 * 1000, CAPTURING: 3 * 60 * 1000, PREVIEW_READY: 10 * 60 * 1000,
  CONFIRMATION_REQUIRED: 120 * 1000, VAULT: 15 * 60 * 1000, ELEVATED_FRESHNESS: 60 * 1000,
});
const LIMITS = Object.freeze({ MAX_VAULT_FAILURES: 5, MAX_CAPTURE_CHARS: 4000 });
const TRIGGER_SOURCE = 'live_convo';
const FORBIDDEN_CONTEXT_KEYS = new Set(['credential', 'password', 'passwd', 'vaultpassword', 'vault_password', 'brainpassword', 'brain_password', 'secret', 'token', 'rawtoken', 'raw_token', 'plaintext']);

function findForbiddenKey(value, depth = 0) {
  if (!value || typeof value !== 'object' || depth > 6) return null;
  for (const key of Object.keys(value)) {
    if (FORBIDDEN_CONTEXT_KEYS.has(String(key).toLowerCase())) return key;
    const inner = findForbiddenKey(value[key], depth + 1);
    if (inner) return inner;
  }
  return null;
}
function fail(code, message) { return { ok: false, code, message, session: null, effects: [] }; }
function succeed(session, effects) { return { ok: true, session, effects: effects.slice(), code: null, message: null }; }
function isNonEmptyString(v) { return typeof v === 'string' && v.trim().length > 0; }

function createSession(input, now = Date.now()) {
  for (const k of ['id', 'userId', 'accountId', 'agentId']) if (!isNonEmptyString(input[k])) throw new TypeError(`createSession: ${k} required`);
  const forbidden = findForbiddenKey(input);
  if (forbidden) throw new TypeError(`createSession: forbidden key "${forbidden}"`);
  return Object.freeze({
    id: input.id, userId: input.userId, accountId: input.accountId, agentId: input.agentId, profileId: input.profileId || null,
    state: STATES.IDLE, createdAt: now, updatedAt: now, expiresAt: null, stateExpiresAt: null,
    micMuted: false, vault: { verifiedAt: null, failures: 0 }, capture: { text: '' },
    preview: null, approval: null, write: null, terminalReason: null, history: [],
  });
}

function enter(session, state, event, now, extra = {}) {
  const next = structuredClone(session);
  Object.assign(next, extra);
  next.history = next.history.concat([{ from: session.state, to: state, event, at: now }]);
  next.state = state;
  next.updatedAt = now;
  if (TERMINAL_STATES.has(state)) { next.stateExpiresAt = null; next.capture = { text: '' }; next.approval = null; }
  return Object.freeze(next);
}
function terminal(session, state, reason, event, now, extra = {}) {
  return enter(session, state, event, now, Object.assign({ terminalReason: reason }, extra));
}

function transition(session, event, ctx = {}) {
  const now = Number.isFinite(ctx.now) ? ctx.now : Date.now();
  if (!session || typeof session !== 'object') return fail('INVALID_SESSION', 'session required');
  const forbidden = findForbiddenKey(ctx);
  if (forbidden) return fail('CREDENTIAL_IN_CONTEXT', `refusing event ${event}: context key "${forbidden}" is not allowed in the state machine`);
  if (TERMINAL_STATES.has(session.state)) return fail('TERMINAL_STATE', `session is ${session.state}`);

  // Expiry is checked before every event so a stale session can never advance.
  if ((session.expiresAt && now > session.expiresAt) || (session.stateExpiresAt && now > session.stateExpiresAt)) {
    return succeed(terminal(session, STATES.EXPIRED, 'TTL_ELAPSED', event, now), [EFFECTS.UNMUTE_MIC, EFFECTS.AUDIT]);
  }
  if (event === EVENTS.TICK) return succeed(session, []);
  if (event === EVENTS.CANCEL) return succeed(terminal(session, STATES.CANCELLED, 'USER_CANCELLED', event, now), [EFFECTS.UNMUTE_MIC, EFFECTS.AUDIT]);

  const s = session.state;
  switch (event) {
    case EVENTS.TRIGGER: {
      if (s !== STATES.IDLE) break;
      const actor = ctx.actor || {};
      if (actor.userId !== session.userId) return fail('ACTOR_MISMATCH', 'trigger actor is not the session owner');
      if (actor.isAccountManager !== true) return fail('NOT_ACCOUNT_MANAGER', 'only an account manager may trigger learning');
      if (ctx.source !== TRIGGER_SOURCE) return fail('INVALID_SOURCE', `trigger source must be ${TRIGGER_SOURCE}`);
      if (ctx.triggerMatched !== true) return fail('TRIGGER_NOT_MATCHED', 'no learning trigger phrase in a final transcript');
      return succeed(enter(session, STATES.TRIGGERED, event, now, { expiresAt: now + TTL_MS.SESSION }), [EFFECTS.MUTE_MIC, EFFECTS.AUDIT]);
    }
    case EVENTS.MIC_MUTED: {
      if (s !== STATES.TRIGGERED) break;
      if (ctx.micMuted !== true) return fail('MIC_NOT_MUTED', 'vault field may only be shown after the microphone is muted');
      return succeed(enter(session, STATES.AUTH_REQUIRED, event, now, { micMuted: true, stateExpiresAt: now + TTL_MS.AUTH_REQUIRED }), [EFFECTS.SHOW_VAULT_FIELD]);
    }
    case EVENTS.VAULT_VERIFIED: {
      if (s !== STATES.AUTH_REQUIRED) break;
      const v = ctx.vault || {};
      if (v.verified !== true) return fail('VAULT_NOT_VERIFIED', 'vault verification result is not positive');
      if (v.userId !== session.userId || v.accountId !== session.accountId) return fail('VAULT_BINDING_MISMATCH', 'vault verification is for a different manager or account');
      if (!Number.isFinite(v.verifiedAt) || v.verifiedAt > now + 1000 || now - v.verifiedAt > TTL_MS.VAULT) return fail('VAULT_STALE', 'vault verification timestamp is missing or stale');
      return succeed(enter(session, STATES.AUTHENTICATED, event, now, { vault: { verifiedAt: v.verifiedAt, failures: session.vault.failures }, stateExpiresAt: null }), [EFFECTS.UNMUTE_MIC, EFFECTS.AUDIT]);
    }
    case EVENTS.VAULT_FAILED: {
      if (s !== STATES.AUTH_REQUIRED) break;
      const failures = session.vault.failures + 1;
      if (failures >= LIMITS.MAX_VAULT_FAILURES) return succeed(terminal(session, STATES.REJECTED, 'VAULT_LOCKED', event, now, { vault: { verifiedAt: null, failures } }), [EFFECTS.UNMUTE_MIC, EFFECTS.AUDIT]);
      const next = structuredClone(session); next.vault = { verifiedAt: null, failures }; next.updatedAt = now;
      return succeed(Object.freeze(next), []);
    }
    case EVENTS.MIC_UNMUTED: {
      if (s !== STATES.AUTHENTICATED) break;
      if (ctx.micMuted !== false) return fail('MIC_STATE_UNKNOWN', 'capture requires a confirmed unmuted microphone');
      return succeed(enter(session, STATES.CAPTURING, event, now, { micMuted: false, stateExpiresAt: now + TTL_MS.CAPTURING }), []);
    }
    case EVENTS.CAPTURE_TEXT: {
      if (s !== STATES.CAPTURING) break;
      if (!isNonEmptyString(ctx.text)) return fail('EMPTY_TEXT', 'captured text is empty');
      const text = (session.capture.text + ' ' + ctx.text).trim();
      if (text.length > LIMITS.MAX_CAPTURE_CHARS) return fail('CAPTURE_TOO_LONG', `capture exceeds ${LIMITS.MAX_CAPTURE_CHARS} characters`);
      const next = structuredClone(session); next.capture = { text }; next.updatedAt = now;
      return succeed(Object.freeze(next), []);
    }
    case EVENTS.END_CAPTURE: {
      if (s !== STATES.CAPTURING) break;
      if (!isNonEmptyString(session.capture.text)) return fail('EMPTY_TEXT', 'nothing was captured');
      return succeed(enter(session, STATES.CLASSIFYING, event, now, { stateExpiresAt: null }), [EFFECTS.CLASSIFY]);
    }
    case EVENTS.CLASSIFIED: {
      if (s !== STATES.CLASSIFYING) break;
      const p = ctx.preview || {};
      const cls = p.classification || {};
      const pol = p.policy || {};
      if (!isNonEmptyString(p.contentHash) || !isNonEmptyString(p.finalText) || !isNonEmptyString(cls.type)) return fail('INVALID_PREVIEW', 'preview must carry finalText, classification.type and contentHash');
      if (cls.type === ENTRY_TYPES.PROHIBITED) return succeed(terminal(session, STATES.REJECTED, 'PROHIBITED_CONTENT', event, now, { preview: p }), [EFFECTS.UNMUTE_MIC, EFFECTS.AUDIT]);
      if (pol.allowed !== true && pol.requiresQueue !== true) return succeed(terminal(session, STATES.REJECTED, 'POLICY_VIOLATION', event, now, { preview: p }), [EFFECTS.UNMUTE_MIC, EFFECTS.AUDIT]);
      return succeed(enter(session, STATES.PREVIEW_READY, event, now, { preview: p, approval: null, stateExpiresAt: now + TTL_MS.PREVIEW_READY }), [EFFECTS.SHOW_PREVIEW]);
    }
    case EVENTS.EDIT: {
      if (s !== STATES.PREVIEW_READY) break;
      return succeed(enter(session, STATES.CLASSIFYING, event, now, { approval: null, stateExpiresAt: null }), [EFFECTS.CLASSIFY]);
    }
    case EVENTS.REQUEST_CONFIRMATION: {
      if (s !== STATES.PREVIEW_READY) break;
      const a = ctx.approval || {};
      const pol = session.preview.policy || {};
      if (!isNonEmptyString(a.approvalId) || !Number.isFinite(a.expiresAt)) return fail('INVALID_APPROVAL', 'an issued approval with approvalId and expiresAt is required');
      if (a.contentHash !== session.preview.contentHash) return fail('CONTENT_HASH_MISMATCH', 'approval was issued for different content');
      const mustBeElevated = pol.elevated === true || pol.requiresQueue === true;
      if (mustBeElevated && a.elevated !== true) return fail('ELEVATED_REQUIRED', 'this change requires an elevated approval');
      return succeed(enter(session, STATES.CONFIRMATION_REQUIRED, event, now, { approval: { approvalId: a.approvalId, contentHash: a.contentHash, expiresAt: a.expiresAt, elevated: a.elevated === true }, stateExpiresAt: a.expiresAt }), [EFFECTS.AUDIT]);
    }
    case EVENTS.APPROVE: {
      if (s !== STATES.CONFIRMATION_REQUIRED) break;
      const c = ctx.consumed || {};
      const ap = session.approval;
      if (c.ok !== true) return fail('APPROVAL_NOT_CONSUMED', 'approval token was not consumed');
      if (c.approvalId !== ap.approvalId) return fail('APPROVAL_ID_MISMATCH', 'consumed approval does not belong to this session');
      if (c.contentHash !== session.preview.contentHash || c.contentHash !== ap.contentHash) return fail('CONTENT_HASH_MISMATCH', 'approved content differs from the preview');
      if (c.userId !== session.userId || c.accountId !== session.accountId || c.agentId !== session.agentId) return fail('APPROVAL_BINDING_MISMATCH', 'approval is bound to a different manager, account or agent');
      if (ap.elevated) {
        if (ctx.channel !== 'typed') return fail('ELEVATED_VOICE_FORBIDDEN', 'elevated changes cannot be approved by voice');
        if (!Number.isFinite(ctx.vaultReverifiedAt) || now - ctx.vaultReverifiedAt > TTL_MS.ELEVATED_FRESHNESS || ctx.vaultReverifiedAt > now + 1000) return fail('VAULT_REVERIFY_REQUIRED', 'elevated changes need a vault re-verification within 60 seconds');
      } else if (ctx.channel !== 'typed' && ctx.channel !== 'voice') return fail('CHANNEL_REQUIRED', 'approval channel must be typed or voice');
      return succeed(enter(session, STATES.COMMITTING, event, now, { stateExpiresAt: null }), [EFFECTS.WRITE]);
    }
    case EVENTS.TOKEN_EXPIRED: {
      if (s !== STATES.CONFIRMATION_REQUIRED) break;
      return succeed(enter(session, STATES.PREVIEW_READY, event, now, { approval: null, stateExpiresAt: now + TTL_MS.PREVIEW_READY }), [EFFECTS.SHOW_PREVIEW]);
    }
    case EVENTS.COMMITTED: {
      if (s !== STATES.COMMITTING) break;
      const w = ctx.write || {}; const vr = ctx.verification || {};
      if (!isNonEmptyString(w.entryRef) || w.contentHash !== session.preview.contentHash) return fail('WRITE_RECORD_INVALID', 'write record must reference the entry and carry the preview content hash');
      if (vr.found === true && vr.contentHash === session.preview.contentHash && vr.entryRef === w.entryRef) {
        return succeed(terminal(session, STATES.VERIFIED, 'VERIFIED', event, now, { write: { entryRef: w.entryRef, contentHash: w.contentHash, verified: true } }), [EFFECTS.REFRESH_CONTEXT, EFFECTS.AUDIT]);
      }
      return succeed(terminal(session, STATES.REJECTED, 'VERIFICATION_FAILED', event, now, { write: { entryRef: w.entryRef, contentHash: w.contentHash, verified: false } }), [EFFECTS.ALERT, EFFECTS.AUDIT]);
    }
    case EVENTS.COMMIT_FAILED: {
      if (s !== STATES.COMMITTING) break;
      return succeed(terminal(session, STATES.REJECTED, 'WRITE_FAILED', event, now), [EFFECTS.ALERT, EFFECTS.AUDIT]);
    }
    default:
      return fail('UNKNOWN_EVENT', `unknown event ${event}`);
  }
  return fail('INVALID_TRANSITION', `event ${event} is not valid in state ${s}`);
}

module.exports = { STATES, TERMINAL_STATES, EVENTS, EFFECTS, ENTRY_TYPES, TTL_MS, LIMITS, TRIGGER_SOURCE, createSession, transition, findForbiddenKey };
