'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { STATES, EVENTS, EFFECTS, TTL_MS, LIMITS, createSession, transition } = require('../k136s_learning/domain/state_machine.cjs');

const T0 = 1_800_000_000_000;
const IDS = { id: 'sess-1', userId: 'mgr-1', accountId: 'acct-1', agentId: 'agent-1', profileId: 'prof-1' };
const actor = { userId: 'mgr-1', isAccountManager: true };
const preview = (over = {}) => Object.assign({
  finalText: 'Always escalate billing disputes to Maria.', normalizedText: 'Always escalate billing disputes to Maria.',
  contentHash: 'h1', classification: { type: 'TRAINING', category: 'escalation', sensitivity: 'low', expiresAt: null },
  policy: { allowed: true, elevated: false, requiresQueue: false, violations: [] }, duplicates: [], contradictions: [],
}, over);
const step = (s, ev, ctx) => { const r = transition(s, ev, ctx); assert.equal(r.ok, true, `${ev}: ${r.code} ${r.message}`); return r; };

function runToConfirmation(over = {}) {
  const effects = [];
  const track = (r) => { effects.push(...r.effects); return r.session; };
  let s = createSession(IDS, T0);
  s = track(step(s, EVENTS.TRIGGER, { now: T0, actor, source: 'live_convo', triggerMatched: true }));
  s = track(step(s, EVENTS.MIC_MUTED, { now: T0 + 1000, micMuted: true }));
  s = track(step(s, EVENTS.VAULT_VERIFIED, { now: T0 + 5000, vault: { verified: true, userId: 'mgr-1', accountId: 'acct-1', verifiedAt: T0 + 4000 } }));
  s = track(step(s, EVENTS.MIC_UNMUTED, { now: T0 + 6000, micMuted: false }));
  s = track(step(s, EVENTS.CAPTURE_TEXT, { now: T0 + 7000, text: 'always escalate billing disputes' }));
  s = track(step(s, EVENTS.CAPTURE_TEXT, { now: T0 + 8000, text: 'to Maria' }));
  s = track(step(s, EVENTS.END_CAPTURE, { now: T0 + 9000 }));
  s = track(step(s, EVENTS.CLASSIFIED, { now: T0 + 10000, preview: preview(over.preview) }));
  s = track(step(s, EVENTS.REQUEST_CONFIRMATION, { now: T0 + 11000, approval: Object.assign({ approvalId: 'ap-1', contentHash: 'h1', expiresAt: T0 + 11000 + TTL_MS.CONFIRMATION_REQUIRED, elevated: false }, over.approval) }));
  return { s, effects };
}

test('happy path reaches VERIFIED and WRITE is emitted only by APPROVE', () => {
  const { s, effects } = runToConfirmation();
  assert.equal(s.state, STATES.CONFIRMATION_REQUIRED);
  assert.equal(effects.includes(EFFECTS.WRITE), false, 'no WRITE effect before approval');
  assert.deepEqual(effects.slice(0, 3), [EFFECTS.MUTE_MIC, EFFECTS.AUDIT, EFFECTS.SHOW_VAULT_FIELD]);
  const consumed = { ok: true, approvalId: 'ap-1', contentHash: 'h1', userId: 'mgr-1', accountId: 'acct-1', agentId: 'agent-1' };
  const r1 = step(s, EVENTS.APPROVE, { now: T0 + 12000, consumed, channel: 'voice' });
  assert.equal(r1.session.state, STATES.COMMITTING);
  assert.deepEqual(r1.effects, [EFFECTS.WRITE]);
  const r2 = step(r1.session, EVENTS.COMMITTED, { now: T0 + 13000, write: { entryRef: 'mem-42', contentHash: 'h1' }, verification: { found: true, contentHash: 'h1', entryRef: 'mem-42' } });
  assert.equal(r2.session.state, STATES.VERIFIED);
  assert.equal(r2.session.write.verified, true);
  assert.deepEqual(r2.effects, [EFFECTS.REFRESH_CONTEXT, EFFECTS.AUDIT]);
  assert.equal(r2.session.capture.text, '', 'captured text wiped in terminal state');
  assert.equal(r2.session.history.length, 9);
});

test('unauthorized triggers fail: non-manager, wrong actor, meeting ingress, unmatched phrase', () => {
  const s = createSession(IDS, T0);
  assert.equal(transition(s, EVENTS.TRIGGER, { now: T0, actor: { userId: 'mgr-1', isAccountManager: false }, source: 'live_convo', triggerMatched: true }).code, 'NOT_ACCOUNT_MANAGER');
  assert.equal(transition(s, EVENTS.TRIGGER, { now: T0, actor: { userId: 'someone-else', isAccountManager: true }, source: 'live_convo', triggerMatched: true }).code, 'ACTOR_MISMATCH');
  assert.equal(transition(s, EVENTS.TRIGGER, { now: T0, actor, source: 'meeting_ingress', triggerMatched: true }).code, 'INVALID_SOURCE');
  assert.equal(transition(s, EVENTS.TRIGGER, { now: T0, actor, source: 'live_convo', triggerMatched: false }).code, 'TRIGGER_NOT_MATCHED');
  assert.equal(s.state, STATES.IDLE);
});

