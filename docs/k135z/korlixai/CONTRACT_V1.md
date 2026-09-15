# K135Z C1 contract and draft implementation map

Contract: `K135Z-KAI-CONTRACT-v1 / MAIN-DECISIONS-01`.
Consolidation: `K135Z-KAI-CONTRACT-CONSOLIDATION-01`.
Final design acknowledgment: `K135Z-MAIN-CONTRACT-ACK-20260912`.
Execution preparation basis: `K135Z-MAIN-C1-EXECUTION-SPEC-02`.

**Design baseline frozen; this candidate is review-only and unexecuted.**
The text below retains the submitted consolidation's declarations and rules.
Its historical phrases "proposed" or "for final reconciliation" refer to the
submission stage. Main's final acknowledgment accepts those counter, range and
fixture definitions. This file does not rewrite the original submitted PDF.
No design amendment is proposed by this draft.

## Ownership and use

Only the five allocated CommonJS modules, three designated test files, shared
fictional fixture and two Markdown files belong to C1. No provider, database,
server mount, OAuth, RTMS adapter or production fixture fallback is included.
The pure consumers validate data; they do not authenticate anyone. The C2
workspace and Main-owned adapters remain responsible for trusted authority,
current subscription/operation binding and permission to call these consumers.
A metadata-only RTMS status or generic context ID is never listening permission.

## Draft module API

- `contract.cjs`: exact scalar/object validation, CanonicalV1, context/event and
  control-envelope validation, safe fixed diagnostics, evidence/range helpers.
- `transcript.cjs`: immutable transcript/replay/finality state; explicit active
  ingress gate; bounded queue; cumulative gap-snapshot validation; coverage and
  finalized suffix selection; bounded request/unreflected bookkeeping.
- `evidence.cjs`: exact input/index matching, structural evidence validation,
  deterministic insight IDs, notes output/revalidation and size checks.
- `notes_processor.cjs`: pure prepare/accept/reconcile/prompt functions, plus a
  separate asynchronous injected-generator operation with injected cancellation
  and deadline scheduling. No ambient clocks or real provider imports.
- `minutes_preview.cjs`: pure projection and a preferred state-bound wrapper;
  no file, clipboard, print, URL-opening, sending or persistence operation.

`createTranscript` creates a pure same-context data store, not an authorized
session. `ingest` defaults closed. Its boolean gate arguments represent an
already validated caller decision; they are not a replacement for the frozen
C2 state machine. This package does not claim to implement that Flutter state
machine, atomic Main service command serialization, or a live transport.

## Reviewable auxiliary representation

The transcript state has one complete immutable context. All four partitioned
maps (`events`, `revisions`, `guards`, `unreflected`) are scoped by that context.
Their inner keys are canonical structured tuples, not delimiter concatenations.
Event aliases map to segment/revision tuples. Revision records store exact
semantic content once, with their context on the enclosing state. Guards retain
sequence, accepted revision/finality and content-acceptance serial after eviction.
The full identity is the enclosing validated context together with the tuple.
No truncated semantic digest is substituted for exact replay comparison.

Map buckets are immutable copy-on-write values. A map stores its actual canonical
bucket-array byte length as a cache; the cache value and count also consume the
auxiliary budget. `auxiliaryBytes` includes the full logical bucket bytes and the
other metadata, context, request snapshot, warning records and unreflected map.
The 1,024-character emergency reserve is also charged. Overflow consumes that
reserved capacity to publish a safe blocked state, retaining prior identity and
finality evidence. It does not allocate an unbounded side log. Numeric overflow
retains the last exact count, closes intake and marks coverage blocked/partial.

The queue has its own ceiling; this draft counts the entire canonical queue
array including separators/brackets. Complete map/state correctness and size
arithmetic remain static-review and later candidate-test subjects, not claims
of measured performance. Temporary derived indexes in evidence projection are
bounded by the retained-window/input ceilings and are not persistent histories.

## Notes and preview caveats for static review

The request snapshot stored in the auxiliary state is shared by reference with
its returned preparation packet. It contains the selected segments, manifest,
serial, immutable request-time coverage and request warnings. It is not a
separate unbounded cache. New accepted material outside the request updates one
current reference per identity; manifest changes invalidate the request.
The generator receives only requestId and finalized segments. Caller identity,
coverage, permissions, IDs and review flags are not generator authority.

UTC support is deliberately narrow: an accepted UTC deadline must match a valid
explicit UTC literal in referenced source. No named-zone conversion is done.
This is lexical/structural support, not a proof of task-date entailment; draft
review remains mandatory. Titles, detail and owner entailment are not certified
by reference existence. No production generator is present.

`previewFromState` revalidates the notes result and current manifest before
calling `projectMinutes`. The lower-level projection has the frozen validated-
input/authorized-caller preconditions; it also checks result shape, IDs and every
reference. Trusted metadata provenance cannot be established by a string context
comparison alone. Main supplies that integration; no fixture fallback is allowed.

## Test responsibility boundary

The three C1 test texts cover the pure package and control-schema rejection.
The four shared `c2LifecycleExpectations` are explicit C2 acceptance examples,
not passing C1 tests or an independent Node session-controller implementation.
C2 must exercise acknowledged Start/Stop, command fencing, reactive authorization,
disposal and shared-service ownership against its real controller candidate.
The frozen foundation speech regression must remain separate and unchanged.

## Retained normative declarations and rules

B. Retained revision-1.1 declarations and enum values
=====================================================

The following three complete declarations retain the field names, optional markers and literal unions in revision 1.1. Scalar validation refinements in C.D02 apply without silently replacing the original shapes. [R11, section 4, lines 364–429]

Context {
  tenantId: string
  userId: string
  agentId: string
  sessionId: string
  meetingUuid: string
  streamId: string | null
  generation: integer
}

SessionSnapshot {
  schemaVersion: 1
  context: Context
  revision: integer
  state: "ready" | "listening" | "paused" | "stopped" | "error"
  hostAuthorized: boolean
  listeningAuthorized: boolean
  activeSeconds: integer
  capabilities: { canSpeak: false }
}

