'use strict';
// K135Z C1 draft for static review. Not imported or executed for this return.
const { createHash } = require('node:crypto');
const VERSION = 'K135Z-KAI-CONTRACT-v1 / MAIN-DECISIONS-01';
const LIMITS = Object.freeze({
  envelope: 32768, text: 8192, retainedCount: 2000,
  retainedText: 4194304, queueCount: 256, queueBytes: 524288,
  eventHistory: 20000, revisionHistory: 20000, auxiliary: 8388608,
  notesCount: 500, notesText: 262144, insights: 100,
  perCategory: 25, evidence: 16, result: 524288, preview: 524288,
  sessionTimeoutMs: 15000, notesTimeoutMs: 30000
});
const CATEGORIES = Object.freeze({
  decisions: 'decision', actionItems: 'actionItem', deadlines: 'deadline',
  risks: 'risk', openQuestions: 'openQuestion', takeaways: 'takeaway'
});
const STATES = Object.freeze(['ready', 'listening', 'paused', 'stopped', 'error']);
const MESSAGES = Object.freeze({
  INVALID_INPUT: 'Input does not match the agreed contract.',
  CONTEXT_MISMATCH: 'Input does not match the selected context.',
  PROTOCOL_CONFLICT: 'Conflicting input requires trusted resolution.',
  EMPTY_TEXT: 'Whitespace-only input did not replace content.',
  FINALITY_DOWNGRADE: 'Finalized content cannot become provisional.',
  LIMIT_EXCEEDED: 'A configured processing bound was exceeded.',
  WINDOW_TRUNCATED: 'Known source material is outside this window.',
  CAPTURE_GAP: 'The trusted source reported capture gaps.',
  COVERAGE_UNKNOWN: 'Complete meeting coverage has not been established.',
  PROVISIONAL_EXCLUDED: 'Provisional content is not evidence.',
  NO_FINALIZED_INPUT: 'No finalized input is available.',
  INVALID_EVIDENCE: 'Evidence does not match the exact input window.',
  NOTES_INVALIDATED: 'Source changes invalidated this draft.',
  NOTES_OUTDATED: 'Later finalized material is not reflected.',
  DEADLINE_UNRESOLVED: 'The stated deadline requires review.',
  GENERATOR_ERROR: 'The generation operation did not produce a valid result.',
  TIMEOUT: 'The local operation timed out; no retry was requested.',
  CANCELLED: 'The local operation was cancelled.',
  REVIEW_REQUIRED: 'Draft output requires human review.'
});
const FIELDS = new Set([
  'input', 'context', 'event', 'control', 'coverage', 'metadata',
  'notes', 'evidence', 'deadline', 'window', 'queue', 'history', 'operation'
]);
const BLANK = /^[\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]*$/u;
class ContractError extends Error {
  constructor(code = 'INVALID_INPUT', field = 'input') {
    super(MESSAGES[code] || MESSAGES.INVALID_INPUT);
    this.name = 'ContractError';
    this.code = Object.hasOwn(MESSAGES, code) ? code : 'INVALID_INPUT';
    this.field = FIELDS.has(field) ? field : 'input';
  }
}
function fail(code = 'INVALID_INPUT', field = 'input') {
  throw new ContractError(code, field);
}
function requireValue(ok, code = 'INVALID_INPUT', field = 'input') {
  if (!ok) fail(code, field);
}
function uint(value, field = 'input') {
  requireValue(typeof value === 'number' && Number.isSafeInteger(value) &&
    value >= 0 && !Object.is(value, -0), 'INVALID_INPUT', field);
  return value;
}
function text(value, field = 'input') {
  requireValue(typeof value === 'string', 'INVALID_INPUT', field);
  for (const ch of value) {
    const cp = ch.codePointAt(0);
    requireValue(cp < 0xd800 || cp > 0xdfff, 'INVALID_INPUT', field);
  }
  return value;
}
function nonblank(value, field = 'input') {
  text(value, field);
  requireValue(!BLANK.test(value), 'INVALID_INPUT', field);
  return value;
}
function id(value, field = 'context') {
  nonblank(value, field);
  requireValue(Buffer.byteLength(value, 'utf8') <= 256, 'LIMIT_EXCEEDED', field);
  return value;
}
function bool(value, field = 'input') {
  requireValue(typeof value === 'boolean', 'INVALID_INPUT', field);
  return value;
}
function oneOf(value, options, field = 'input') {
  requireValue(options.includes(value), 'INVALID_INPUT', field);
  return value;
}
function nullable(value, validate) { return value === null ? null : validate(value); }
function object(value, required, optional = [], field = 'input') {
  requireValue(value !== null && typeof value === 'object' &&
    !Array.isArray(value), 'INVALID_INPUT', field);
  const proto = Object.getPrototypeOf(value);
  requireValue(proto === Object.prototype || proto === null, 'INVALID_INPUT', field);
  const keys = Reflect.ownKeys(value);
  requireValue(keys.every(k => typeof k === 'string' &&
    (required.includes(k) || optional.includes(k))), 'INVALID_INPUT', field);
  requireValue(required.every(k => Object.hasOwn(value, k)), 'INVALID_INPUT', field);
  for (const k of keys) {
    const d = Object.getOwnPropertyDescriptor(value, k);
    requireValue(d.enumerable && Object.hasOwn(d, 'value'), 'INVALID_INPUT', field);
  }
  return value;
}
function array(value, field = 'input') {
  requireValue(Array.isArray(value), 'INVALID_INPUT', field);
  requireValue(Reflect.ownKeys(value).length === value.length + 1,
    'INVALID_INPUT', field);
  for (let i = 0; i < value.length; i += 1) {
    const d = Object.getOwnPropertyDescriptor(value, String(i));
    requireValue(d && d.enumerable && Object.hasOwn(d, 'value'),
      'INVALID_INPUT', field);
  }
  return value;
}
function scalarCompare(a, b) {
  const aa = Array.from(text(a), ch => ch.codePointAt(0));
  const bb = Array.from(text(b), ch => ch.codePointAt(0));
  for (let i = 0; i < Math.min(aa.length, bb.length); i += 1) {
    if (aa[i] !== bb[i]) return aa[i] < bb[i] ? -1 : 1;
  }
  return Math.sign(aa.length - bb.length);
}
function quote(value) {
  let out = '"';
  for (const ch of text(value)) {
    const n = ch.codePointAt(0);
    out += ch === '"' ? '\\"' : ch === '\\' ? '\\\\' :
      n < 32 ? '\\u' + n.toString(16).padStart(4, '0') : ch;
  }
  return out + '"';
}
function canonical(value) {
  const active = new Set();
  function encode(v) {
    if (v === null) return 'null';
    if (typeof v === 'string') return quote(v);
    if (typeof v === 'boolean') return v ? 'true' : 'false';
    if (typeof v === 'number') return String(uint(v));
    requireValue(v && typeof v === 'object' && !active.has(v));
    active.add(v);
    let result;
    if (Array.isArray(v)) {
      result = '[' + array(v).map(encode).join(',') + ']';
    } else {
      object(v, Object.keys(v));
      result = '{' + Object.keys(v).sort(scalarCompare)
        .map(k => quote(k) + ':' + encode(v[k])).join(',') + '}';
    }
    active.delete(v);
    return result;
  }
  return encode(value);
}
function bytes(value) { return Buffer.byteLength(canonical(value), 'utf8'); }
function hash(value) {
  return createHash('sha256').update(canonical(value), 'utf8').digest('hex');
}
function clone(value) { return JSON.parse(canonical(value)); }
function freeze(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.values(value).forEach(freeze);
    Object.freeze(value);
  }
  return value;
}
function utc(value, field = 'input') {
  text(value, field);
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{3}))?Z$/.exec(value);
  requireValue(m !== null, 'INVALID_INPUT', field);
  const [y, mo, d, h, mi, s] = m.slice(1, 7).map(Number);
  const leap = y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0);
  const days = [0, 31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  requireValue(y >= 1 && mo >= 1 && mo <= 12 && d >= 1 && d <= days[mo] &&
    h <= 23 && mi <= 59 && s <= 59, 'INVALID_INPUT', field);
  return value.slice(0, 19) + '.' + (m[7] || '000') + 'Z';
}
const CONTEXT_KEYS = ['tenantId', 'userId', 'agentId', 'sessionId',
  'meetingUuid', 'streamId', 'generation'];