test('vault field is only shown after the microphone is muted', () => {
  let s = createSession(IDS, T0);
  s = step(s, EVENTS.TRIGGER, { now: T0, actor, source: 'live_convo', triggerMatched: true }).session;
  assert.equal(transition(s, EVENTS.MIC_MUTED, { now: T0 + 1, micMuted: false }).code, 'MIC_NOT_MUTED');
  assert.equal(transition(s, EVENTS.VAULT_VERIFIED, { now: T0 + 1, vault: { verified: true, userId: 'mgr-1', accountId: 'acct-1', verifiedAt: T0 } }).code, 'INVALID_TRANSITION');
});

test('vault verification must be positive, bound to the manager and account, and fresh', () => {
  let s = createSession(IDS, T0);
  s = step(s, EVENTS.TRIGGER, { now: T0, actor, source: 'live_convo', triggerMatched: true }).session;
  s = step(s, EVENTS.MIC_MUTED, { now: T0 + 1, micMuted: true }).session;
  assert.equal(transition(s, EVENTS.VAULT_VERIFIED, { now: T0 + 2, vault: { verified: false, userId: 'mgr-1', accountId: 'acct-1', verifiedAt: T0 } }).code, 'VAULT_NOT_VERIFIED');
  assert.equal(transition(s, EVENTS.VAULT_VERIFIED, { now: T0 + 2, vault: { verified: true, userId: 'mgr-2', accountId: 'acct-1', verifiedAt: T0 } }).code, 'VAULT_BINDING_MISMATCH');
  assert.equal(transition(s, EVENTS.VAULT_VERIFIED, { now: T0 + 2, vault: { verified: true, userId: 'mgr-1', accountId: 'acct-1', verifiedAt: T0 - TTL_MS.VAULT - 1 } }).code, 'VAULT_STALE');
});

test('five vault failures reject the session (mirrors the vault lockout)', () => {
  let s = createSession(IDS, T0);
  s = step(s, EVENTS.TRIGGER, { now: T0, actor, source: 'live_convo', triggerMatched: true }).session;
  s = step(s, EVENTS.MIC_MUTED, { now: T0 + 1, micMuted: true }).session;
  for (let i = 1; i < LIMITS.MAX_VAULT_FAILURES; i++) { s = step(s, EVENTS.VAULT_FAILED, { now: T0 + 10 + i }).session; assert.equal(s.state, STATES.AUTH_REQUIRED); assert.equal(s.vault.failures, i); }
  const r = step(s, EVENTS.VAULT_FAILED, { now: T0 + 100 });
  assert.equal(r.session.state, STATES.REJECTED);
  assert.equal(r.session.terminalReason, 'VAULT_LOCKED');
});

test('prohibited classification and policy violations reject at CLASSIFIED; queued policies reach PREVIEW_READY', () => {
  const base = () => { let s = createSession(IDS, T0); s = step(s, EVENTS.TRIGGER, { now: T0, actor, source: 'live_convo', triggerMatched: true }).session; s = step(s, EVENTS.MIC_MUTED, { now: T0, micMuted: true }).session; s = step(s, EVENTS.VAULT_VERIFIED, { now: T0, vault: { verified: true, userId: 'mgr-1', accountId: 'acct-1', verifiedAt: T0 } }).session; s = step(s, EVENTS.MIC_UNMUTED, { now: T0, micMuted: false }).session; s = step(s, EVENTS.CAPTURE_TEXT, { now: T0, text: 'x' }).session; return step(s, EVENTS.END_CAPTURE, { now: T0 }).session; };
  const r1 = step(base(), EVENTS.CLASSIFIED, { now: T0, preview: preview({ classification: { type: 'PROHIBITED' } }) });
  assert.equal(r1.session.state, STATES.REJECTED); assert.equal(r1.session.terminalReason, 'PROHIBITED_CONTENT');
  const r2 = step(base(), EVENTS.CLASSIFIED, { now: T0, preview: preview({ policy: { allowed: false, elevated: false, requiresQueue: false, violations: [{ code: 'SECRET_LIKE_CONTENT' }] } }) });
  assert.equal(r2.session.state, STATES.REJECTED); assert.equal(r2.session.terminalReason, 'POLICY_VIOLATION');
  const r3 = step(base(), EVENTS.CLASSIFIED, { now: T0, preview: preview({ classification: { type: 'TOOL_PERMISSION' }, policy: { allowed: false, elevated: true, requiresQueue: true, violations: [] } }) });
  assert.equal(r3.session.state, STATES.PREVIEW_READY);
  assert.equal(transition(r3.session, EVENTS.REQUEST_CONFIRMATION, { now: T0, approval: { approvalId: 'a', contentHash: 'h1', expiresAt: T0 + 1000, elevated: false } }).code, 'ELEVATED_REQUIRED');
  assert.equal(transition(base(), EVENTS.CLASSIFIED, { now: T0, preview: { finalText: 'x' } }).code, 'INVALID_PREVIEW');
});