TranscriptEvent {
  schemaVersion: 1
  context: Context

  eventId: string
  segmentId: string
  segmentRevision: integer
  sequence: integer

  speakerId?: string
  speakerName?: string

  startMs: integer
  endMs?: integer

  text: string
  isFinal: boolean
  receivedAt: UTC timestamp string
  source: "zoom_rtms" | "offline_fixture"
}

The referenced literal enums are SessionSnapshot.state = ready | listening | paused | stopped | error, and TranscriptEvent.source = zoom_rtms | offline_fixture. The following existing UI vocabularies remain separate; these labels are not additional SessionSnapshot states. [R11, section 4, lines 495–516]

Existing foundation display status:
  disconnected, ready, listening, paused, speaking, stopped, error

Existing connection-controller phase:
  idle, loadingStatus, disconnected, connecting,
  connected, loadingMeetings, disconnecting, error

Main supplies trusted context bindings. The selected KORLIX agent ID is not a visual character ID, speaker ID, meeting topic or Zoom account ID. Server generation is nonnegative and is not a local operation counter. streamId may be null in an inactive snapshot, but must be nonempty in a transcript event. Its first adoption follows C.D01; unsolicited transcript identifiers cannot rebind the workspace. [R11, lines 375–381]

startMs and endMs use elapsed milliseconds from the fixed start of the KORLIX capture session, not Unix time or billable active seconds. receivedAt is Main’s explicit receipt timestamp, not an ordering authority. An event endMs, when present, may equal startMs. The stricter TimeRange rule below does not change that retained event rule. [R11, lines 433–448]

C. Consolidated D01–D05 declarations and rules
==============================================

D01. Session, authority, correlation and cancellation
-----------------------------------------------------

The supporting envelopes and injected interfaces accepted from C0-DELTA-01 are retained below. A field is required unless marked “?”; a nullable field is not an optional field. These are internal interfaces, not native Zoom messages or invented production endpoints. [A0, D01; M1, D01]

OperationRef {
  requestId: Id
  localEpoch: UInt
  operationNumber: UInt
}

SessionRequest {
  schemaVersion: 1
  operation: OperationRef
  action: "refresh" | "start" | "pause" | "stop"
  expectedContext: Context
  expectedSnapshotRevision: UInt | null
}

OperationError {
  code: "UNAVAILABLE" | "DENIED" | "TIMEOUT" | "CANCELLED" |
        "BINDING_MISMATCH" | "CONFLICT" | "PROTOCOL_ERROR"
  message: NonBlankText
  remoteOutcome: "notRequested" | "rejected" | "unknown"
  automaticRetry: false
}

SessionReply {
  schemaVersion: 1
  operation: OperationRef
  action: SessionRequest.action
  outcome:
    { kind: "acknowledged", snapshot: SessionSnapshot }
    OR
    { kind: "failed", error: OperationError }
}

AuthorityUpdate {
  authorityRevision: UInt
  context: Context | null
  viewerAuthorized: boolean
}

TimeRange {
  startMs: UInt
  endMs: UInt
}

SessionSignal =
  { kind: "snapshot", snapshot: SessionSnapshot }
  OR { kind: "transcript", event: TranscriptEvent }
  OR { kind: "meetingEnded", snapshot: SessionSnapshot }
  OR { kind: "transportLost", context: Context }
  OR {
    kind: "captureGaps",
    context: Context,
    revision: UInt,
    gaps: TimeRange[]
  }

Unsubscribe = () -> void

CancellationToken {
  isCancelled(): boolean
  subscribe(listener: () -> void): Unsubscribe
}

OwnedSubscription {
  cancel(): Future<void>
}

WorkspacePort {
  request(
    request: SessionRequest,
    cancellation: CancellationToken
  ): Future<SessionReply>

  subscribe(
    context: Context,
    listener: (SessionSignal) -> void
  ): OwnedSubscription

  subscribeAuthority(
    listener: (AuthorityUpdate) -> void
  ): OwnedSubscription
}

One command ordering domain. Start, Pause and Stop share one monotonically ordered session-command domain for the current trusted binding. Independent action-specific counters are prohibited. localEpoch and operationNumber reject obsolete local callbacks; they do not grant authority, manufacture a server generation or replace Main’s atomic revision check. Refresh is nonmutating and cannot remove a command fence. [M1, D01.1]

Main’s service must serialize the expectedSnapshotRevision check and command-state decision for the bound session/generation. An initial refresh may carry a null expected revision. Mutating commands require the validated revision they are based on. An obsolete expected revision produces CONFLICT or the agreed failure outcome, not silent authorization. An acknowledged Stop fences older Starts and is terminal for that generation. A conflicted or timed-out Stop only establishes a local block and an unconfirmed remote outcome.

Correlated acceptance. A reply must match the current pending OperationRef, action, local epoch and expected binding. Only a current, successful Start acknowledgment with state=listening, hostAuthorized=true, listeningAuthorized=true and a valid adopted stream can open local ingestion. Both snapshot flags remain necessary; a connected account or Enterprise display flag is insufficient. Snapshot revisions order snapshots within the same binding: lower is stale; equal plus identical validated content is a no-op; equal plus inconsistent content is a conflict. A higher revision does not override a terminal-generation fence. [R11, lines 401–403; M1, D01.1–3]

State-transition mapping using the retained enum. Pending action, local ingestion block, disconnected transport and uncertain remote outcome are local/controller concerns; they are not added to SessionSnapshot.state. An acknowledgment must be valid for the service’s bound state and revision; the following mapping does not self-authorize a command.

Trigger / accepted result: Trusted inactive binding / validated ready snapshot
Retained snapshot state and local outcome: ready; ingestion closed. No self-granted Start permission.

Trigger / accepted result: Explicit Start from a valid ready state
Retained snapshot state and local outcome: Correlated authorized listening acknowledgment opens ingestion. Only first Start may adopt null -> nonempty streamId with all other context fields unchanged.

