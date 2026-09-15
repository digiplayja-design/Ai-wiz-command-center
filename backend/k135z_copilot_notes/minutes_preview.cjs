'use strict';
const C = require('./contract.cjs');
const T = require('./transcript.cjs');
const E = require('./evidence.cjs');
const N = require('./notes_processor.cjs');
const TITLES = Object.freeze({ decisions: 'Decisions', actionItems: 'Action Items',
  deadlines: 'Deadlines', risks: 'Risks', openQuestions: 'Open Questions',
  takeaways: 'Key Takeaways' });
const EMPTY = 'Nothing identified in the available transcript';
function metadata(raw) {
  C.object(raw, ['title', 'startedAtUtc', 'endedAtUtc', 'timeZone',
    'participants', 'participantListScope'], [], 'metadata');
  const out = { title: C.nullable(raw.title, v => C.nonblank(v, 'metadata')),
    startedAtUtc: C.nullable(raw.startedAtUtc, v => C.utc(v, 'metadata')),
    endedAtUtc: C.nullable(raw.endedAtUtc, v => C.utc(v, 'metadata')),
    timeZone: C.nullable(raw.timeZone, v => C.nonblank(v, 'metadata')),
    participantListScope: C.oneOf(raw.participantListScope, ['unknown', 'partial', 'complete'], 'metadata'),
    participants: raw.participants === null ? null : C.array(raw.participants, 'metadata').map(p => {
      C.object(p, ['participantId', 'displayName'], [], 'metadata');
      return { participantId: C.nullable(p.participantId, C.id), displayName: C.nonblank(p.displayName, 'metadata') };
    }) };
  C.requireValue(out.participants !== null || out.participantListScope === 'unknown', 'INVALID_INPUT', 'metadata');
  C.requireValue(out.startedAtUtc === null || out.endedAtUtc === null ||
    out.startedAtUtc <= out.endedAtUtc, 'INVALID_INPUT', 'metadata');
  return C.freeze(out);
}
function deadlineLabel(insight) {
  const label = insight.deadlineText !== null ? insight.deadlineText :
    insight.deadlineAtUtc !== null ? insight.deadlineAtUtc : 'Not specified';
  const zone = insight.deadlineTimeZone;
  // Display the exact supplied zone once. This is text presentation only:
  // no named-zone conversion, invented UTC instant or metadata mutation.
  return zone === null || label.includes(zone) ? label : label + ' (' + zone + ')';
}
function projectMinutes(input, currentView) {
  try {
    C.object(input, ['meetingMetadata', 'context', 'validatedNotesResult',
      'finalizedTranscriptIndex', 'coverageStatus', 'freshness', 'warnings'], [], 'notes');
    C.object(currentView, ['status', 'freshness', 'result', 'unreflectedSegments', 'warnings'], [], 'notes');
    C.requireValue(['ready', 'empty'].includes(currentView.status) && currentView.result !== null,
      'NOTES_INVALIDATED', 'notes');
    const ctx = C.context(input.context, true);
    C.requireValue(C.sameContext(ctx, currentView.result.context) &&
      C.canonical(currentView.result) === C.canonical(input.validatedNotesResult) &&
      currentView.freshness === input.freshness, 'INVALID_EVIDENCE', 'notes');
    C.oneOf(input.freshness, ['currentWindow', 'outdatedWindow'], 'notes');
    const result = currentView.result;
    C.object(result, ['schemaVersion', 'context', 'requestId', 'notesRevision',
      'sourceThroughSequence', 'sourceSegments', 'coverage', 'reviewRequired',
      'warnings', ...Object.keys(C.CATEGORIES)], [], 'notes');
    C.requireValue(result.schemaVersion === 1 && result.reviewRequired === true,
      'INVALID_INPUT', 'notes');
    C.id(result.requestId, 'notes'); C.uint(result.notesRevision, 'notes');
    E.validateCoverage(result.coverage);
    C.checkSize(result, C.LIMITS.result, 'notes');
    const meta = metadata(input.meetingMetadata);
    const index = E.currentIndex(input.finalizedTranscriptIndex, ctx);
    C.requireValue([...index.values()].every(e => e.isFinal), 'INVALID_EVIDENCE', 'evidence');
    const request = { context: ctx, manifest: result.sourceSegments };
    const manifestEvents = E.validateManifest(request, index);
    C.requireValue(manifestEvents.length > 0 && result.sourceThroughSequence ===
      Math.max(...manifestEvents.map(e => e.sequence)), 'INVALID_EVIDENCE', 'notes');
    let count = 0;
    const ids = new Set();
    for (const key of Object.keys(C.CATEGORIES)) {
      C.array(result[key], 'notes');
      C.requireValue(result[key].length <= C.LIMITS.perCategory, 'LIMIT_EXCEEDED', 'notes');
      count += result[key].length;
      for (const raw of result[key]) {
        C.object(raw, ['id', 'category', 'title', 'detail', 'owner', 'deadlineText',
          'deadlineAtUtc', 'deadlineTimeZone', 'evidence'], [], 'notes');
        const { id, ...draft } = raw;
        const rebuilt = E.validateDraft(draft, C.CATEGORIES[key],
          { ...request, context: ctx }, index);
        C.requireValue(id === rebuilt.id && !ids.has(id), 'INVALID_EVIDENCE', 'notes');
        ids.add(id);
      }
    }
    C.requireValue(count <= C.LIMITS.insights &&
      ((currentView.status === 'empty') === (count === 0)), 'INVALID_INPUT', 'notes');
    const currentCoverage = E.validateCoverage(input.coverageStatus);
    const warnings = C.mergeWarnings(E.validateWarnings(result.warnings),
      [...E.validateWarnings(input.warnings), ...currentCoverage.reasons.map(code =>
        C.warning(code, 'coverage', code === 'COVERAGE_UNKNOWN' ? 'info' : 'warning'))], false);
    const sections = [{ kind: 'meetingInformation', metadata: meta,
      coverage: currentCoverage, freshness: input.freshness }];
    const title = meta.title === null ? 'Meeting minutes — draft' : meta.title + ' — draft';
    const lines = [title, 'Draft; human review required. Not saved.',
      'Coverage: ' + currentCoverage.completeness + '; freshness: ' + input.freshness,
      'Known omitted segments: ' + currentCoverage.omittedSegments,
      'Examined rejected deliveries: ' + currentCoverage.rejectedEvents,
      'Known provisional segments: ' + currentCoverage.provisionalSegments];
    if (meta.startedAtUtc !== null) lines.push('Supplied start: ' + meta.startedAtUtc);
    if (meta.endedAtUtc !== null) lines.push('Supplied end: ' + meta.endedAtUtc);
    if (meta.timeZone !== null) lines.push('Supplied timezone: ' + meta.timeZone);
    if (meta.participants !== null) lines.push('Supplied participants (' +
      meta.participantListScope + '): ' + meta.participants.map(p => p.displayName).join(', '));
    for (const key of Object.keys(C.CATEGORIES)) {
      const items = E.sortInsights(result[key], index).map(insight => ({
        insightId: insight.id, title: insight.title, detail: insight.detail,
        ownerLabel: insight.owner === null ? 'Unassigned' : insight.owner,
        deadlineLabel: deadlineLabel(insight),
        evidence: E.resolveReferences(insight.evidence, request, index)
      }));
      sections.push({ kind: 'insights', category: C.CATEGORIES[key], items,
        emptyMessage: items.length ? null : EMPTY });
      lines.push('', TITLES[key]);
      if (!items.length) lines.push(EMPTY);
      for (const item of items) {
        lines.push(item.title + ': ' + item.detail,
          'Owner: ' + item.ownerLabel + '; deadline: ' + item.deadlineLabel);
        for (const e of item.evidence) lines.push('[' + e.ref.segmentId + '@' +
          e.ref.segmentRevision + '] ' + e.speakerLabel + ' @ ' + e.startMs +
          'ms' + (e.endMs === null ? '' : '-' + e.endMs + 'ms') + ': ' + e.text);
      }
    }
    sections.push({ kind: 'warnings', items: warnings });
    lines.push('', 'Warnings and review limitations', ...warnings.map(w => w.message));
    const preview = { schemaVersion: 1, context: ctx, notesRevision: result.notesRevision,
      title, sections, warnings, plainText: lines.join('\n'), reviewRequired: true, persisted: false };
    C.checkSize(preview, C.LIMITS.preview, 'notes');
    return C.freeze({ ok: true, preview });
  } catch (error) { return C.freeze({ ok: false, rejection: C.rejection(error) }); }
}
function previewFromState(state, previousView, boundMetadata) {
  // boundMetadata is supplied through Main-owned trusted integration. Its
  // context assertion is checked but is not authentication by itself.
  try {
    C.object(boundMetadata, ['context', 'metadata'], [], 'metadata');
    C.requireValue(C.sameContext(boundMetadata.context, state.context), 'CONTEXT_MISMATCH', 'metadata');
    const nextView = N.reconcileNotes(state, previousView);
    C.requireValue(['ready', 'empty'].includes(nextView.status), 'NOTES_INVALIDATED', 'notes');
    const selected = nextView.result.sourceSegments.map(ref =>
      state.retained.find(e => e.segmentId === ref.segmentId && e.segmentRevision === ref.segmentRevision));
    C.requireValue(selected.every(Boolean), 'INVALID_EVIDENCE', 'evidence');
    return projectMinutes({ meetingMetadata: boundMetadata.metadata, context: state.context,
      validatedNotesResult: nextView.result,
      finalizedTranscriptIndex: state.retained.filter(e => e.isFinal),
      coverageStatus: T.coverage(state, 'notesWindow', selected),
      freshness: nextView.freshness, warnings: nextView.warnings }, nextView);
  } catch (error) { return C.freeze({ ok: false, rejection: C.rejection(error) }); }
}
module.exports = Object.freeze({ projectMinutes, previewFromState });
