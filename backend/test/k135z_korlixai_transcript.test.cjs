'use strict';
// Static-review draft. This file has NOT been run.
const test = require('node:test');
const assert = require('node:assert/strict');
const C = require('../k135z_copilot_notes/contract.cjs');
const T = require('../k135z_copilot_notes/transcript.cjs');
const F = require('../../docs/k135z/korlixai/fixtures/contract_v1.json');
const gate = Object.freeze({ intakeOpen: true, subscriptionCurrent: true });
const copy = value => structuredClone(value);
const event = (n, changes = {}) => ({ ...copy(F.events[0]),
  eventId: 'e' + n, segmentId: 's' + n, sequence: n, startMs: n,
  text: 'x', ...changes });
function feed(events) {
  let state = T.createTranscript(F.context);
  for (const e of events) state = T.ingest(state, e, gate).state;
  return state;
}
function add(state, raw) { return T.ingest(state, raw, gate); }
function gaps(revision, intervals) {
  return { kind: 'captureGaps', context: F.context, revision,
    gaps: intervals.map(([startMs, endMs]) => ({ startMs, endMs })) };
}
test('TR-01 canonical frozen UTF-8 byte examples', () => {
  for (const x of F.canonicalCases) {
    assert.equal(Buffer.from(C.canonical(x.input), 'utf8').toString('hex'), x.hex);
  }
});
test('TR-02 UTC normalization is calendar-validated without rollover', () => {
  assert.equal(C.utc('2026-09-12T13:00:10Z'), '2026-09-12T13:00:10.000Z');
  for (const bad of ['2026-02-29T00:00:00Z', '0000-01-01T00:00:00Z',
    '2026-09-12T24:00:00Z', '2026-09-12T13:00:60Z', '2026-09-12T13:00:10+00:00'])
    assert.throws(() => C.utc(bad));
  assert.equal(C.utc('2024-02-29T00:00:00Z'), '2024-02-29T00:00:00.000Z');
});
test('TR-03 UInt rejects coercion, negative zero and unsafe numbers', () => {
  for (const bad of ['1', -0, -1, 1.5, Infinity, NaN, 9007199254740992])
    assert.throws(() => C.uint(bad));
  assert.equal(C.uint(9007199254740991), 9007199254740991);
});
test('TR-04 unpaired surrogates, unknown fields and accessors reject', () => {
  assert.throws(() => C.text('\ud800'));
  assert.throws(() => C.context({ ...F.context, extra: 1 }));
  let invoked = false;
  const raw = copy(F.events[0]);
  Object.defineProperty(raw, 'text', { enumerable: true, get() { invoked = true; return 'x'; } });
  assert.equal(C.normalizeEvent(raw, F.context).ok, false);
  assert.equal(invoked, false);
});
test('TR-05 optional omission, blank and null are distinct', () => {
  const missing = event(1); delete missing.speakerName;
  assert.equal(C.speaker(C.validateEvent(missing, F.context)), 'Unknown speaker');
  const blank = { ...missing, speakerName: '\u0085' };
  assert.equal(C.speaker(C.validateEvent(blank, F.context)), 'Unknown speaker');
  assert.notEqual(C.canonical(missing), C.canonical(blank));
  assert.equal(C.normalizeEvent({ ...missing, speakerName: null }, F.context).ok, false);
  assert.equal(C.normalizeEvent({ ...missing, endMs: null }, F.context).ok, false);
});
test('TR-06 six finalized fixture events keep exact source and unknown coverage', () => {
  const state = feed(F.events.slice().reverse());
  assert.deepEqual(state.retained.map(e => e.segmentId), ['S1', 'S2', 'S3', 'S4', 'S5', 'S6']);
  assert.equal(state.retained[2].text, F.events[2].text);
  assert.deepEqual(T.coverage(state), F.expected.transcriptCoverage);
});
test('TR-07 receipt-only redelivery does not advance state', () => {
  const state = feed([event(1)]);
  const result = add(state, event(1, { receivedAt: '2026-09-12T15:00:00Z' }));
  assert.equal(result.disposition, 'duplicate'); assert.equal(result.state, state);
});
test('TR-08 new event alias is a transcript no-op with bounded history', () => {
  const state = feed([event(1)]);
  const next = add(state, event(1, { eventId: 'alias' })).state;
  assert.deepEqual(next.retained, state.retained);
  assert.equal(next.aux.events.count, 2); assert.equal(next.aux.revisions.count, 1);
  assert.equal(next.aux.rejected, 0);
});
test('TR-09 conflicts take precedence over stale revision', () => {
  let state = feed([event(1), event(1, { eventId: 'new', segmentRevision: 2, text: 'corrected' })]);
  state = add(state, event(1, { text: 'inconsistent old text' })).state;
  assert.equal(state.aux.blocked, true); assert.equal(state.aux.rejected, 1);
  assert.equal(state.retained[0].text, 'corrected');
});
test('TR-10 final content survives provisional downgrade and empty correction', () => {
  const state = feed([event(1)]);
  const downgrade = add(state, event(1, { eventId: 'p', segmentRevision: 2, isFinal: false }));
  assert.equal(downgrade.disposition, 'rejected'); assert.equal(downgrade.state.aux.rejected, 1);
  const empty = add(state, event(1, { eventId: 'z', segmentRevision: 2, text: '\t  ' }));
  assert.equal(empty.disposition, 'empty'); assert.equal(empty.state.retained[0].segmentRevision, 1);
  assert.equal(empty.state.aux.rejected, 0);
});
test('TR-11 corrections preserve sequence and pure caller-owned collections', () => {
  const input = event(1); const state = feed([input]);
  const next = add(state, event(1, { eventId: 'fix', segmentRevision: 2, text: 'corrected' })).state;
  assert.equal(state.retained[0].text, 'x'); assert.equal(input.text, 'x');
  assert.equal(next.retained[0].text, 'corrected'); assert.equal(next.aux.accepted, 1);
  assert.equal(add(next, event(1, { eventId: 'seq', segmentRevision: 3, sequence: 99 })).state.aux.blocked, true);
});
test('TR-12 foreign/malformed examined deliveries count once without leaking text', () => {
  let state = feed([]);
  const foreign = event(1, { context: { ...F.context, tenantId: 'foreign' }, text: 'PRIVATE FOREIGN TEXT' });
  const result = add(state, foreign);
  assert.equal(result.state.aux.rejected, 1); assert.equal(result.state.retained.length, 0);
  assert.equal(JSON.stringify(result).includes('PRIVATE FOREIGN TEXT'), false);
  state = add(result.state, { bad: true }).state;
  state = add(state, { bad: true }).state;
  assert.equal(state.aux.rejected, 3); assert.equal(state.aux.events.count, 0);
});
test('TR-13 closed/stale subscription callbacks are not inspected or counted', () => {
  const state = feed([]);
  const malformed = { text: 'unexamined' };
  assert.equal(T.ingest(state, malformed, { intakeOpen: false, subscriptionCurrent: true }).state, state);
  assert.equal(T.ingest(state, malformed, { intakeOpen: true, subscriptionCurrent: false }).state, state);
});
test('TR-14 8191/8192/8193 original text bytes and serialized envelope bound', () => {
  assert.equal(C.normalizeEvent(event(1, { text: 'x'.repeat(8191) }), F.context).ok, true);
  assert.equal(C.normalizeEvent(event(1, { text: 'x'.repeat(8192) }), F.context).ok, true);
  assert.equal(C.normalizeEvent(event(1, { text: 'x'.repeat(8193) }), F.context).ok, false);
  // Control escapes cost six canonical bytes while one source newline is one byte.
  assert.equal(C.normalizeEvent(event(1, { text: '\n'.repeat(8192) }), F.context).ok, false);
  const base = event(1, { speakerName: '' });
  const overhead = C.bytes(base);
  for (const delta of [-1, 0, 1]) {
    const raw = { ...base, speakerName: 'x'.repeat(32768 - overhead + delta) };
    assert.equal(C.bytes(raw), 32768 + delta);
    assert.equal(C.normalizeEvent(raw, F.context).ok, delta <= 0);
  }
});
test('TR-15 retained count 1999/2000/2001 and replay after eviction', () => {
  let state = feed(Array.from({ length: 1999 }, (_, i) => event(i)));
  assert.equal(state.retained.length, 1999);
  state = add(state, event(1999)).state; assert.equal(state.retained.length, 2000);
  state = add(state, event(2000)).state;
  assert.equal(state.retained.length, 2000); assert.equal(T.coverage(state).omittedSegments, 1);
  const replay = add(state, event(0));
  assert.equal(replay.disposition, 'duplicate'); assert.equal(replay.state, state);
  const downgrade = add(state, event(0, { eventId: 'down', segmentRevision: 2, isFinal: false }));
  assert.equal(downgrade.state.aux.rejected, 1);
  assert.equal(downgrade.state.retained.some(e => e.segmentId === 's0'), false);
});
test('TR-16 stale revision and final correction after eviction retain safeguards', () => {
  let state = feed([event(0, { segmentRevision: 2 })]);
  for (let i = 1; i <= 2000; i += 1) state = add(state, event(i)).state;
  const stale = add(state, event(0, { eventId: 'old', segmentRevision: 1 }));
  assert.equal(stale.disposition, 'stale'); assert.equal(stale.state.aux.rejected, 0);
  const corrected = add(stale.state, event(0, { eventId: 'fixed', segmentRevision: 3, text: 'fixed' })).state;
  assert.equal(corrected.aux.accepted, 2001);
  assert.equal(T.coverage(corrected).omittedSegments, 1);
});
test('TR-17 retained original-text budget at one below/exact/overflow', () => {
  const inputs = Array.from({ length: 512 }, (_, i) => event(i, { text: 'x'.repeat(i === 511 ? 8191 : 8192) }));
  let state = feed(inputs);
  const total = s => s.retained.reduce((n, e) => n + Buffer.byteLength(e.text), 0);
  assert.equal(total(state), 4194303);
  state = add(state, event(511, { eventId: 'full', segmentRevision: 2, text: 'x'.repeat(8192) })).state;
  assert.equal(total(state), 4194304);
  state = add(state, event(512)).state;
  assert.ok(total(state) <= 4194304); assert.equal(T.coverage(state).omittedSegments, 1);
});
test('TR-18 queue count 255/256/257 blocks without draining or dropping', () => {
  let state = feed([]);
  for (let i = 0; i < 255; i += 1) state = T.enqueue(state, event(i), gate).state;
  assert.equal(state.queue.length, 255);
  state = T.enqueue(state, event(255), gate).state; assert.equal(state.queue.length, 256);
  const full = T.enqueue(state, event(256), gate);
  assert.equal(full.state.aux.blocked, true); assert.equal(full.state.queue.length, 256);
  assert.equal(full.state.aux.rejected, 1);
});
test('TR-19 queue serialized bytes count envelopes and separators', () => {
  let state = feed([]), n = 0;
  while (C.bytes(state.queue) < 500000 && n < 200) {
    state = T.enqueue(state, event(n++, { text: 'x'.repeat(8192) }), gate).state;
  }
  const base = event(n, { text: '', speakerName: '' });
  const overhead = C.bytes([...state.queue, base]);
  for (const delta of [-1, 0, 1]) {
    const raw = { ...base, speakerName: 'y'.repeat(524288 - overhead + delta) };
    // The last individual envelope must still be within 32 KiB.
    assert.ok(C.bytes(raw) <= 32768);
    const out = T.enqueue(state, raw, gate);
    assert.equal(out.state.aux.blocked, delta > 0);
    if (delta <= 0) assert.equal(C.bytes(out.state.queue), 524288 + delta);
  }
});
test('TR-20 event-history identity ceiling 19999/20000/20001', () => {
  let state = feed([event(0)]);
  for (let i = 1; i < 19999; i += 1) state = add(state, event(0, { eventId: 'alias-' + i })).state;
  assert.equal(state.aux.events.count, 19999); assert.equal(state.aux.blocked, false);
  state = add(state, event(0, { eventId: 'alias-19999' })).state;
  assert.equal(state.aux.events.count, 20000);
  const next = add(state, event(0, { eventId: 'alias-20000' })).state;
  assert.equal(next.aux.blocked, true); assert.equal(next.aux.events.count, 20000);
});
test('TR-21 segment/revision and event ceilings hold for 20000 revisions', () => {
  let state = feed([]);
  for (let i = 0; i < 19999; i += 1)
    state = add(state, event(0, { eventId: 'r' + i, segmentRevision: i })).state;
  assert.equal(state.aux.revisions.count, 19999); assert.equal(state.aux.blocked, false);
  state = add(state, event(0, { eventId: 'r19999', segmentRevision: 19999 })).state;
  assert.equal(state.aux.revisions.count, 20000); assert.equal(state.aux.blocked, false);
  const next = add(state, event(0, { eventId: 'r20000', segmentRevision: 20000 })).state;
  assert.equal(next.aux.blocked, true); assert.equal(next.aux.revisions.count, 20000);
  assert.equal(next.retained[0].segmentRevision, 19999);
});
test('TR-22 combined auxiliary bound includes retained guards and diagnostics', () => {
  let state = feed([]), previous = state;
  for (let i = 0; i < 2000 && !state.aux.blocked; i += 1) {
    previous = state;
    state = add(state, event(i, { text: 'x'.repeat(8192) })).state;
  }
  assert.equal(state.aux.blocked, true);
  assert.ok(T.auxiliaryBytes(state) <= 8388608);
  assert.equal(state.aux.events.count, previous.aux.events.count);
  assert.equal(state.aux.guards.count, previous.aux.guards.count);
  assert.equal(state.aux.rejected, previous.aux.rejected + 1);
  assert.equal(T.coverage(state).ingestionBlocked, true);
});
test('TR-23 cumulative capture-gap normalization, conflict and no retraction', () => {
  const first = T.applyGaps(feed([]), gaps(1, [[10, 20], [20, 30]])).state;
  assert.deepEqual(first.aux.gaps, [{ startMs: 10, endMs: 30 }]);
  assert.equal(T.applyGaps(first, gaps(1, [[10, 30]])).disposition, 'duplicate');
  assert.equal(T.applyGaps(first, gaps(0, [])).disposition, 'stale');
  assert.equal(T.applyGaps(first, gaps(1, [[10, 31]])).state.aux.blocked, true);
  assert.equal(T.applyGaps(first, gaps(2, [[10, 31]])).state.aux.blocked, false);
  assert.equal(T.applyGaps(first, gaps(2, [[11, 30]])).state.aux.blocked, true);
  assert.equal(T.applyGaps(first, gaps(2, [[1, 1]])).state.aux.rejected, 0);
});
test('TR-24 observedRange does not invent missing endpoints or continuity', () => {
  assert.equal(T.observedRange([event(1)]), null);
  assert.equal(T.observedRange([event(1, { endMs: 1 })]), null);
  assert.deepEqual(T.observedRange([event(1, { endMs: 2 }), event(10, { endMs: 11 })]),
    { startMs: 1, endMs: 11 });
});
test('TR-25 controls validate retained enums and never allow speaking', () => {
  const snap = { schemaVersion: 1, context: F.context, revision: 1,
    state: 'stopped', hostAuthorized: true, listeningAuthorized: false,
    activeSeconds: 0, capabilities: { canSpeak: false } };
  assert.equal(C.snapshot(snap).state, 'stopped');
  assert.throws(() => C.snapshot({ ...snap, state: 'ended' }));
  assert.throws(() => C.snapshot({ ...snap, capabilities: { canSpeak: true } }));
  assert.throws(() => C.control({ kind: 'meetingEnded', snapshot: { ...snap, state: 'listening' } }, 'signal', F.context));
});
test('TR-26 active gap/control rejection blocks without a transcript rejection count', () => {
  const state = feed([]);
  const malformed = T.applyGaps(state, { kind: 'captureGaps', context: F.context });
  assert.equal(malformed.state.aux.blocked, true);
  assert.equal(malformed.state.aux.rejected, 0);
  const oversized = gaps(1, Array.from({ length: 2000 }, (_, i) => [i * 2, i * 2 + 1]));
  assert.equal(T.applyGaps(state, oversized).state.aux.blocked, true);
});
test('TR-27 warning projection does not increase occurrences and contexts reset', () => {
  const state = add(feed([]), {}).state;
  const first = C.canonical(state.aux.warnings);
  T.coverage(state); T.coverage(state);
  assert.equal(C.canonical(state.aux.warnings), first);
  const next = T.clearContext(state, { ...F.context, sessionId: 'new-session', generation: 2 });
  assert.equal(next.aux.rejected, 0); assert.equal(next.aux.events.count, 0);
});