Trigger / accepted result: Explicit Start to resume an acknowledged pause
Retained snapshot state and local outcome: paused -> listening; same generation and already-adopted stream unless Main explicitly rebinds.

Trigger / accepted result: Pause requested / then acknowledged
Retained snapshot state and local outcome: Block immediately; retain last confirmed state plus pending status until a current paused acknowledgment. paused is nonterminal.

Trigger / accepted result: Stop requested / then acknowledged
Retained snapshot state and local outcome: Block ingestion and invalidate pending notes immediately. A valid stopped acknowledgment establishes the terminal generation fence; retain authorized in-memory evidence under the accepted context.

Trigger / accepted result: Valid meetingEnded signal
Retained snapshot state and local outcome: Its terminal snapshot maps to stopped, not a new ended enum. Reject late callbacks and prohibit same-generation restart. An inconsistent signal is a protocol error, not fabricated stopped state.

Trigger / accepted result: Stop conflict, timeout or transport failure
Retained snapshot state and local outcome: Do not manufacture a stopped snapshot. Keep local ingestion blocked and remote outcome unconfirmed; no automatic retry.

Trigger / accepted result: Valid error snapshot / control protocol error
Retained snapshot state and local outcome: error is the retained error state where supplied. A local validation failure does not invent an authoritative snapshot; it blocks ingestion and exposes a safe local error.

Trigger / accepted result: Refresh or unsolicited snapshot after a local block
Retained snapshot state and local outcome: May update validated remote status or restrict ingestion. Cannot reopen ingestion after pause, stop, timeout, transport loss or protocol block.

Trigger / accepted result: New capture after stopped / meeting end
Retained snapshot state and local outcome: Requires Main-issued trusted rebinding with a new generation and explicit Start. No stopped -> listening transition in the old generation.

Stream and subscription ownership. First stream adoption occurs only through the current Start acknowledgment. Replacement stream/generation comes through trusted rebinding, never an incoming transcript’s differing IDs. Pause/resume preserves the adopted stream. Stop preserves the accepted context for authorized in-memory review; access loss, identity change or disposal clears private state. [M1, D01.2–5]

Authority revisions are scoped to the particular owned authority subscription. Replacing that subscription synchronously invalidates its callbacks before adopting new state. Within the active subscription, lower revisions are stale; identical equal revisions are no-ops; inconsistent equal revisions are conflicts. Null context or viewerAuthorized=false immediately blocks processing and clears private data. Invalidate callbacks and pending-result acceptance before awaiting owned cancellation. Never dispose a shared injected service. There is no automatic effectful retry after cancellation, timeout or uncertain outcome.

Capture gaps. TimeRange is [startMs,endMs), endMs > startMs, in the capture-session elapsed-ms coordinate system. captureGaps.revision is scoped to the accepted context. Its gaps array is a complete cumulative snapshot of known gaps for that revision, normalized by sorting by start/end and merging overlapping or adjacent intervals. Lower revisions are stale; equal revisions with identical normalized gaps are no-ops; equal revisions with different normalized gaps are conflicts. A higher revision must cover every previously known gap; a shrink/removal is a protocol conflict because v1 has no backfill/retraction mechanism. Numerical sequence gaps do not imply capture loss. [M1, D01.6]

D02. Canonical processing and transcript reduction
--------------------------------------------------

The accepted scalar policies are consolidated here. Generic Id validity does not authenticate a caller or relax Main’s storage/identity restrictions. These strict new-object rules are not silently applied to B5A HTTP responses. [A0, D02; M1, D02]

UInt = numeric integer in [0, 9007199254740991].
       Reject numeric strings, fractions, nonfinite values and -0.

Text = well-formed Unicode string.
       Reject unpaired surrogates; do not normalize Unicode.

BlankV1 = U+0009–U+000D, U+0020, U+0085, U+00A0, U+1680,
          U+2000–U+200A, U+2028, U+2029, U+202F, U+205F,
          U+3000, U+FEFF.

NonBlankText = Text containing a character outside BlankV1.
Id = NonBlankText of at most 256 UTF-8 bytes; preserve exactly.

UtcInstant = valid Gregorian date/time in either form:
  YYYY-MM-DDTHH:mm:ssZ
  YYYY-MM-DDTHH:mm:ss.sssZ
Years 0001–9999; seconds 00–59.
Canonical output always includes .sssZ.

Every retained context ID is Id; only streamId is explicitly nullable. Context generation, snapshot revision/activeSeconds, and transcript revision/sequence/ms fields use UInt. Event text and speakerName use Text; receivedAt uses UtcInstant. Required fields reject omission and null except the explicitly nullable streamId. Optional speakerId, speakerName and endMs may be omitted, but present null is rejected. Present speakerId must be nonblank; present speakerName may be blank and remains semantically distinct from omission. Missing/blank display names project to “Unknown speaker”; they do not merge identities. endMs >= startMs remains valid for transcript events. [A0, D02; R11, section 4]

All new internal object fields are exact: reject unknown fields. Do not coerce objects to strings, replace missing timestamps with zero/current time, trim IDs, or rewrite source text. Nullable owner/deadline fields below are required keys; blank non-null values are invalid.

CanonicalV1. Object keys sort by Unicode scalar-value order; declared array order is preserved. Integers use decimal notation; boolean/null tokens are literal. There is no insignificant whitespace or trailing newline. U+0022 becomes \" and U+005C becomes \\. Every U+0000–U+001F uses lowercase \u00xx, never short escapes. Slash is unescaped. Other valid scalar values are direct UTF-8. Accepted UtcInstant fields become .sssZ before canonical comparison or hashing. [M1, D02.1]

Structured identities and semantic equality. Use structured tuples over the complete validated context, not delimiter concatenation:

Event lookup key:             [context, eventId]
Segment/revision lookup key:  [context, segmentId, segmentRevision]
Segment safeguard key:        [context, segmentId]
Semantic event value:         validated event minus eventId and receivedAt

