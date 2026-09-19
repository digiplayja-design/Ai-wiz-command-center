'use strict';
// Pure state only. Calling a reducer does not authenticate a viewer.
const C = require('./contract.cjs');
const L = C.LIMITS;
const BUCKETS = 128;
function bucketFor(key) {
  let h = 2166136261;
  for (let i = 0; i < key.length; i += 1) h = Math.imul(h ^ key.charCodeAt(i), 16777619);
  return (h >>> 0) % BUCKETS;
}
function emptyStore() {
  const buckets = Array.from({ length: BUCKETS }, () => Object.freeze({}));
  return Object.freeze({ buckets: Object.freeze(buckets), count: 0,
    bucketBytes: C.bytes(buckets) });
}
function lookup(store, tuple) {
  const key = C.canonical(tuple);
  return store.buckets[bucketFor(key)][key];
}
function put(store, tuple, value) {
  const key = C.canonical(tuple), n = bucketFor(key), old = store.buckets[n];
  const next = Object.freeze({ ...old, [key]: C.freeze(value) });
  const buckets = store.buckets.slice();
  buckets[n] = next;
  return Object.freeze({ buckets: Object.freeze(buckets),
    count: store.count + (Object.hasOwn(old, key) ? 0 : 1),
    bucketBytes: store.bucketBytes - C.bytes(old) + C.bytes(next) });
}
function values(store) { return store.buckets.flatMap(bucket => Object.values(bucket)); }
function auxiliaryBytes(state) {
  // This equals CanonicalV1({context, auxiliary}) bytes; buckets are charged
  // at their full serialized length, not a digest or an estimated heap size.
  const maps = ['events', 'revisions', 'guards', 'unreflected'];
  const shell = { ...state.aux };
  let omittedBytes = 0;
  for (const name of maps) {
    const map = state.aux[name];
    shell[name] = { ...map, buckets: [] };
    omittedBytes += map.bucketBytes - 2;
  }
  return C.bytes({ context: state.context, auxiliary: shell }) + omittedBytes;
}
function immutable(context, retained, aux, queue = []) {
  return Object.freeze({ context, retained: Object.freeze(retained),
    aux: Object.freeze(aux), queue: Object.freeze(queue) });
}
function createTranscript(rawContext) {
  return immutable(C.context(rawContext), [], {
    events: emptyStore(), revisions: emptyStore(), guards: emptyStore(),
    unreflected: emptyStore(), accepted: 0, finalized: 0, serial: 0,
    rejected: 0, blocked: false, blockCode: null,
    gapRevision: null, gaps: Object.freeze([]), warnings: Object.freeze([]),
    request: null, notesRevisionFloor: null,
    // Charged capacity reserved for a bounded terminal diagnostic/counter.
    reserve: ' '.repeat(1024)
  });
}
function emergencyBlock(previous, delivery = false, code = 'LIMIT_EXCEEDED') {
  const w = C.warning(code, 'history', 'error');
  let rejected = previous.aux.rejected;
  if (delivery && rejected < Number.MAX_SAFE_INTEGER) rejected += 1;
  const warnings = C.mergeWarnings(previous.aux.warnings, [w], false);
  const next = immutable(previous.context, previous.retained, {
    ...previous.aux, blocked: true, blockCode: code, rejected,
    reserve: '', warnings
  }, previous.queue);
  // No identity/revision guard is erased. If a caller fabricated an invalid
  // internal state that has no reserve, reject it instead of hiding overflow.
  C.requireValue(auxiliaryBytes(next) <= L.auxiliary, 'LIMIT_EXCEEDED', 'history');
  return next;
}
function commitState(previous, retained, aux, queue = previous.queue, delivery = false) {
  try {
    C.uint(aux.accepted); C.uint(aux.finalized); C.uint(aux.serial); C.uint(aux.rejected);
    C.requireValue(aux.events.count <= L.eventHistory &&
      aux.revisions.count <= L.revisionHistory, 'LIMIT_EXCEEDED', 'history');
    const next = immutable(previous.context, retained, aux, queue);
    C.requireValue(auxiliaryBytes(next) <= L.auxiliary, 'LIMIT_EXCEEDED', 'history');
    return next;
  } catch (error) {
    if (!(error instanceof C.ContractError)) throw error;
    return emergencyBlock(previous, delivery);
  }
}
function outcome(state, disposition, diagnostics = []) {
  return Object.freeze({ state, disposition, diagnostics: Object.freeze(diagnostics) });
}
function boundedOutcome(previous, delivery, calculate) {
  // Include prospective warning/reconciliation work, not only commitState.
  // Failed updates discard their prospective maps and retain the last exact
  // state. The charged emergency reserve covers the terminal diagnostic.
  try { return calculate(); }
  catch (error) {
    if (!(error instanceof C.ContractError) || error.code !== 'LIMIT_EXCEEDED') throw error;
    return outcome(emergencyBlock(previous, delivery), 'blocked',
      [C.warning('LIMIT_EXCEEDED', 'history', 'error')]);
  }
}
function rejectDelivery(previous, diagnostic, block = false) {
  if (previous.aux.blocked) return outcome(previous, 'closed');
  let next;
  try {
    next = commitState(previous, previous.retained, { ...previous.aux,
      rejected: C.uint(previous.aux.rejected + 1),
      blocked: block, blockCode: block ? diagnostic.code : null,
      warnings: C.mergeWarnings(previous.aux.warnings, [diagnostic]) }, previous.queue, true);
  } catch (error) {
    if (!(error instanceof C.ContractError)) throw error;
    next = emergencyBlock(previous, true);
  }
  return outcome(next, next.aux.blocked ? 'blocked' : 'rejected', [diagnostic]);
}
function clearContext(state, nextTrustedContext) {
  // Caller must invalidate callbacks before replacement. No context is guessed.
  return createTranscript(nextTrustedContext);
}
function semantic(event) {
  // Complete context is stored once on the enclosing state. These stores are
  // inaccessible across a mismatched context; lookup is structurally
  // [state.context, tuple], never delimiter-concatenated identity strings.
  const { context, eventId, receivedAt, ...content } = event;
  return C.freeze(content);
}
function selectedManifestMatches(request, retained) {
  return request.manifest.every(ref => retained.some(e =>
    e.segmentId === ref.segmentId && e.segmentRevision === ref.segmentRevision && e.isFinal));
}
function reconcileRequest(aux, retained) {
  if (!aux.request || !aux.request.valid) return aux;
  if (!selectedManifestMatches(aux.request, retained)) {
    // Historical processing outcome; keep its exact count in the charged aux
    // ledger. It describes this invalidated request, not a future replacement.
    return { ...aux, request: C.freeze({ ...aux.request, valid: false }),
      warnings: C.mergeWarnings(aux.warnings,
        [C.warning('NOTES_INVALIDATED', 'notes')]) };
  }
  return aux;
}
function reduceTranscript(previous, validatedEvent) {
  if (previous.aux.blocked) return outcome(previous, 'closed');
  const event = C.validateEvent(validatedEvent, previous.context);
  return boundedOutcome(previous, true, () => reduceValidated(previous, event));
}
function reduceValidated(previous, event) {
  const content = semantic(event);
  const eventKey = [event.eventId], revisionKey = [event.segmentId, event.segmentRevision];
  const segmentKey = [event.segmentId];
  const oldEvent = lookup(previous.aux.events, eventKey);
  const oldRevision = lookup(previous.aux.revisions, revisionKey);
  const oldContent = oldEvent ? lookup(previous.aux.revisions, oldEvent) : undefined;
  if ((oldContent && C.canonical(oldContent) !== C.canonical(content)) ||
      (oldRevision && C.canonical(oldRevision) !== C.canonical(content))) {
    return rejectDelivery(previous, C.warning('PROTOCOL_CONFLICT', 'event', 'error'), true);
  }
  if (oldEvent) return outcome(previous, 'duplicate');
  let aux = { ...previous.aux,
    events: put(previous.aux.events, eventKey, revisionKey) };
  if (oldRevision) {
    const next = commitState(previous, previous.retained, aux, previous.queue, true);
    return outcome(next, next.aux.blocked ? 'blocked' : 'duplicate');
  }
  aux.revisions = put(aux.revisions, revisionKey, content);
  const guard = lookup(aux.guards, segmentKey);
  if (guard && event.sequence !== guard.sequence) {
    return rejectDelivery(previous, C.warning('PROTOCOL_CONFLICT', 'event', 'error'), true);
  }
  if (C.isBlank(event.text)) {
    const diagnostic = C.warning('EMPTY_TEXT', 'event', 'info');
    aux.warnings = C.mergeWarnings(aux.warnings, [diagnostic]);
    const next = commitState(previous, previous.retained, aux, previous.queue, true);
    return outcome(next, next.aux.blocked ? 'blocked' : 'empty', [diagnostic]);
  }
  if (guard && event.segmentRevision < guard.revision) {
    const next = commitState(previous, previous.retained, aux, previous.queue, true);
    return outcome(next, next.aux.blocked ? 'blocked' : 'stale');
  }
  if (guard && guard.final && !event.isFinal) {
    const diagnostic = C.warning('FINALITY_DOWNGRADE', 'event', 'error');
    try {
      aux.rejected = C.uint(aux.rejected + 1);
      aux.warnings = C.mergeWarnings(aux.warnings, [diagnostic]);
    } catch { return outcome(emergencyBlock(previous, true), 'blocked'); }
    const next = commitState(previous, previous.retained, aux, previous.queue, true);
    return outcome(next, next.aux.blocked ? 'blocked' : 'rejected', [diagnostic]);
  }
  try { aux.serial = C.uint(aux.serial + 1); }
  catch { return outcome(emergencyBlock(previous, true), 'blocked'); }
  aux.accepted += guard ? 0 : 1;
  aux.finalized += event.isFinal && (!guard || !guard.final) ? 1 : 0;
  aux.guards = put(aux.guards, segmentKey, {
    segmentId: event.segmentId, sequence: event.sequence,
    revision: event.segmentRevision, final: event.isFinal, serial: aux.serial
  });
  let retained = previous.retained.filter(e => e.segmentId !== event.segmentId);
  retained.push(event);
  retained.sort(C.eventCompare);
  let textBytes = retained.reduce((sum, e) => sum + Buffer.byteLength(e.text, 'utf8'), 0);
  while (retained.length > L.retainedCount || textBytes > L.retainedText) {
    const removed = retained.shift();
    textBytes -= Buffer.byteLength(removed.text, 'utf8');
  }
  aux = reconcileRequest(aux, retained);
  if (aux.request && aux.request.valid && event.isFinal &&
      !aux.request.manifest.some(ref => ref.segmentId === event.segmentId)) {
    aux.unreflected = put(aux.unreflected, segmentKey, {
      segmentId: event.segmentId, segmentRevision: event.segmentRevision
    });
  }
  const next = commitState(previous, retained, aux, previous.queue, true);
  return outcome(next, next.aux.blocked ? 'blocked' : guard ? 'replaced' : 'accepted');
}
function ingest(previous, raw, { intakeOpen = false, subscriptionCurrent = false } = {}) {
  // Both booleans are caller assertions from the trusted C2 boundary, NOT auth.
  if (!intakeOpen || !subscriptionCurrent || previous.aux.blocked) return outcome(previous, 'closed');
  const normalized = C.normalizeEvent(raw, previous.context);
  return normalized.ok ? reduceTranscript(previous, normalized.event) :
    rejectDelivery(previous, normalized.rejection);
}
function enqueue(previous, raw, gate) {
  if (!gate || !gate.intakeOpen || !gate.subscriptionCurrent || previous.aux.blocked)
    return outcome(previous, 'closed');
  const normalized = C.normalizeEvent(raw, previous.context);
  if (!normalized.ok) return rejectDelivery(previous, normalized.rejection);
  const queue = [...previous.queue, normalized.event];
  if (queue.length > L.queueCount || C.bytes(queue) > L.queueBytes)
    return rejectDelivery(previous, C.warning('LIMIT_EXCEEDED', 'queue', 'error'), true);
  return outcome(immutable(previous.context, previous.retained, previous.aux, queue), 'queued');
}
function drainOne(previous, gate) {
  if (!gate || !gate.intakeOpen || !gate.subscriptionCurrent || previous.aux.blocked)
    return outcome(previous, 'closed');
  if (!previous.queue.length) return outcome(previous, 'emptyQueue');
  const [event, ...queue] = previous.queue;
  return reduceTranscript(immutable(previous.context, previous.retained, previous.aux, queue), event);
}
function applyGaps(previous, rawSignal) {
  if (previous.aux.blocked) return outcome(previous, 'closed');
  let signal;
  try {
    signal = C.control(rawSignal, 'signal', previous.context);
    C.requireValue(signal.kind === 'captureGaps', 'INVALID_INPUT', 'control');
    C.requireValue(C.sameContext(signal.context, previous.context), 'CONTEXT_MISMATCH', 'context');
  } catch (error) {
    return outcome(emergencyBlock(previous, false, C.rejection(error).code), 'blocked');
  }
  const old = previous.aux.gapRevision;
  if (old !== null && signal.revision < old) return outcome(previous, 'stale');
  if (old !== null && signal.revision === old) {
    if (C.canonical(signal.gaps) === C.canonical(previous.aux.gaps)) return outcome(previous, 'duplicate');
    return outcome(emergencyBlock(previous, false, 'PROTOCOL_CONFLICT'), 'blocked');
  }
  if (!previous.aux.gaps.every(g => signal.gaps.some(n =>
      n.startMs <= g.startMs && n.endMs >= g.endMs)))
    return outcome(emergencyBlock(previous, false, 'PROTOCOL_CONFLICT'), 'blocked');
  return boundedOutcome(previous, false, () => {
    const aux = { ...previous.aux, gapRevision: signal.revision, gaps: signal.gaps,
      warnings: C.mergeWarnings(previous.aux.warnings,
        signal.gaps.length ? [C.warning('CAPTURE_GAP', 'coverage')] : []) };
    const next = commitState(previous, previous.retained, aux);
    return outcome(next, next.aux.blocked ? 'blocked' : 'accepted');
  });
}
function observedRange(events) {
  if (!events.length || events.some(e => !Object.hasOwn(e, 'endMs'))) return null;
  const startMs = Math.min(...events.map(e => e.startMs));
  const endMs = Math.max(...events.map(e => e.endMs));
  return endMs > startMs ? C.freeze({ startMs, endMs }) : null;
}
function coverage(state, scope = 'transcriptWindow', selected = state.retained) {
  C.oneOf(scope, ['transcriptWindow', 'notesWindow'], 'coverage');
  const omitted = scope === 'transcriptWindow' ? state.aux.accepted - state.retained.length :
    state.aux.finalized - selected.length;
  const provisional = state.aux.accepted - state.aux.finalized;
  const reasons = [];
  if (omitted) reasons.push('WINDOW_TRUNCATED');
  if (provisional) reasons.push('PROVISIONAL_EXCLUDED');
  if (state.aux.rejected) reasons.push('INVALID_INPUT');
  if (state.aux.gaps.length) reasons.push('CAPTURE_GAP');
  if (state.aux.blocked) reasons.push(state.aux.blockCode || 'LIMIT_EXCEEDED');
  const partial = reasons.length > 0;
  if (!partial) reasons.push('COVERAGE_UNKNOWN');
  return C.freeze({ scope, completeness: partial ? 'partial' : 'unknown',
    observedRange: observedRange(selected), knownCaptureGaps: state.aux.gaps,
    omittedSegments: C.uint(omitted), rejectedEvents: state.aux.rejected,
    provisionalSegments: provisional, ingestionBlocked: state.aux.blocked,
    reasons: [...new Set(reasons)].sort(C.scalarCompare) });
}
function selectFinalized(state) {
  const ordered = state.retained.filter(e => e.isFinal);
  let bytes = 0, start = ordered.length;
  while (start > 0 && ordered.length - start < L.notesCount) {
    const nextBytes = bytes + Buffer.byteLength(ordered[start - 1].text, 'utf8');
    if (nextBytes > L.notesText) break;
    bytes = nextBytes; start -= 1;
  }
  return Object.freeze(ordered.slice(start));
}
function warningsForNewRequest(state) {
  // Project, never delete/reset the historical aux ledger. The new request's
  // stored copy is charged by auxiliaryBytes along with the original ledger.
  // Existing invalidated requests remain invalid; only fresh preparation uses
  // this projection. Other transcript/coverage diagnostics remain visible.
  return C.freeze(state.aux.warnings.filter(w => w.code !== 'NOTES_INVALIDATED'));
}
function setRequest(state, request) {
  C.requireValue(!state.aux.blocked, 'LIMIT_EXCEEDED', 'history');
  if (request !== null) {
    C.requireValue(state.aux.notesRevisionFloor === null ||
      request.notesRevision > state.aux.notesRevisionFloor, 'INVALID_INPUT', 'notes');
  }
  return commitState(state, state.retained, { ...state.aux,
    request: C.freeze(request), unreflected: emptyStore(),
    notesRevisionFloor: request === null ? state.aux.notesRevisionFloor : request.notesRevision });
}
function unreflected(state) {
  return C.freeze(values(state.aux.unreflected).slice().sort(C.refCompare));
}
module.exports = Object.freeze({ createTranscript, clearContext, reduceTranscript,
  ingest, enqueue, drainOne, applyGaps, coverage, observedRange, selectFinalized,
  setRequest, unreflected, selectedManifestMatches, auxiliaryBytes,
  warningsForNewRequest });