test('TR-28 session/control envelope at 32767/32768/32769 bytes', () => {
  const base = { schemaVersion: 1,
    operation: { requestId: 'stop-1', localEpoch: 1, operationNumber: 1 },
    action: 'stop', outcome: { kind: 'failed', error: {
      code: 'CONFLICT', message: 'x', remoteOutcome: 'unknown', automaticRetry: false } } };
  const size = C.bytes(base);
  for (const delta of [-1, 0, 1]) {
    const raw = copy(base);
    raw.outcome.error.message = 'x'.repeat(1 + 32768 - size + delta);
    assert.equal(C.bytes(raw), 32768 + delta);
    if (delta <= 0) assert.equal(C.control(raw, 'reply').outcome.error.remoteOutcome, 'unknown');
    else assert.throws(() => C.control(raw, 'reply'));
  }
});
test('TR-29 actual combined auxiliary-state one below/exact/one above', () => {
  let state = feed([]), n = 0;
  while (T.auxiliaryBytes(state) < 8388608 - 20000 && n < 1500) {
    state = add(state, event(n++, { text: 'x'.repeat(8192) })).state;
    assert.equal(state.aux.blocked, false);
  }
  assert.ok(n < 1500);
  const raw = event(n, { speakerName: 'x' });
  const probe = add(state, raw).state;
  assert.equal(probe.aux.blocked, false);
  const headroom = 8388608 - T.auxiliaryBytes(probe);
  for (const delta of [-1, 0, 1]) {
    const input = { ...raw, speakerName: 'x'.repeat(1 + headroom + delta) };
    assert.ok(C.bytes(input) <= 32768);
    const result = add(state, input).state;
    assert.equal(result.aux.blocked, delta > 0);
    if (delta <= 0) assert.equal(T.auxiliaryBytes(result), 8388608 + delta);
    else assert.equal(result.aux.events.count, state.aux.events.count);
  }
});
test('TR-30 counter overflow preserves last exact value and blocks intake', () => {
  const empty = feed([]);
  // Explicitly seeded numeric-state fixture; not billions of claimed deliveries.
  const seeded = Object.freeze({ ...empty, aux: Object.freeze({ ...empty.aux,
    rejected: Number.MAX_SAFE_INTEGER - 1 }) });
  const exact = add(seeded, {}).state;
  assert.equal(exact.aux.rejected, Number.MAX_SAFE_INTEGER);
  const blocked = add(exact, {}).state;
  assert.equal(blocked.aux.blocked, true);
  assert.equal(blocked.aux.rejected, Number.MAX_SAFE_INTEGER);
});