All remaining fields, including source and optional-field presence, participate in canonical semantic equality. Identity keys and semantic values are checked separately. A changed receipt timestamp alone is a redelivery; changing source is not. A new event-ID alias for an identical segment/revision is a transcript no-op but still requires bounded replay accounting. [M1, D02.2]

Reduction. normalizeEvent(raw,expectedContext) returns a validated event or structured rejection. reduceTranscript(previousState,validatedEvent) returns immutable state, disposition and diagnostics. Both are deterministic, without clock reads, provider calls, filesystem/database effects or mutation of caller collections. [R11, lines 450–477]

Conflicting known event or segment/revision identities are checked before stale or empty classification. Exact redelivery is a no-op. Established segment sequence cannot change. Lower revisions cannot replace accepted content; higher provisional revisions cannot downgrade accepted finality; a higher final correction can replace content and invalidate notes. Whitespace-only updates never delete content or advance its accepted content revision. These no-op/rejection rules also apply after display eviction. [M1, D02.3]

The segment’s sequence, highest accepted revision, accepted finality and replay/conflict identities survive display eviction. A duplicate cannot resurrect its evicted display entry; an old revision cannot become new simply because text was evicted. Required guard/history capacity is checked before admitting new bookkeeping. No guard erasure is permitted to stay within D05.

Display order remains (startMs, sequence, segmentId), with non-locale scalar ordering for segmentId. Sequence is stable, not assumed dense and not proof of completeness. Invalid/foreign-context input is not applied to transcript content and is not quoted in diagnostics. Transcript instructions remain inert content; they cannot grant permissions, invoke tools, select credentials or authorize network activity.

D03. Notes, evidence, coverage and freshness
--------------------------------------------

These accepted supporting shapes are consolidated without changing their category vocabulary or caller/validator ownership. The NotesResult.coverage field is the explicit addition accepted from C0-DELTA-01. [A0, D03; M1, D03]

EvidenceRef { segmentId: Id; segmentRevision: UInt }

Category = "decision" | "actionItem" | "deadline" |
           "risk" | "openQuestion" | "takeaway"

Insight {
  id: Id
  category: Category
  title: NonBlankText
  detail: NonBlankText
  owner: NonBlankText | null
  deadlineText: NonBlankText | null
  deadlineAtUtc: UtcInstant | null
  deadlineTimeZone: NonBlankText | null
  evidence: EvidenceRef[]
}

WarningCode =
  "INVALID_INPUT" | "CONTEXT_MISMATCH" | "PROTOCOL_CONFLICT" |
  "EMPTY_TEXT" | "FINALITY_DOWNGRADE" | "LIMIT_EXCEEDED" |
  "WINDOW_TRUNCATED" | "CAPTURE_GAP" | "COVERAGE_UNKNOWN" |
  "PROVISIONAL_EXCLUDED" | "NO_FINALIZED_INPUT" |
  "INVALID_EVIDENCE" | "NOTES_INVALIDATED" | "NOTES_OUTDATED" |
  "DEADLINE_UNRESOLVED" | "GENERATOR_ERROR" |
  "TIMEOUT" | "CANCELLED" | "REVIEW_REQUIRED"

Warning {
  code: WarningCode
  severity: "info" | "warning" | "error"
  field: Text | null
  eventId: Id | null
  segment: EvidenceRef | null
  message: NonBlankText
  occurrences: UInt
}

Coverage {
  scope: "transcriptWindow" | "notesWindow"
  completeness: "unknown" | "partial"
  observedRange: TimeRange | null
  knownCaptureGaps: TimeRange[]
  omittedSegments: UInt
  rejectedEvents: UInt
  provisionalSegments: UInt
  ingestionBlocked: boolean
  reasons: WarningCode[]
}

NotesResult {
  schemaVersion: 1
  context: Context
  requestId: Id
  notesRevision: UInt
  sourceThroughSequence: UInt | null
  sourceSegments: EvidenceRef[]
  decisions: Insight[]
  actionItems: Insight[]
  deadlines: Insight[]
  risks: Insight[]
  openQuestions: Insight[]
  takeaways: Insight[]
  coverage: Coverage
  reviewRequired: true
  warnings: Warning[]
}

NotesView {
  status: "notRequested" | "processing" | "noFinalizedInput" |
          "ready" | "empty" | "failed" | "invalidated"
  freshness: "notApplicable" | "currentWindow" | "outdatedWindow"
  result: NotesResult | null
  unreflectedSegments: EvidenceRef[]
  warnings: Warning[]
}

FinalizedSourceSegment {
  segmentId: Id
  segmentRevision: UInt
  sequence: UInt
  speakerId?: Id
  speakerName?: Text
  startMs: UInt
  endMs?: UInt
  text: Text
  isFinal: true
}

GeneratorRequest {
  requestId: Id
  segments: FinalizedSourceSegment[]
}

DraftInsight = Insight without id

GeneratorDraft {
  decisions: DraftInsight[]
  actionItems: DraftInsight[]
  deadlines: DraftInsight[]
  risks: DraftInsight[]
  openQuestions: DraftInsight[]
  takeaways: DraftInsight[]
}

GeneratorReply =
  { kind: "generated", requestId: Id, draft: GeneratorDraft }
  OR { kind: "failed", requestId: Id, error: OperationError }

NotesGenerator {
  generate(
    request: GeneratorRequest,
    cancellation: CancellationToken
  ): Future<GeneratorReply>
}

Validation. Each factual insight requires 1–16 unique references resolving to exact finalized segment/revision pairs in BOTH the captured request manifest and the current validated same-context index used for acceptance. A real segment outside the request window is invalid evidence for that result. Invalid evidence rejects the entire result, not just the offending references. Each category must match its array; the six array/category pairs retain their spelling above. Duplicate computed insight IDs within a result are rejected. Structural linkage is not a guarantee that a generated claim is entailed; reviewRequired remains true. [M1, D03.1–2]