test('approval must match content hash, session bindings and be consumed; elevated approvals cannot be voice', () => {
  const { s } = runToConfirmation();
  const ok = { ok: true, approvalId: 'ap-1', contentHash: 'h1', userId: 'mgr-1', accountId: 'acct-1', agentId: 'agent-1' };
  assert.equal(transition(s, EVENTS.APPROVE, { now: T0 + 12000, consumed: Object.assign({}, ok, { ok: false }), channel: 'voice' }).code, 'APPROVAL_NOT_CONSUMED');
  assert.equal(transition(s, EVENTS.APPROVE, { now: T0 + 12000, consumed: Object.assign({}, ok, { approvalId: 'other' }), channel: 'voice' }).code, 'APPROVAL_ID_MISMATCH');
  assert.equal(transition(s, EVENTS.APPROVE, { now: T0 + 12000, consumed: Object.assign({}, ok, { contentHash: 'h2' }), channel: 'voice' }).code, 'CONTENT_HASH_MISMATCH');
  assert.equal(transition(s, EVENTS.APPROVE, { now: T0 + 12000, consumed: Object.assign({}, ok, { accountId: 'acct-9' }), channel: 'voice' }).code, 'APPROVAL_BINDING_MISMATCH');
  assert.equal(transition(s, EVENTS.APPROVE, { now: T0 + 12000, consumed: ok }).code, 'CHANNEL_REQUIRED');
  assert.equal(transition(s, EVENTS.REQUEST_CONFIRMATION, { now: T0 + 12000, approval: { approvalId: 'x', contentHash: 'h2', expiresAt: T0 + 20000 } }).code, 'INVALID_TRANSITION');
  const el = runToConfirmation({ preview: { policy: { allowed: true, elevated: true, requiresQueue: false, violations: [] } }, approval: { elevated: true } }).s;
  assert.equal(transition(el, EVENTS.APPROVE, { now: T0 + 12000, consumed: ok, channel: 'voice' }).code, 'ELEVATED_VOICE_FORBIDDEN');
  assert.equal(transition(el, EVENTS.APPROVE, { now: T0 + 12000, consumed: ok, channel: 'typed', vaultReverifiedAt: T0 + 12000 - TTL_MS.ELEVATED_FRESHNESS - 1 }).code, 'VAULT_REVERIFY_REQUIRED');
  assert.equal(transition(el, EVENTS.APPROVE, { now: T0 + 12000, consumed: ok, channel: 'typed', vaultReverifiedAt: T0 + 11500 }).session.state, STATES.COMMITTING);
});

test('token expiry returns to PREVIEW_READY with a cleared approval; edit re-classifies', () => {
  const { s } = runToConfirmation();
  const r = step(s, EVENTS.TOKEN_EXPIRED, { now: T0 + 12000 });
  assert.equal(r.session.state, STATES.PREVIEW_READY); assert.equal(r.session.approval, null);
  const e = step(r.session, EVENTS.EDIT, { now: T0 + 12500, finalText: 'Always escalate billing disputes to Maria within one hour.' });
  assert.equal(e.session.state, STATES.CLASSIFYING); assert.deepEqual(e.effects, [EFFECTS.CLASSIFY]);
});

test('verification failure after a write is a REJECTED terminal with the write recorded and an ALERT', () => {
  const { s } = runToConfirmation();
  const consumed = { ok: true, approvalId: 'ap-1', contentHash: 'h1', userId: 'mgr-1', accountId: 'acct-1', agentId: 'agent-1' };
  const c = step(s, EVENTS.APPROVE, { now: T0 + 12000, consumed, channel: 'typed' }).session;
  assert.equal(transition(c, EVENTS.COMMITTED, { now: T0 + 13000, write: { entryRef: 'mem-1', contentHash: 'other' }, verification: { found: true } }).code, 'WRITE_RECORD_INVALID');
  const r = step(c, EVENTS.COMMITTED, { now: T0 + 13000, write: { entryRef: 'mem-1', contentHash: 'h1' }, verification: { found: false } });
  assert.equal(r.session.state, STATES.REJECTED); assert.equal(r.session.terminalReason, 'VERIFICATION_FAILED'); assert.equal(r.session.write.verified, false);
  assert.ok(r.effects.includes(EFFECTS.ALERT));
});

