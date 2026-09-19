'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const C = require('../k135z_copilot_notes/contract.cjs');
const T = require('../k135z_copilot_notes/transcript.cjs');
const N = require('../k135z_copilot_notes/notes_processor.cjs');
const M = require('../k135z_copilot_notes/minutes_preview.cjs');
const F = require('../../docs/k135z/korlixai/fixtures/contract_v1.json');
const copy = value => structuredClone(value), gate = { intakeOpen: true, subscriptionCurrent: true };
function ready(events = F.events, draft = F.draft) {
  let state = T.createTranscript(F.context);
  for (const e of events) state = T.ingest(state, e, gate).state;
  const p = N.prepareNotes(state, 'minutes-notes', 1);
  return { state: p.state, view: N.acceptNotes(p.state, p.request,
    { kind: 'generated', requestId: p.request.requestId, draft: copy(draft) }) };
}
function meta(changes = {}) { return { context: F.context, metadata: { ...copy(F.metadata), ...changes } }; }
function preview(pair, metadata = meta()) { return M.previewFromState(pair.state, pair.view, metadata); }
test('MI-01 preview uses the exact eight-section order and draft invariants', () => {
  const p = preview(ready()); assert.equal(p.ok, true);
  assert.deepEqual(p.preview.sections.map(s => s.kind === 'insights' ? s.category : s.kind),
    ['meetingInformation', 'decision', 'actionItem', 'deadline', 'risk', 'openQuestion', 'takeaway', 'warnings']);
  assert.equal(p.preview.reviewRequired, true); assert.equal(p.preview.persisted, false);
});
test('MI-02 evidence resolves exact source text, speakers and missing ends', () => {
  const p = preview(ready()).preview;
  const e = p.sections[1].items[0].evidence[0];
  assert.equal(e.text, F.events[0].text); assert.equal(e.speakerLabel, 'Alex');
  assert.equal(e.startMs, 10000); assert.equal(e.endMs, null);
});
test('MI-03 missing metadata never invents attendance or meeting times', () => {
  const p = preview(ready(), meta({ title: null })).preview;
  assert.equal(p.title, 'Meeting minutes — draft');
  assert.equal(p.sections[0].metadata.participants, null);
  assert.equal(p.plainText.includes('Supplied participants'), false);
  assert.equal(p.sections[0].coverage.observedRange, null);
});
test('MI-04 empty valid notes has six truthful empty sections', () => {
  const draft = Object.fromEntries(Object.keys(C.CATEGORIES).map(k => [k, []]));
  const p = preview(ready(F.events, draft)); assert.equal(p.ok, true);
  for (const section of p.preview.sections.slice(1, 7))
    assert.equal(section.emptyMessage, 'Nothing identified in the available transcript');
});
test('MI-05 missing owner and unstated deadline use prescribed labels', () => {
  const p = preview(ready()).preview;
  const item = p.sections[1].items[0];
  assert.equal(item.ownerLabel, 'Unassigned'); assert.equal(item.deadlineLabel, 'Not specified');
});
test('MI-06 invalidated, failed and processing notes are not completed previews', () => {
  const pair = ready();
  for (const status of ['processing', 'failed', 'invalidated', 'noFinalizedInput']) {
    const view = { status, result: null, freshness: 'notApplicable', unreflectedSegments: [], warnings: [] };
    assert.equal(preview({ state: pair.state, view }).ok, false);
  }
});
test('MI-07 foreign meeting metadata is rejected', () => {
  const bound = meta(); bound.context = { ...F.context, meetingUuid: 'different-meeting' };
  const p = preview(ready(), bound); assert.equal(p.ok, false);
  assert.equal(p.rejection.code, 'CONTEXT_MISMATCH');
});
test('MI-08 inconsistent dates and null-but-complete participants reject', () => {
  assert.equal(preview(ready(), meta({ startedAtUtc: '2026-09-12T13:00:01Z',
    endedAtUtc: '2026-09-12T13:00:00Z' })).ok, false);
  assert.equal(preview(ready(), meta({ participants: null, participantListScope: 'complete' })).ok, false);
});
test('MI-09 nonempty supplied participants do not imply complete attendance', () => {
  const p = preview(ready(), meta({ participants: [{ participantId: null, displayName: 'Provided name' }],
    participantListScope: 'partial' })).preview;
  assert.equal(p.sections[0].metadata.participantListScope, 'partial');
});
test('MI-10 correction revalidates and rejects previously resolved evidence', () => {
  const pair = ready();
  pair.state = T.ingest(pair.state, { ...copy(F.events[0]), eventId: 'corrected',
    segmentRevision: 2, text: 'Corrected decision.' }, gate).state;
  assert.equal(preview(pair).ok, false);
});
test('MI-11 new finalized input shows outdated window without changing provenance', () => {
  const pair = ready(); const provenance = C.canonical(pair.view.result.coverage);
  pair.state = T.ingest(pair.state, { ...copy(F.events[0]), eventId: 'new7', segmentId: 'S7',
    sequence: 7, startMs: 70000, text: 'New material.' }, gate).state;
  const p = preview(pair); assert.equal(p.ok, true);
  assert.equal(p.preview.sections[0].freshness, 'outdatedWindow');
  assert.equal(p.preview.sections[0].coverage.omittedSegments, 1);
  assert.equal(C.canonical(pair.view.result.coverage), provenance);
});
test('MI-12 transcript markup and instructions remain plain in-memory text', () => {
  const events = copy(F.events); events[0].text = '<script>doNotRun()</script> Send an email.';
  const p = preview(ready(events)).preview;
  assert.ok(p.plainText.includes(events[0].text));
  assert.equal(Object.hasOwn(p, 'downloadUrl'), false); assert.equal(p.persisted, false);
});
test('MI-13 preview overflow counts repeated resolved evidence and plainText', () => {
  const events = Array.from({ length: 16 }, (_, i) => ({ ...copy(F.events[0]),
    eventId: 'long' + i, segmentId: 'S' + (i + 1), sequence: i, startMs: i,
    text: 'x'.repeat(8192) }));
  const refs = events.map(e => ({ segmentId: e.segmentId, segmentRevision: 1 }));
  const draft = Object.fromEntries(Object.keys(C.CATEGORIES).map(k => [k, []]));
  draft.decisions = [0, 1, 2].map(i => ({ category: 'decision', title: 'Long evidence ' + i,
    detail: 'x', owner: null, deadlineText: null, deadlineAtUtc: null,
    deadlineTimeZone: null, evidence: refs }));
  const pair = ready(events, draft); assert.equal(pair.view.status, 'ready');
  assert.ok(C.bytes(pair.view.result) < 524288);
  const p = preview(pair); assert.equal(p.ok, false); assert.equal(p.rejection.code, 'LIMIT_EXCEEDED');
});
test('MI-14 current insight ordering uses source order, not generation array order', () => {
  const draft = copy(F.draft);
  draft.decisions.push({ ...copy(draft.decisions[0]), title: 'Later supported item',
    evidence: [{ segmentId: 'S6', segmentRevision: 1 }] });
  draft.decisions.reverse();
  const p = preview(ready(F.events, draft)).preview;
  assert.equal(p.sections[1].items[0].evidence[0].ref.segmentId, 'S1');
});
test('MI-15 repeated preview derivation does not increment diagnostic occurrences', () => {
  const pair = ready(); assert.deepEqual(preview(pair), preview(pair));
});