// R2: Explicitly seeded numeric fixtures. No large event history is simulated.
function seedWarningCount(state, code, field, severity, occurrences) {
  const warnings = state.aux.warnings.slice();
  const at = warnings.findIndex(w =>
    w.code === code && w.field === field && w.severity === severity);
  const seededWarning = C.freeze({ ...C.warning(code, field, severity), occurrences });
  if (at < 0) warnings.push(seededWarning);
  else warnings[at] = seededWarning;
  const seeded = C.freeze({ ...state, aux: { ...state.aux, warnings } });
  assert.equal(T.auxiliaryBytes(seeded),
    C.bytes({ context: seeded.context, auxiliary: seeded.aux }));
  assert.ok(T.auxiliaryBytes(seeded) <= C.LIMITS.auxiliary);
  return seeded;
}
function warningCount(state, code, field, severity) {
  return state.aux.warnings.find(w =>
    w.code === code && w.field === field && w.severity === severity).occurrences;
}
function assertBoundedRollback(previous, next, delivery) {
  assert.equal(next.aux.blocked, true);
  assert.equal(next.aux.blockCode, 'LIMIT_EXCEEDED');
  assert.equal(next.retained, previous.retained);
  assert.equal(next.queue, previous.queue);
  for (const key of ['events', 'revisions', 'guards', 'unreflected', 'request', 'gaps'])
    assert.equal(next.aux[key], previous.aux[key]);
  for (const key of ['accepted', 'finalized', 'serial', 'gapRevision', 'notesRevisionFloor'])
    assert.equal(next.aux[key], previous.aux[key]);
  assert.equal(next.aux.rejected, previous.aux.rejected + (delivery ? 1 : 0));
  for (const w of previous.aux.warnings) {
    const kept = next.aux.warnings.find(x =>
      x.code === w.code && x.field === w.field && x.severity === w.severity);
    assert.deepEqual(kept, w);
  }
  assert.equal(T.auxiliaryBytes(next),
    C.bytes({ context: next.context, auxiliary: next.aux }));
  assert.ok(T.auxiliaryBytes(next) <= C.LIMITS.auxiliary);
  assert.equal(T.coverage(next).ingestionBlocked, true);
  assert.equal(T.coverage(next).completeness, 'partial');
}
test('TR-31 seeded warning count reaches UInt maximum then reports typed capacity failure', () => {
  const w = C.warning('EMPTY_TEXT', 'event', 'info');
  const seeded = C.freeze([{ ...w, occurrences: Number.MAX_SAFE_INTEGER - 1 }]);
  const exact = C.mergeWarnings(seeded, [w]);
  assert.equal(exact[0].occurrences, Number.MAX_SAFE_INTEGER);
  assert.equal(seeded[0].occurrences, Number.MAX_SAFE_INTEGER - 1);
  assert.throws(() => C.mergeWarnings(exact, [w]), error =>
    error instanceof C.ContractError && error.code === 'LIMIT_EXCEEDED' &&
    error.field === 'history');
  assert.equal(exact[0].occurrences, Number.MAX_SAFE_INTEGER);
  assert.deepEqual(C.mergeWarnings(exact, [w], false), exact);
});
test('TR-32 seeded empty-event warning overflow blocks without committing prospective histories', () => {
  const seeded = seedWarningCount(feed([event(1)]),
    'EMPTY_TEXT', 'event', 'info', Number.MAX_SAFE_INTEGER - 1);
  const exact = add(seeded, event(2, { text: ' \t' }));
  assert.equal(exact.disposition, 'empty');
  assert.equal(exact.state.aux.blocked, false);
  assert.equal(warningCount(exact.state, 'EMPTY_TEXT', 'event', 'info'), Number.MAX_SAFE_INTEGER);
  assert.equal(exact.state.aux.rejected, 0);
  assert.equal(exact.state.aux.events.count, seeded.aux.events.count + 1);
  let stopped;
  assert.doesNotThrow(() => { stopped = add(exact.state, event(3, { text: '  ' })); });
  assert.equal(stopped.disposition, 'blocked');
  assertBoundedRollback(exact.state, stopped.state, true);
  assert.equal(stopped.diagnostics[0].code, 'LIMIT_EXCEEDED');
  assert.equal(add(stopped.state, {}).state, stopped.state);
});
test('TR-33 seeded accepted-gap warning overflow keeps prior gap snapshot and rejection total', () => {
  const first = T.applyGaps(feed([event(1)]), gaps(1, [[10, 20]])).state;
  const seeded = seedWarningCount(first,
    'CAPTURE_GAP', 'coverage', 'warning', Number.MAX_SAFE_INTEGER - 1);
  const exact = T.applyGaps(seeded, gaps(2, [[10, 30]]));
  assert.equal(exact.disposition, 'accepted');
  assert.equal(warningCount(exact.state, 'CAPTURE_GAP', 'coverage', 'warning'), Number.MAX_SAFE_INTEGER);
  assert.equal(exact.state.aux.gapRevision, 2);
  assert.deepEqual(exact.state.aux.gaps, [{ startMs: 10, endMs: 30 }]);
  let stopped;
  assert.doesNotThrow(() => { stopped = T.applyGaps(exact.state, gaps(3, [[10, 40]])); });
  assert.equal(stopped.disposition, 'blocked');
  assertBoundedRollback(exact.state, stopped.state, false);
  assert.equal(stopped.state.aux.rejected, 0);
});
test('TR-34 seeded rejected-delivery warning overflow counts inspected delivery once', () => {
  const seeded = seedWarningCount(feed([event(1)]),
    'INVALID_INPUT', 'event', 'error', Number.MAX_SAFE_INTEGER - 1);
  const exact = add(seeded, {});
  assert.equal(exact.disposition, 'rejected');
  assert.equal(exact.state.aux.rejected, 1);
  assert.equal(warningCount(exact.state, 'INVALID_INPUT', 'event', 'error'), Number.MAX_SAFE_INTEGER);
  let stopped;
  assert.doesNotThrow(() => { stopped = add(exact.state, {}); });
  assertBoundedRollback(exact.state, stopped.state, true);
  assert.equal(stopped.state.aux.rejected, 2);
  assert.equal(add(stopped.state, {}).state.aux.rejected, 2);
});
test('TR-35 seeded finality-warning overflow preserves accepted final revision and guards', () => {
  const seeded = seedWarningCount(feed([event(1)]),
    'FINALITY_DOWNGRADE', 'event', 'error', Number.MAX_SAFE_INTEGER - 1);
  const exact = add(seeded, event(1, { eventId: 'provisional-2',
    segmentRevision: 2, isFinal: false }));
  assert.equal(exact.disposition, 'rejected');
  assert.equal(warningCount(exact.state, 'FINALITY_DOWNGRADE', 'event', 'error'), Number.MAX_SAFE_INTEGER);
  assert.equal(exact.state.retained[0].segmentRevision, 1);
  assert.equal(exact.state.retained[0].isFinal, true);
  let stopped;
  assert.doesNotThrow(() => { stopped = add(exact.state, event(1,
    { eventId: 'provisional-3', segmentRevision: 3, isFinal: false })); });
  assertBoundedRollback(exact.state, stopped.state, true);
  assert.equal(stopped.state.retained[0].isFinal, true);
});
test('TR-36 seeded full warning counter does not turn control failure into transcript rejection', () => {
  const first = T.applyGaps(feed([event(1)]), gaps(1, [[10, 20]])).state;
  const seeded = seedWarningCount(first,
    'CAPTURE_GAP', 'coverage', 'warning', Number.MAX_SAFE_INTEGER);
  let stopped;
  assert.doesNotThrow(() => { stopped = T.applyGaps(seeded,
    { kind: 'captureGaps', context: F.context }); });
  assert.equal(stopped.disposition, 'blocked');
  assert.equal(stopped.state.aux.rejected, seeded.aux.rejected);
  assert.equal(warningCount(stopped.state, 'CAPTURE_GAP', 'coverage', 'warning'), Number.MAX_SAFE_INTEGER);
  assert.equal(stopped.state.aux.events, seeded.aux.events);
  assert.equal(stopped.state.aux.revisions, seeded.aux.revisions);
  assert.equal(stopped.state.aux.guards, seeded.aux.guards);
  assert.equal(stopped.state.aux.gaps, seeded.aux.gaps);
  assert.equal(stopped.state.aux.gapRevision, seeded.aux.gapRevision);
  assert.ok(T.auxiliaryBytes(stopped.state) <= C.LIMITS.auxiliary);
  assert.equal(T.auxiliaryBytes(stopped.state),
    C.bytes({ context: stopped.state.context, auxiliary: stopped.state.aux }));
});