Exact insight-ID preimage. The following object has exactly these keys and no requestId, notesRevision, supplied id or receipt metadata:

{
  context,
  category,
  title,
  detail,
  owner,
  deadlineText,
  deadlineAtUtc,
  deadlineTimeZone,
  evidence
}

id = "insight_" + lowercase_sha256(CanonicalV1(preimage)_UTF8)

Use validated values, explicit nulls and canonical UTC formatting. Sort evidence for this preimage by scalar-value segmentId and then numeric segmentRevision. This does not change the selected-transcript order of sourceSegments. The validator computes IDs; the generator never supplies them. Identical preimage content produces the same ID; changed content is an explicit replacement, not a fuzzy title merge. [M1, D03.2]

Manifest and result freshness. sourceSegments is the exact unique selected request manifest in transcript order. sourceThroughSequence is the maximum included sequence, or null for an empty manifest; it is not a contiguous-coverage marker. Caller/validator owns context, request metadata, notesRevision, source manifest, coverage, IDs and review flags. Any source revision change anywhere in the manifest invalidates pending acceptance and the derived result, even when that segment is not cited by one particular insight. Removed/unresolvable evidence also invalidates it. Late replies cannot restore invalidated notes. [M1, D03.3]

New finalized material outside an unchanged manifest is recorded as unreflected and marks an otherwise valid result outdatedWindow. It never silently expands the old input. currentWindow means current for the selected request window, not a complete meeting. No finalized input means no generator call and noFinalizedInput with result=null. A valid populated source window yielding six empty arrays produces empty. Failed validation/provider handling produces failed; source correction produces invalidated. Only ready and empty carry a result. All other statuses have result=null and freshness=notApplicable; processing/failed/invalidated are not completed previews. [A0, D03; M1, D03–D04]

Deadlines and diagnostics. Unstated owner/deadline remains null. An absent deadline is not an unresolved-deadline error. Preserve explicit wording and timezone; perform no named-timezone conversion using ambient settings or a new dependency. Unresolvable stated deadlines retain deadlineAtUtc=null and DEADLINE_UNRESOLVED. A syntactically valid UTC string is acceptable only with support in the referenced source. Do not turn proposals into decisions, conflicting statements into agreement or requests into completed actions. [M1, D03.4; R11, section 5]

Warnings and OperationError messages use fixed, validator-controlled safe text and field names, never raw provider errors, credentials, foreign-context source text or executable instructions. Aggregate warnings by the fixed tuple (code,field,severity), retain only the permitted first safe reference and use occurrences as defined below. Their counters and references consume the combined auxiliary-state budget. [A0, D03; M1, D03.5]

D04. Minutes and metadata
-------------------------

The accepted typed declarations follow. Eligibility is a required caller precondition tied to a currently valid ready/empty NotesView and the same validated result; retaining MinutesPreviewInput does not waive that check or add an unapproved duplicate NotesView field. Revalidate all evidence during projection. [A0, D04; M1, D04]

MeetingParticipant {
  participantId: Id | null
  displayName: NonBlankText
}

MeetingMetadata {
  title: NonBlankText | null
  startedAtUtc: UtcInstant | null
  endedAtUtc: UtcInstant | null
  timeZone: NonBlankText | null
  participants: MeetingParticipant[] | null
  participantListScope: "unknown" | "partial" | "complete"
}

ResolvedEvidence {
  ref: EvidenceRef
  speakerLabel: NonBlankText
  startMs: UInt
  endMs: UInt | null
  text: Text
}

MinutesItem {
  insightId: Id
  title: NonBlankText
  detail: NonBlankText
  ownerLabel: NonBlankText
  deadlineLabel: NonBlankText
  evidence: ResolvedEvidence[]
}

PreviewSection =
  {
    kind: "meetingInformation",
    metadata: MeetingMetadata,
    coverage: Coverage,
    freshness: "currentWindow" | "outdatedWindow"
  }
  OR {
    kind: "insights",
    category: Category,
    items: MinutesItem[],
    emptyMessage: NonBlankText | null
  }
  OR { kind: "warnings", items: Warning[] }

MinutesPreviewInput {
  meetingMetadata: MeetingMetadata
  context: Context
  validatedNotesResult: NotesResult
  finalizedTranscriptIndex: TranscriptEvent[]
  coverageStatus: Coverage
  freshness: "currentWindow" | "outdatedWindow"
  warnings: Warning[]
}

MinutesPreview {
  schemaVersion: 1
  context: Context
  notesRevision: UInt
  title: NonBlankText
  sections: PreviewSection[]
  warnings: Warning[]
  plainText: Text
  reviewRequired: true
  persisted: false
}

The caller binds metadata, notes and transcript index to the same trusted context. No previous-meeting metadata cache or inferred speaker attendance is used. participants=null requires participantListScope=unknown. A complete participant list requires an explicit trusted-provider assertion, not a nonempty array. Supplied start/end instants must be consistent. Missing title uses “Meeting minutes — draft.” [A0, D04; M1, D04.2]

Order the sections as Meeting information; Decisions; Action Items; Deadlines; Risks; Open Questions; Key Takeaways; warnings. Within each insight category, use the earliest supporting segment’s transcript order, then stable insight ID. Resolve speaker/time/text from exact current finalized segments rather than model-authored evidence. Missing owners display “Unassigned”; absent deadlines display “Not specified.” Empty sections say “Nothing identified in the available transcript.” [A0, D04; M1, D04.3]

An invalidated, failed or processing view cannot be shown as a current completed preview. Projection makes no additional model request. plainText stays in memory; content renders as text, never markup, commands or automatically opened URLs. Evidence navigation stays local. reviewRequired=true and persisted=false are invariant. The entire serialized preview, INCLUDING duplicated text in plainText and resolved evidence, is limited to 512 KiB; reject overflow without clipping evidence. [M1, D04; M2, D05.3]

D05. Accepted limits and overflow behavior
------------------------------------------