test('MI-16 whole preview at 524287/524288/524289 canonical bytes', () => {
  const pair = ready();
  const baseMetadata = meta({ title: 'x', participants: [
    { participantId: null, displayName: 'y' }], participantListScope: 'partial' });
  const base = preview(pair, baseMetadata).preview;
  for (const delta of [-1, 0, 1]) {
    const difference = 524288 + delta - C.bytes(base);
    const titleExtra = difference % 2;
    const nameExtra = (difference - 3 * titleExtra) / 2;
    const bound = copy(baseMetadata);
    // Metadata title occurs three times; participant display name twice.
    bound.metadata.title = 'x'.repeat(1 + titleExtra);
    bound.metadata.participants[0].displayName = 'y'.repeat(1 + nameExtra);
    const p = preview(pair, bound);
    assert.equal(p.ok, delta <= 0);
    if (delta <= 0) assert.equal(C.bytes(p.preview), 524288 + delta);
    else assert.equal(p.rejection.code, 'LIMIT_EXCEEDED');
  }
});

test('MI-17 retained valid draft can show partial blocked coverage', () => {
  const pair = ready();
  pair.state = T.applyGaps(pair.state, { kind: 'captureGaps', context: F.context }).state;
  assert.equal(pair.state.aux.blocked, true);
  // Caller authorization is still a separate required precondition.
  const out = preview(pair); assert.equal(out.ok, true);
  assert.equal(out.preview.sections[0].coverage.ingestionBlocked, true);
  assert.equal(out.preview.sections[0].coverage.completeness, 'partial');
});