test('credentials are refused in any event context, at any depth', () => {
  const { s } = runToConfirmation();
  for (const ctx of [{ password: 'x' }, { vault: { credential: 'x' } }, { consumed: { token: 'raw' } }, { a: { b: { c: { vaultPassword: 'x' } } } }]) {
    const r = transition(s, EVENTS.APPROVE, Object.assign({ now: T0 + 12000, channel: 'typed' }, ctx));
    assert.equal(r.code, 'CREDENTIAL_IN_CONTEXT'); assert.equal(r.session, null);
  }
  assert.throws(() => createSession(Object.assign({}, IDS, { password: 'x' }), T0), /forbidden key/);
  assert.equal(JSON.stringify(s).includes('hunter2'), false);
});

test('expiry: session TTL, state TTL and approval TTL all lead to EXPIRED and unmute the mic', () => {
  let s = createSession(IDS, T0);
  s = step(s, EVENTS.TRIGGER, { now: T0, actor, source: 'live_convo', triggerMatched: true }).session;
  const r1 = step(s, EVENTS.TICK, { now: T0 + TTL_MS.SESSION + 1 });
  assert.equal(r1.session.state, STATES.EXPIRED); assert.ok(r1.effects.includes(EFFECTS.UNMUTE_MIC));
  s = step(s, EVENTS.MIC_MUTED, { now: T0 + 1, micMuted: true }).session;
  assert.equal(step(s, EVENTS.VAULT_FAILED, { now: T0 + TTL_MS.AUTH_REQUIRED + 2 }).session.state, STATES.EXPIRED);
  const { s: c } = runToConfirmation();
  assert.equal(step(c, EVENTS.TICK, { now: c.approval.expiresAt + 1 }).session.state, STATES.EXPIRED);
  assert.equal(step(c, EVENTS.TICK, { now: c.approval.expiresAt - 1 }).session.state, STATES.CONFIRMATION_REQUIRED);
});

test('terminal states are immutable, cancel works from any live state, sessions are frozen', () => {
  const { s } = runToConfirmation();
  const cancelled = step(s, EVENTS.CANCEL, { now: T0 + 12000 }).session;
  assert.equal(cancelled.state, STATES.CANCELLED); assert.equal(cancelled.approval, null); assert.equal(cancelled.capture.text, '');
  for (const ev of Object.values(EVENTS)) assert.equal(transition(cancelled, ev, { now: T0 + 13000 }).code, 'TERMINAL_STATE');
  assert.ok(Object.isFrozen(s)); assert.throws(() => { 'use strict'; s.state = STATES.VERIFIED; });
  assert.equal(transition(s, 'BOGUS', { now: T0 }).code, 'UNKNOWN_EVENT');
  assert.equal(transition(createSession(IDS, T0), EVENTS.CAPTURE_TEXT, { now: T0, text: 'x' }).code, 'INVALID_TRANSITION');
});

test('capture accumulates and enforces the length limit', () => {
  let s = createSession(IDS, T0);
  s = step(s, EVENTS.TRIGGER, { now: T0, actor, source: 'live_convo', triggerMatched: true }).session;
  s = step(s, EVENTS.MIC_MUTED, { now: T0, micMuted: true }).session;
  s = step(s, EVENTS.VAULT_VERIFIED, { now: T0, vault: { verified: true, userId: 'mgr-1', accountId: 'acct-1', verifiedAt: T0 } }).session;
  s = step(s, EVENTS.MIC_UNMUTED, { now: T0, micMuted: false }).session;
  assert.equal(transition(s, EVENTS.END_CAPTURE, { now: T0 }).code, 'EMPTY_TEXT');
  assert.equal(transition(s, EVENTS.CAPTURE_TEXT, { now: T0, text: '   ' }).code, 'EMPTY_TEXT');
  assert.equal(transition(s, EVENTS.CAPTURE_TEXT, { now: T0, text: 'x'.repeat(LIMITS.MAX_CAPTURE_CHARS + 1) }).code, 'CAPTURE_TOO_LONG');
  s = step(s, EVENTS.CAPTURE_TEXT, { now: T0, text: 'remember that' }).session;
  s = step(s, EVENTS.CAPTURE_TEXT, { now: T0, text: 'Acme prefers mornings' }).session;
  assert.equal(s.capture.text, 'remember that Acme prefers mornings');
});