These are accepted application design limits, not Zoom limits or measured capacity. Both applicable count and byte ceilings must hold; an exact ceiling is allowed, but an addition that would exceed it is not. KiB=1024, MiB=1048576. Text budgets count original UTF-8 text bytes. Serialized-object budgets count CanonicalV1 UTF-8 bytes. Raw transport-byte enforcement before decoding remains Main’s adapter responsibility. [M2, D05]

Area: Transcript envelope
Count ceiling: —
Byte ceiling / time: 32 KiB
Outcome at an exceeding addition: Reject; do not replace previous content.

Area: Transcript text/event
Count ceiling: —
Byte ceiling / time: 8 KiB
Outcome at an exceeding addition: Reject; no truncation.

Area: Serialized session/control signal
Count ceiling: —
Byte ceiling / time: 32 KiB
Outcome at an exceeding addition: Malformed/oversized active-context control leaves ingestion blocked, not apparently authorized/listening.

Area: Retained current transcript
Count ceiling: 2,000 segments
Byte ceiling / time: 4 MiB original text
Outcome at an exceeding addition: Evict oldest in transcript order until both hold; disclose omissions and invalidate removed evidence.

Area: Queued updates
Count ceiling: 256 envelopes
Byte ceiling / time: 512 KiB
Outcome at an exceeding addition: Block ingestion; no silent drop/resume.

Area: Event / segment-revision identities
Count ceiling: 20,000 each
Byte ceiling / time: Shared budget below
Outcome at an exceeding addition: Block before excess; do not erase safeguards.

Area: Combined serialized auxiliary state
Count ceiling: —
Byte ceiling / time: 8 MiB
Outcome at an exceeding addition: Block before excess, including supporting side bookkeeping.

Area: Selected notes input
Count ceiling: 500 finalized segments
Byte ceiling / time: 256 KiB original text
Outcome at an exceeding addition: Newest contiguous suffix of finalized ordered input fitting both.

Area: Notes output
Count ceiling: 100 total; 25/category; 16 references/insight
Byte ceiling / time: 512 KiB result
Outcome at an exceeding addition: Reject whole oversized result, not clip.

Area: MinutesPreview
Count ceiling: —
Byte ceiling / time: 512 KiB entire preview
Outcome at an exceeding addition: Reject whole preview, including evidence/plainText cost.

Area: Connection/session operation
Count ceiling: —
Byte ceiling / time: 15 seconds
Outcome at an exceeding addition: Local invalidation; uncertain remote outcome is not undo.

Area: Notes operation
Count ceiling: —
Byte ceiling / time: 30 seconds
Outcome at an exceeding addition: Reject late completion; no automatic retry.

Area: C1 whole test suite
Count ceiling: Exact three planned test files
Byte ceiling / time: 120 seconds
Outcome at an exceeding addition: Runner-owned process/descendant handling; separately reviewed mechanism.

The 8 MiB budget covers the COMBINED event/segment histories, revision/finality safeguards, omission bookkeeping, gap records, warning aggregation and unreflected-reference bookkeeping. All supporting representations/side maps that preserve these facts are charged; there is no unbounded “outside the budget” map. Size accounting must use the actual agreed serialized representation, including counters, retained identifiers and repeated stored copies. A candidate’s state representation and exact boundary-fixture byte calculations must be reviewable; no runtime-capacity measurement is claimed here. [M2, D05.1]

Reserve bounded bookkeeping capacity to represent a blocked/error outcome without evicting replay/finality evidence. An attempted update is not committed if its combined required state would exceed a ceiling. Warnings/counters must not grow beyond the budget while reporting overflow. Stop admitting further input rather than silently dropping guards, wrapping counters or launching a new generation. Timeouts use explicitly injected orchestration outside pure processing; they do not read an implicit clock inside reducers. [M2, D05; A0, D05]

The 32 KiB control limit applies to serialized data envelopes such as SessionRequest, SessionReply, AuthorityUpdate and SessionSignal, not interface callback functions. Validation failure on the active owned control channel cannot preserve an apparently valid local listening permission. Keep the last confirmed remote snapshot distinct from the local blocked/error status. No rejected control message manufactures a stopped snapshot.

Counter and coverage definitions supplied for final reconciliation
------------------------------------------------------------------

These definitions fill the explicit omission/rejection-count request in Message 2. They are scoped to observable input and this accepted context, not to an entire meeting or provider traffic. They do not change the accepted limit values. [M2, D05.5]

For one accepted full context, let A be the set of distinct segment identities for which nonblank content has been accepted at least once; let R be the identities whose current accepted content is retained in the display window; let F be the identities in A whose highest accepted content is finalized, whether retained or evicted. Let S be the exact finalized source manifest selected for a particular notes request. Revision corrections do not create new segment identities.

Field: Coverage.omittedSegments, transcriptWindow
Exact consolidation definition: Current gauge: cardinality(A minus R). Counts known accepted identities absent from the retained display, not eviction operations, revisions, duplicates or estimated missing sequence numbers.

Field: Coverage.omittedSegments, notesWindow
Exact consolidation definition: At request selection: cardinality(F minus S). Counts known finalized identities excluded from that request, including evicted finalized identities. Provisional identities are not eligible and are reported separately.

Field: Coverage.provisionalSegments, either scope
Exact consolidation definition: Number of known identities in A whose highest accepted content is provisional: cardinality(A minus F), including evicted provisional identities whose guards remain. This is observed provisional material, not a meeting-wide number.

Field: Coverage.rejectedEvents
Exact consolidation definition: Cumulative count of rejected transcript-envelope deliveries examined on the current owned active-binding ingress boundary. One rejected delivery increments once, even if multiple fields fail. It is not a count of distinct lost utterances.

Field: Warning.occurrences
Exact consolidation definition: At least 1. Count of distinct processing outcomes that emitted that fixed aggregation key; at most one increment per key per outcome. Rendering/recomputation is not a new occurrence.

Field: NotesView.unreflectedSegments
Exact consolidation definition: Unique current finalized references accepted after the request was captured, outside its unchanged manifest. A later correction outside the manifest replaces the older unreflected reference for that identity; it does not append unlimited revisions.