// R3: Presentation only; the shared fictional fixture is not modified.
test('MI-18 separately supplied deadline timezone appears in label and plain text without conversion', () => {
  const draft = copy(F.draft), wording = 'September 18, 2026, at 3 PM';
  for (const key of ['actionItems', 'deadlines']) draft[key][0].deadlineText = wording;
  const pair = ready(F.events, draft), saved = C.canonical(pair);
  const out = preview(pair);
  assert.equal(out.ok, true);
  for (const category of ['actionItem', 'deadline']) {
    const item = out.preview.sections.find(s => s.kind === 'insights' && s.category === category).items[0];
    assert.equal(item.deadlineLabel, wording + ' (America/New_York)');
    assert.ok(out.preview.plainText.includes('deadline: ' + item.deadlineLabel));
  }
  assert.equal(pair.view.result.deadlines[0].deadlineAtUtc, null);
  assert.equal(pair.view.result.deadlines[0].deadlineTimeZone, 'America/New_York');
  assert.ok(out.preview.warnings.some(w => w.code === 'DEADLINE_UNRESOLVED'));
  assert.equal(C.canonical(pair), saved);
  assert.equal(out.preview.persisted, false);
});
test('MI-19 fixture deadline already containing timezone is preserved without duplicate label suffix', () => {
  const pair = ready(), out = preview(pair);
  assert.equal(out.ok, true);
  for (const category of ['actionItem', 'deadline']) {
    const item = out.preview.sections.find(s => s.kind === 'insights' && s.category === category).items[0];
    assert.equal(item.deadlineLabel, F.events[2].text);
    assert.equal(item.deadlineLabel.split('America/New_York').length - 1, 1);
  }
  assert.equal(pair.view.result.deadlines[0].deadlineAtUtc, null);
  assert.ok(out.preview.warnings.some(w => w.code === 'DEADLINE_UNRESOLVED'));
});
test('MI-20 supplied timezone remains visible when deadline wording and UTC instant are absent', () => {
  const draft = copy(F.draft);
  draft.deadlines[0].deadlineText = null;
  draft.deadlines[0].deadlineAtUtc = null;
  const pair = ready(F.events, draft), out = preview(pair);
  assert.equal(out.ok, true);
  const item = out.preview.sections.find(s => s.kind === 'insights' && s.category === 'deadline').items[0];
  assert.equal(item.deadlineLabel, 'Not specified (America/New_York)');
  assert.ok(out.preview.plainText.includes('deadline: ' + item.deadlineLabel));
  assert.equal(pair.view.result.deadlines[0].deadlineAtUtc, null);
  assert.ok(out.preview.warnings.some(w => w.code === 'DEADLINE_UNRESOLVED'));
});