function context(raw, active = false) {
  object(raw, CONTEXT_KEYS, [], 'context');
  const out = {};
  for (const key of CONTEXT_KEYS.slice(0, 5)) out[key] = id(raw[key]);
  out.streamId = nullable(raw.streamId, id);
  out.generation = uint(raw.generation, 'context');
  requireValue(!active || out.streamId !== null, 'INVALID_INPUT', 'context');
  return freeze(out);
}
function sameContext(a, b) { return canonical(context(a)) === canonical(context(b)); }
function checkSize(value, limit, field) {
  requireValue(bytes(value) <= limit, 'LIMIT_EXCEEDED', field);
}
function validateEvent(raw, expectedContext) {
  object(raw, ['schemaVersion', 'context', 'eventId', 'segmentId',
    'segmentRevision', 'sequence', 'startMs', 'text', 'isFinal',
    'receivedAt', 'source'], ['speakerId', 'speakerName', 'endMs'], 'event');
  requireValue(raw.schemaVersion === 1, 'INVALID_INPUT', 'event');
  const ctx = context(raw.context, true);
  requireValue(sameContext(ctx, expectedContext), 'CONTEXT_MISMATCH', 'context');
  const out = { schemaVersion: 1, context: ctx, eventId: id(raw.eventId, 'event'),
    segmentId: id(raw.segmentId, 'event'),
    segmentRevision: uint(raw.segmentRevision, 'event'),
    sequence: uint(raw.sequence, 'event'), startMs: uint(raw.startMs, 'event'),
    text: text(raw.text, 'event'), isFinal: bool(raw.isFinal, 'event'),
    receivedAt: utc(raw.receivedAt, 'event'),
    source: oneOf(raw.source, ['zoom_rtms', 'offline_fixture'], 'event') };
  if (Object.hasOwn(raw, 'speakerId')) out.speakerId = id(raw.speakerId, 'event');
  if (Object.hasOwn(raw, 'speakerName')) out.speakerName = text(raw.speakerName, 'event');
  if (Object.hasOwn(raw, 'endMs')) {
    out.endMs = uint(raw.endMs, 'event');
    requireValue(out.endMs >= out.startMs, 'INVALID_INPUT', 'event');
  }
  requireValue(Buffer.byteLength(out.text, 'utf8') <= LIMITS.text,
    'LIMIT_EXCEEDED', 'event');
  checkSize(out, LIMITS.envelope, 'event');
  return freeze(out);
}
function warning(code, field = 'input', severity = 'warning') {
  requireValue(Object.hasOwn(MESSAGES, code) && FIELDS.has(field));
  return freeze({ code, severity, field, eventId: null, segment: null,
    message: MESSAGES[code], occurrences: 1 });
}
function rejection(error) {
  return warning(error instanceof ContractError ? error.code : 'INVALID_INPUT',
    error instanceof ContractError ? error.field : 'input', 'error');
}
function normalizeEvent(raw, expectedContext) {
  try { return { ok: true, event: validateEvent(raw, expectedContext) }; }
  catch (error) { return { ok: false, rejection: rejection(error) }; }
}
function nextWarningCount(value) {
  // Check before arithmetic. Callers owning transcript state convert this
  // typed capacity failure into a bounded block, never an inexact counter.
  const current = uint(value, 'history');
  requireValue(current >= 1, 'INVALID_INPUT', 'history');
  requireValue(current < Number.MAX_SAFE_INTEGER, 'LIMIT_EXCEEDED', 'history');
  return current + 1;
}
function mergeWarnings(previous, emitted, increment = true) {
  const out = previous.slice();
  const seen = new Set();
  for (const w of emitted) {
    const key = canonical([w.code, w.field, w.severity]);
    if (seen.has(key)) continue;
    seen.add(key);
    const at = out.findIndex(x => canonical([x.code, x.field, x.severity]) === key);
    if (at < 0) out.push(w);
    else if (increment) out[at] = freeze({ ...out[at],
      occurrences: nextWarningCount(out[at].occurrences) });
  }
  return freeze(out);
}
function ref(raw) {
  object(raw, ['segmentId', 'segmentRevision'], [], 'evidence');
  return freeze({ segmentId: id(raw.segmentId, 'evidence'),
    segmentRevision: uint(raw.segmentRevision, 'evidence') });
}
function refCompare(a, b) {
  return scalarCompare(a.segmentId, b.segmentId) ||
    Math.sign(a.segmentRevision - b.segmentRevision);
}
function eventCompare(a, b) {
  return Math.sign(a.startMs - b.startMs) || Math.sign(a.sequence - b.sequence) ||
    scalarCompare(a.segmentId, b.segmentId);
}
function speaker(event) {
  return !Object.hasOwn(event, 'speakerName') || BLANK.test(event.speakerName) ?
    'Unknown speaker' : event.speakerName;
}
function ranges(raw) {
  const sorted = array(raw, 'coverage').map(r => {
    object(r, ['startMs', 'endMs'], [], 'coverage');
    const out = { startMs: uint(r.startMs), endMs: uint(r.endMs) };
    requireValue(out.endMs > out.startMs, 'INVALID_INPUT', 'coverage');
    return out;
  }).sort((a, b) => a.startMs - b.startMs || a.endMs - b.endMs);
  const out = [];
  for (const r of sorted) {
    const tail = out[out.length - 1];
    if (tail && r.startMs <= tail.endMs) tail.endMs = Math.max(tail.endMs, r.endMs);
    else out.push({ ...r });
  }
  return freeze(out);
}
function snapshot(raw) {
  object(raw, ['schemaVersion', 'context', 'revision', 'state', 'hostAuthorized',
    'listeningAuthorized', 'activeSeconds', 'capabilities'], [], 'control');
  requireValue(raw.schemaVersion === 1, 'INVALID_INPUT', 'control');
  object(raw.capabilities, ['canSpeak'], [], 'control');
  requireValue(raw.capabilities.canSpeak === false, 'INVALID_INPUT', 'control');
  const out = { schemaVersion: 1, context: context(raw.context),
    revision: uint(raw.revision), state: oneOf(raw.state, STATES, 'control'),
    hostAuthorized: bool(raw.hostAuthorized),
    listeningAuthorized: bool(raw.listeningAuthorized),
    activeSeconds: uint(raw.activeSeconds), capabilities: { canSpeak: false } };
  checkSize(out, LIMITS.envelope, 'control');
  return freeze(out);
}
function operation(raw) {
  object(raw, ['requestId', 'localEpoch', 'operationNumber'], [], 'operation');
  return freeze({ requestId: id(raw.requestId), localEpoch: uint(raw.localEpoch),
    operationNumber: uint(raw.operationNumber) });
}
function operationError(raw) {
  object(raw, ['code', 'message', 'remoteOutcome', 'automaticRetry'], [], 'operation');
  oneOf(raw.code, ['UNAVAILABLE', 'DENIED', 'TIMEOUT', 'CANCELLED',
    'BINDING_MISMATCH', 'CONFLICT', 'PROTOCOL_ERROR'], 'operation');
  nonblank(raw.message, 'operation');
  oneOf(raw.remoteOutcome, ['notRequested', 'rejected', 'unknown'], 'operation');
  requireValue(raw.automaticRetry === false, 'INVALID_INPUT', 'operation');
  return freeze({ code: raw.code, message: 'The requested operation did not complete successfully.',
    remoteOutcome: raw.remoteOutcome, automaticRetry: false });
}
function control(raw, kind, expected) {
  // Validate the entire raw data envelope before selecting a variant.
  checkSize(raw, LIMITS.envelope, 'control');
  let out;
  if (kind === 'authority') {
    object(raw, ['authorityRevision', 'context', 'viewerAuthorized'], [], 'control');
    out = { authorityRevision: uint(raw.authorityRevision),
      context: nullable(raw.context, context), viewerAuthorized: bool(raw.viewerAuthorized) };
  } else if (kind === 'request') {
    object(raw, ['schemaVersion', 'operation', 'action', 'expectedContext',
      'expectedSnapshotRevision'], [], 'control');
    requireValue(raw.schemaVersion === 1, 'INVALID_INPUT', 'control');
    out = { schemaVersion: 1, operation: operation(raw.operation),
      action: oneOf(raw.action, ['refresh', 'start', 'pause', 'stop']),
      expectedContext: context(raw.expectedContext),
      expectedSnapshotRevision: nullable(raw.expectedSnapshotRevision, uint) };
    requireValue(out.action === 'refresh' || out.expectedSnapshotRevision !== null,
      'INVALID_INPUT', 'control');
  } else if (kind === 'reply') {
    object(raw, ['schemaVersion', 'operation', 'action', 'outcome'], [], 'control');
    requireValue(raw.schemaVersion === 1, 'INVALID_INPUT', 'control');
    object(raw.outcome, ['kind'], ['snapshot', 'error'], 'control');
    const acknowledged = raw.outcome.kind === 'acknowledged';
    object(raw.outcome, acknowledged ? ['kind', 'snapshot'] : ['kind', 'error'], [], 'control');
    requireValue(acknowledged || raw.outcome.kind === 'failed', 'INVALID_INPUT', 'control');
    out = { schemaVersion: 1, operation: operation(raw.operation),
      action: oneOf(raw.action, ['refresh', 'start', 'pause', 'stop']),
      outcome: acknowledged ? { kind: 'acknowledged', snapshot: snapshot(raw.outcome.snapshot) } :
        { kind: 'failed', error: operationError(raw.outcome.error) } };
  } else if (kind === 'signal') {
    object(raw, ['kind'], ['snapshot', 'event', 'context', 'revision', 'gaps'], 'control');
    if (raw.kind === 'snapshot' || raw.kind === 'meetingEnded') {
      object(raw, ['kind', 'snapshot'], [], 'control');
      out = { kind: raw.kind, snapshot: snapshot(raw.snapshot) };
      requireValue(raw.kind !== 'meetingEnded' || out.snapshot.state === 'stopped',
        'INVALID_INPUT', 'control');
    } else if (raw.kind === 'transportLost') {
      object(raw, ['kind', 'context'], [], 'control');
      out = { kind: raw.kind, context: context(raw.context) };
    } else if (raw.kind === 'captureGaps') {
      object(raw, ['kind', 'context', 'revision', 'gaps'], [], 'control');
      out = { kind: raw.kind, context: context(raw.context),
        revision: uint(raw.revision), gaps: ranges(raw.gaps) };
    } else {
      object(raw, ['kind', 'event'], [], 'control');
      requireValue(raw.kind === 'transcript', 'INVALID_INPUT', 'control');
      out = { kind: 'transcript', event: validateEvent(raw.event, expected) };
    }
  } else fail('INVALID_INPUT', 'control');
  checkSize(out, LIMITS.envelope, 'control');
  return freeze(out);
}
module.exports = Object.freeze({ VERSION, LIMITS, CATEGORIES, STATES, MESSAGES,
  ContractError, fail, requireValue, uint, text, nonblank, id, bool, oneOf,
  nullable, object, array, scalarCompare, canonical, bytes, hash, clone, freeze,
  utc, context, sameContext, checkSize, validateEvent, normalizeEvent, warning,
  rejection, mergeWarnings, ref, refCompare, eventCompare, speaker, ranges,
  snapshot, operation, operationError, control, isBlank: value => BLANK.test(text(value)) });