Field: Coverage.knownCaptureGaps
Exact consolidation definition: Normalized cumulative accepted interval set, not a count inferred from sequence gaps.

For rejectedEvents, include malformed/oversized deliveries, full-context mismatches examined at the current boundary, semantic conflicts, prohibited finality downgrades and the delivery that triggers queue/history exhaustion. Exclude exact duplicate no-ops, stale ignored revisions, empty-event outcomes, valid provisional input, control-message failures and callbacks discarded before inspection because their subscription/epoch is already invalid or the intake is closed. A malformed delivery can be counted without retaining its payload or inventing an event identity. This count measures boundary rejection attempts, not membership in the authorized meeting; foreign text/IDs are not attached to the current transcript.

No separate de-duplication map is added for invalid deliveries. Consequently, separately delivered malformed envelopes count separately. Known duplicate valid events remain no-ops. A previously seen identity with inconsistent content remains a protocol conflict, even if its revision is stale. Rejection totals and warning totals need not match: one rejected delivery may emit more than one fixed diagnostic key. All such accounting remains within the combined budget.

The transcript omission gauge and provisional gauge can overlap when a provisional segment is evicted; they must not be added to claim a total. The notes omission gauge counts finalized exclusions, while its provisional count is a separate ineligible class. Existing exclusions at request creation are omissions, not later unreflected material. After capture, new finalized material outside S updates the unreflected list and freshness; it does not rewrite S or the result’s request-time coverage.

NotesResult.coverage is the immutable request-window provenance snapshot. Current workspace/preview coverage is separately recomputed from the same scoped rules and displayed with freshness. It does not erase the original result’s omissions or expand its manifest. On trusted rebinding, access loss or disposal, clear private state and start any new context’s counters independently; never roll old counts into a new meeting.

Every counter remains UInt. A counter or its serialized representation may not silently overflow or saturate as an exact value. If the next update cannot be represented within the numeric or byte ceiling, retain the last exact bounded state, block intake and mark coverage partial/blocked; do not claim a continued whole-stream count.

Observed range reconciliation. Keep Coverage.observedRange: TimeRange | null and TimeRange.endMs > startMs. Proposed conservative construction: derive a non-null range only when the represented retained/selected segments are nonempty, each has an explicit endMs, and the hull from minimum startMs to maximum endMs is nonempty. Otherwise use null. Do not fabricate an end time or add one millisecond to satisfy the type. This range describes observed source extents, not continuous coverage or meeting duration. A valid zero-duration TranscriptEvent therefore remains valid even when observedRange is null. This construction is supplied for Main’s final acknowledgment, not attributed to the original revision-1.1 text.

Coverage.completeness remains unknown absent a known deficiency and partial when known omission, rejection, provisional exclusion, capture gap or ingestion block affects the represented coverage. There is no complete value. Nonempty transcript, zero rejection count, maximum sequence and a populated preview never prove completeness.

Shared fixture expectations — specification, not executed tests
---------------------------------------------------------------

The six source sentences remain exact. The concrete context/receipt literals below complete the previously proposed fictional envelope for final reconciliation; they are not real meeting data or historical capture timestamps. [F, page 7; M1, D04.4]

Context for the six finalized events:
  tenantId = "fixture-tenant"
  userId = "fixture-user"
  agentId = "fixture-agent"
  sessionId = "fixture-session"
  meetingUuid = "fixture-meeting"
  streamId = "fixture-stream"
  generation = 1

schemaVersion = 1
segmentId = S1 ... S6
segmentRevision = 1 for each
eventId = "fixture-event-1" ... "fixture-event-6"
sequence = 1 ... 6
isFinal = true
source = "offline_fixture"
endMs is omitted
speakerId = "fixture-alex" or "fixture-morgan"
receivedAt = explicit values in the table, not a clock read

Segment / speaker / startMs / receivedAt: S1 / Alex / 10000 / 2026-09-12T13:00:10.000Z
Exact fictional transcript text: We agreed to keep the pilot notes-only.

Segment / speaker / startMs / receivedAt: S2 / Morgan / 20000 / 2026-09-12T13:00:20.000Z
Exact fictional transcript text: I will draft the pilot checklist.

Segment / speaker / startMs / receivedAt: S3 / Alex / 30000 / 2026-09-12T13:00:30.000Z
Exact fictional transcript text: The pilot checklist is due September 18, 2026, at 3 PM America/New_York.

Segment / speaker / startMs / receivedAt: S4 / Morgan / 40000 / 2026-09-12T13:00:40.000Z
Exact fictional transcript text: Unstable Wi-Fi is a delivery risk.

Segment / speaker / startMs / receivedAt: S5 / Alex / 50000 / 2026-09-12T13:00:50.000Z
Exact fictional transcript text: We still need to decide the retention period.

Segment / speaker / startMs / receivedAt: S6 / Morgan / 60000 / 2026-09-12T13:01:00.000Z
Exact fictional transcript text: Host approval is required before listening.

The baseline selects S1–S6 at revision 1 in that order, sourceThroughSequence=6. A=R=F=S contains six identities; omittedSegments=0, provisionalSegments=0 and rejectedEvents=0. No asserted gaps and no block imply unknown—not complete—coverage. With omitted endMs fields, the proposed observedRange rule yields null. S1 supports decision; S2/S3 support the Morgan-owned checklist and explicit deadline; S4 supports risk; S5 supports open question; S6 supports takeaway. Preserve America/New_York and the deadline wording, keep deadlineAtUtc=null and emit DEADLINE_UNRESOLVED. The fake generator validates plumbing/evidence, not real-model accuracy.

Exact canonical-byte examples. These are reference expectations, not an implementation test result. Literal backslashes below are part of the canonical serialization, not a second encoding layer.

CAN-01: Input object with z=1, a=2
Canonical: {"a":2,"z":1}
UTF-8 hex: 7b2261223a322c227a223a317d

