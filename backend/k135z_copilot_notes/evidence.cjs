'use strict';
const C = require('./contract.cjs');
const T = require('./transcript.cjs');
const KEYS = Object.keys(C.CATEGORIES);
function validateCoverage(raw) {
  C.object(raw, ['scope', 'completeness', 'observedRange', 'knownCaptureGaps',
    'omittedSegments', 'rejectedEvents', 'provisionalSegments', 'ingestionBlocked',
    'reasons'], [], 'coverage');
  C.oneOf(raw.scope, ['transcriptWindow', 'notesWindow'], 'coverage');
  C.oneOf(raw.completeness, ['unknown', 'partial'], 'coverage');
  if (raw.observedRange !== null) C.ranges([raw.observedRange]);
  const gaps = C.ranges(raw.knownCaptureGaps);
  C.requireValue(C.canonical(gaps) === C.canonical(raw.knownCaptureGaps), 'INVALID_INPUT', 'coverage');
  ['omittedSegments', 'rejectedEvents', 'provisionalSegments'].forEach(k => C.uint(raw[k], 'coverage'));
  C.bool(raw.ingestionBlocked, 'coverage');
  C.array(raw.reasons, 'coverage').forEach(code => C.oneOf(code, Object.keys(C.MESSAGES), 'coverage'));
  C.requireValue(new Set(raw.reasons).size === raw.reasons.length, 'INVALID_INPUT', 'coverage');
  const partial = raw.omittedSegments > 0 || raw.rejectedEvents > 0 ||
    raw.provisionalSegments > 0 || raw.knownCaptureGaps.length > 0 || raw.ingestionBlocked;
  C.requireValue(raw.completeness === (partial ? 'partial' : 'unknown'), 'INVALID_INPUT', 'coverage');
  return C.freeze(C.clone(raw));
}
function validateWarnings(raw) {
  const keys = new Set();
  const out = C.array(raw, 'notes').map(w => {
    C.object(w, ['code', 'severity', 'field', 'eventId', 'segment', 'message', 'occurrences'], [], 'notes');
    C.oneOf(w.code, Object.keys(C.MESSAGES), 'notes');
    C.oneOf(w.severity, ['info', 'warning', 'error'], 'notes');
    C.uint(w.occurrences, 'notes');
    C.requireValue(w.occurrences >= 1 && w.message === C.MESSAGES[w.code], 'INVALID_INPUT', 'notes');
    C.nullable(w.eventId, C.id); C.nullable(w.segment, C.ref);
    if (w.field !== null) C.warning(w.code, w.field, w.severity);
    const key = C.canonical([w.code, w.field, w.severity]);
    C.requireValue(!keys.has(key), 'INVALID_INPUT', 'notes'); keys.add(key);
    return C.freeze(C.clone(w));
  });
  return C.freeze(out);
}
function currentIndex(rawEvents, ctx) {
  C.array(rawEvents, 'evidence');
  C.requireValue(rawEvents.length <= C.LIMITS.retainedCount, 'LIMIT_EXCEEDED', 'evidence');
  let total = 0;
  const map = new Map();
  for (const raw of rawEvents) {
    const e = C.validateEvent(raw, ctx);
    total += Buffer.byteLength(e.text, 'utf8');
    C.requireValue(!map.has(e.segmentId) && !C.isBlank(e.text), 'INVALID_EVIDENCE', 'evidence');
    map.set(e.segmentId, e);
  }
  C.requireValue(total <= C.LIMITS.retainedText, 'LIMIT_EXCEEDED', 'evidence');
  return map;
}
function validateManifest(request, index) {
  const seen = new Set(), events = [];
  for (const raw of C.array(request.manifest, 'evidence')) {
    const r = C.ref(raw);
    C.requireValue(!seen.has(r.segmentId), 'INVALID_EVIDENCE', 'evidence');
    seen.add(r.segmentId);
    const event = index.get(r.segmentId);
    C.requireValue(event && event.isFinal && event.segmentRevision === r.segmentRevision,
      'INVALID_EVIDENCE', 'evidence');
    events.push(event);
  }
  C.requireValue(events.length <= C.LIMITS.notesCount, 'LIMIT_EXCEEDED', 'notes');
  C.requireValue(events.reduce((n, e) => n + Buffer.byteLength(e.text, 'utf8'), 0) <=
    C.LIMITS.notesText, 'LIMIT_EXCEEDED', 'notes');
  C.requireValue(C.canonical(events.map(e => [e.segmentId, e.segmentRevision])) ===
    C.canonical(events.slice().sort(C.eventCompare).map(e => [e.segmentId, e.segmentRevision])),
    'INVALID_EVIDENCE', 'evidence');
  return events;
}
function resolveReferences(rawRefs, request, index) {
  const refs = C.array(rawRefs, 'evidence').map(C.ref);
  C.requireValue(refs.length > 0 && refs.length <= C.LIMITS.evidence,
    'INVALID_EVIDENCE', 'evidence');
  const seen = new Set();
  return refs.map(ref => {
    const key = C.canonical([ref.segmentId, ref.segmentRevision]);
    C.requireValue(!seen.has(key), 'INVALID_EVIDENCE', 'evidence'); seen.add(key);
    C.requireValue(request.manifest.some(m => m.segmentId === ref.segmentId &&
      m.segmentRevision === ref.segmentRevision), 'INVALID_EVIDENCE', 'evidence');
    const event = index.get(ref.segmentId);
    C.requireValue(event && event.isFinal && event.segmentRevision === ref.segmentRevision,
      'INVALID_EVIDENCE', 'evidence');
    return C.freeze({ ref, speakerLabel: C.speaker(event), startMs: event.startMs,
      endMs: Object.hasOwn(event, 'endMs') ? event.endMs : null, text: event.text });
  });
}
function sourceSupportsUtc(value, resolved) {
  // Deliberately narrow lexical support. No named-zone or natural-language
  // conversion. Structural/lexical support still does not prove entailment.
  return resolved.some(e => {
    const matches = e.text.match(/\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z\b/g) || [];
    return matches.some(raw => { try { return C.utc(raw) === value; } catch { return false; } });
  });
}
function validateDraft(raw, category, request, index) {
  C.object(raw, ['category', 'title', 'detail', 'owner', 'deadlineText',
    'deadlineAtUtc', 'deadlineTimeZone', 'evidence'], [], 'notes');
  C.requireValue(raw.category === category, 'INVALID_INPUT', 'notes');
  const title = C.nonblank(raw.title, 'notes'), detail = C.nonblank(raw.detail, 'notes');
  const owner = C.nullable(raw.owner, v => C.nonblank(v, 'notes'));
  const deadlineText = C.nullable(raw.deadlineText, v => C.nonblank(v, 'deadline'));
  const deadlineAtUtc = C.nullable(raw.deadlineAtUtc, v => C.utc(v, 'deadline'));
  const deadlineTimeZone = C.nullable(raw.deadlineTimeZone, v => C.nonblank(v, 'deadline'));
  const resolved = resolveReferences(raw.evidence, request, index);
  C.requireValue(deadlineAtUtc === null || sourceSupportsUtc(deadlineAtUtc, resolved),
    'INVALID_EVIDENCE', 'deadline');
  const evidence = resolved.map(e => e.ref).sort(C.refCompare);
  const preimage = { context: request.context, category, title, detail, owner,
    deadlineText, deadlineAtUtc, deadlineTimeZone, evidence };
  const { context, ...insight } = preimage;
  return C.freeze({ id: 'insight_' + C.hash(preimage), ...insight });
}
function sortInsights(insights, index) {
  const earliest = insight => insight.evidence.map(r => index.get(r.segmentId))
    .sort(C.eventCompare)[0];
  return insights.slice().sort((a, b) => C.eventCompare(earliest(a), earliest(b)) ||
    C.scalarCompare(a.id, b.id));
}
function buildResult(request, draft, rawIndex) {
  // A current-result builder does not repair an invalid request by hiding its
  // warning. Fresh preparation supplies a new, correctly scoped warning set.
  C.requireValue(request.valid === true, 'NOTES_INVALIDATED', 'notes');
  const requestWarnings = validateWarnings(request.warnings);
  C.requireValue(!requestWarnings.some(w => w.code === 'NOTES_INVALIDATED'),
    'NOTES_INVALIDATED', 'notes');
  C.checkSize(draft, C.LIMITS.result, 'notes');
  C.object(draft, KEYS, [], 'notes');
  const index = currentIndex(rawIndex, request.context);
  const events = validateManifest(request, index);
  C.requireValue(events.length > 0, 'NO_FINALIZED_INPUT', 'notes');
  const result = { schemaVersion: 1, context: request.context,
    requestId: request.requestId, notesRevision: request.notesRevision,
    sourceThroughSequence: Math.max(...events.map(e => e.sequence)),
    sourceSegments: request.manifest,
    coverage: validateCoverage(request.coverage), reviewRequired: true };
  let count = 0, unresolved = false;
  const ids = new Set();
  for (const key of KEYS) {
    const items = C.array(draft[key], 'notes');
    C.requireValue(items.length <= C.LIMITS.perCategory, 'LIMIT_EXCEEDED', 'notes');
    count += items.length;
    result[key] = sortInsights(items.map(raw => {
      const insight = validateDraft(raw, C.CATEGORIES[key], request, index);
      C.requireValue(!ids.has(insight.id), 'INVALID_INPUT', 'notes'); ids.add(insight.id);
      unresolved ||= insight.deadlineAtUtc === null &&
        (insight.deadlineText !== null || insight.deadlineTimeZone !== null);
      return insight;
    }), index);
  }
  C.requireValue(count <= C.LIMITS.insights, 'LIMIT_EXCEEDED', 'notes');
  const diagnostics = [C.warning('REVIEW_REQUIRED', 'notes', 'info')];
  if (unresolved) diagnostics.push(C.warning('DEADLINE_UNRESOLVED', 'deadline'));
  result.warnings = C.mergeWarnings(requestWarnings, diagnostics);
  C.checkSize(result, C.LIMITS.result, 'notes');
  return C.freeze(result);
}
function revalidateResult(raw, request, rawIndex) {
  C.object(raw, ['schemaVersion', 'context', 'requestId', 'notesRevision',
    'sourceThroughSequence', 'sourceSegments', 'coverage', 'reviewRequired',
    'warnings', ...KEYS], [], 'notes');
  C.checkSize(raw, C.LIMITS.result, 'notes');
  C.requireValue(raw.schemaVersion === 1 && raw.reviewRequired === true &&
    C.sameContext(raw.context, request.context) && raw.requestId === request.requestId &&
    raw.notesRevision === request.notesRevision &&
    C.canonical(raw.sourceSegments) === C.canonical(request.manifest) &&
    C.canonical(raw.coverage) === C.canonical(request.coverage), 'INVALID_EVIDENCE', 'notes');
  validateWarnings(raw.warnings);
  const draft = {};
  for (const key of KEYS) draft[key] = C.array(raw[key], 'notes').map(item => {
    C.object(item, ['id', 'category', 'title', 'detail', 'owner', 'deadlineText',
      'deadlineAtUtc', 'deadlineTimeZone', 'evidence'], [], 'notes');
    C.id(item.id, 'notes');
    const { id, ...rest } = item; return rest;
  });
  const rebuilt = buildResult(request, draft, rawIndex);
  C.requireValue(C.canonical(raw) === C.canonical(rebuilt), 'INVALID_EVIDENCE', 'notes');
  return rebuilt;
}
module.exports = Object.freeze({ validateCoverage, validateWarnings, currentIndex,
  validateManifest, resolveReferences, validateDraft, sortInsights,
  buildResult, revalidateResult });