CAN-02: Text value containing U+0022, U+005C, U+002F,
        U+0000, U+0009, U+000A, U+000D, in that order
Canonical: {"text":"\"\\/\u0000\u0009\u000a\u000d"}
UTF-8 hex:
  7b2274657874223a225c225c5c2f5c75303030305c7530303039
  5c75303030615c7530303064227d

CAN-03: String U+00E9 versus string U+0065 U+0301
First UTF-8 hex:  22c3a922
Second UTF-8 hex: 2265cc8122
Expected: different bytes; no Unicode normalization.

CAN-04: Object keys U+10000 and U+E000, each with value 1
Scalar key order: U+E000 first, then U+10000
Canonical UTF-8 hex: 7b22ee8080223a312c22f0908080223a317d

CAN-05: receivedAt input 2026-09-12T13:00:10Z
Canonical field value: 2026-09-12T13:00:10.000Z
Expected: same canonical field value as the .000Z input.

Fixture family: Omission/null/blank
Required expected outcome: Missing optional name and present blank name are semantically distinct but both display Unknown speaker. Present null rejects. Blank text never deletes or advances content.

Fixture family: Duplicate and receipt-only change
Required expected outcome: Transcript/accepted-revision/omission/rejection counters unchanged; no restored evicted text. A new event-ID alias must fit bounded history.

Fixture family: Foreign input
Required expected outcome: Reject without exposing foreign text or applying its content; rejectedEvents increments only if examined at the current active boundary. No manufactured segment ID.

Fixture family: Conflict-before-stale
Required expected outcome: Same known identity/revision with different content blocks context before stale dismissal.

Fixture family: Replay after display eviction
Required expected outcome: Exact replay is a no-op; established sequence/revision/finality remain. With A={S1,S2}, R={S2}, omittedSegments stays 1.

Fixture family: Unseen stale revision after eviction
Required expected outcome: Highest accepted revision 2 remains authoritative; a newly encountered revision 1 cannot restore content. Stale-ignore does not increment rejectedEvents.

Fixture family: Finality downgrade after eviction
Required expected outcome: Higher provisional revision cannot replace an accepted final one. Reject, retain finality, increment examined-rejection counter once.

Fixture family: Evicted segment correction
Required expected outcome: A valid newer final correction still checks preserved sequence/revision. Recompute bounded retention; count the identity once, not once per revision.

Fixture family: Manifest correction
Required expected outcome: Changing any manifest revision invalidates pending/current notes; an earlier generator reply cannot restore them, even if the corrected segment was not cited by one insight.

Fixture family: Outside-manifest arrival
Required expected outcome: Adding finalized S7 to unchanged S1–S6 notes records one unreflected reference and outdatedWindow; no manifest expansion.

Fixture family: Out-of-window real evidence
Required expected outcome: A real finalized S7 excluded from S1–S6 request is invalid evidence; reject result rather than drop the reference.

Fixture family: Provisional-only input
Required expected outcome: No generator call; noFinalizedInput, result=null. Known provisional count is nonzero.

Fixture family: Empty vs failed
Required expected outcome: Six empty arrays from valid finalized input produce empty; invalid evidence/provider failure does not masquerade as empty.

Fixture family: Counter gauges
Required expected outcome: With A={S1,S2,S3}, R={S2,S3}, all final, and notes S={S3}: transcript omitted=1; notes omitted=2; no whole-meeting total inferred.

Fixture family: Repeated malformed deliveries
Required expected outcome: Two separately examined malformed envelopes produce rejectedEvents=2 without retaining an invalid-event identity map. One delivery with multiple invalid fields increments once.

Fixture family: Late Start after acknowledged Stop
Required expected outcome: Stop at current revision yields stopped and terminal fence; older Start cannot activate the remote generation or local ingestion. A new Start needs a new trusted generation.

Fixture family: Stop conflict / timeout
Required expected outcome: Local intake blocks immediately. Conflict or timeout does not yield a false stopped snapshot, remote-undo claim or retry.

Fixture family: Pause resume / refreshed status
Required expected outcome: Successful explicit resume retains stream. Refresh/unsolicited listening status alone cannot reopen a locally blocked workspace.

Fixture family: Authority replacement
Required expected outcome: Old-subscription callbacks cannot grant access. Equal-revision conflict blocks; null context or loss clears private state synchronously.

Fixture family: Gap merge / equal revision
Required expected outcome: [10,20) plus [20,30) normalizes to [10,30). Same revision with equivalent normalized content is a no-op. Same revision with [10,31) conflicts.

Fixture family: Gap monotonicity
Required expected outcome: Older snapshot is stale. Newer [10,31) extends [10,30) legally; newer [11,30) retracts known coverage and conflicts.

Fixture family: Invalid active control
Required expected outcome: Malformed or >32 KiB control does not leave local ingestion authorized/listening; no false stopped claim.

Fixture family: Notes duplicate IDs/references
Required expected outcome: Duplicate evidence within an insight or duplicate computed IDs in a result reject; category/array mismatch rejects.

Fixture family: Deadline support
Required expected outcome: Absent deadline remains null without unresolved warning. Explicit named zone preserves text/zone without UTC conversion. Unsupported UTC value rejects despite valid syntax.

Fixture family: Preview freshness and overflow
Required expected outcome: Only valid ready/empty qualifies; revalidate evidence. Overflow caused by resolved text or plainText rejects the whole preview; no clipping.

Fixture family: Boundaries
Required expected outcome: One below, exactly at, and one above each count/byte limit; all other constraints kept valid. Combined auxiliary growth includes warnings/gaps/counters, not just replay maps.

For notes input, a 501-finalized-segment source under the text ceiling selects the newest 500 and reports one known finalized omission. For a byte-limited window, select the newest contiguous suffix after filtering to finalized ordered input; do not cherry-pick earlier shorter segments across a rejected suffix boundary. For size examples, canonical escaping can make a serialized envelope exceed its ceiling even when original text is within 8 KiB; both checks still apply.
