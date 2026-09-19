# K135Z Track B checkpoint record - C1 static draft

Draft ID: `K135Z-KAI-C1-DRAFT-02`.
Predecessor: `K135Z-KAI-C1-DRAFT-01` (preserved without overwriting).
Revision request: `K135Z-MAIN-C1-STATIC-REVIEW-01`.
Source base: `2cd4ee37bfc450de8a61584ff9d2462efb1d9385`.
Design: `K135Z-KAI-CONTRACT-v1 / MAIN-DECISIONS-01`.
Design acknowledgment: `K135Z-MAIN-CONTRACT-ACK-20260912`.
Preparation specification: `K135Z-MAIN-C1-EXECUTION-SPEC-02`.

## Current status

This is a candidate TEXT submitted for static review. No candidate module was
imported, no Node syntax command was run and no project test was executed to
prepare this record. These eleven proposed file bodies have not been written
into the Codespace or its reserved worker worktree by Track B.

C0 remains open. C1 executable-package review and execution clearance are not
complete. No local C1 commit exists by virtue of this document. C2 and B5B
continuation remain separately gated. Main's reported V2 synthetic qualification
PASS is retained only within its reported scope, not as a C1 test pass.

## Static revision return: R1-R3

The frozen feature contract, exact base and eleven-file scope are unchanged.
No disagreement with R1-R3 is raised; these are implementation corrections
within the accepted baseline, not a contract amendment.

R1: aux.warnings keeps the aggregate historical NOTES_INVALIDATED record and
its occurrences. warningsForNewRequest creates a filtered presentation for a
fresh request only; it does not mutate the ledger or replay/finality stores.
The stored request copy is still charged by auxiliaryBytes. buildResult
requires a valid request and rejects an invalidation-bearing request rather
than concealing its current invalidity. New valid replacement results therefore
do not inherit the obsolete request warning. NO-24/NO-25 are the added tests.

R2: mergeWarnings checks occurrences before addition and raises a typed
LIMIT_EXCEEDED capacity error, not an unsafe increment. The transcript-state
owner catches that capacity error around the complete prospective reduction,
including empty-event and reconcileRequest warning work. Accepted capture-gap
updates have the same guarded boundary with delivery=false. On overflow, the
prospective update is not committed: prior guards, identities, source content,
gap snapshot, request and exact warning counts remain; the charged emergency
reserve supplies a blocked/partial outcome. An inspected transcript delivery
is counted once when representable; control processing never increments that
rejection counter. Existing rejected-delivery and finality guards remain.
TR-31 through TR-36 and NO-26 add explicitly seeded near-limit cases; they do
not simulate or assert a history of billions of deliveries.

R3: minutes labels append the exact supplied deadlineTimeZone in parentheses
only when that exact zone string is not already visible in the selected label.
The same label reaches plainText. No zone conversion or invented UTC instant
is introduced. MI-18 through MI-20 cover separate zone/text, the unchanged
fixture wording, and a supplied zone without a deadline instant.

Authored top-level declarations: 82 (36 transcript, 26 notes, 20 minutes).
All original 70 declarations and assertions are retained as byte-identical
prefixes of the three test-file bodies; the 12 new declarations are appended.
This inventory is not an executed or passing count. Runtime, 120-second suite
performance and actual candidate correctness remain unestablished.
CONTRACT_V1.md and fixtures/contract_v1.json are byte-identical to Draft 01.
The review manifest is an attachment, not a twelfth repository path.

## Warning-producing call-site review (static only)

- rejectDelivery: existing counter/warning work is under a typed-error handler
  and falls back to the reserved bounded block.
- Empty input and reconcileRequest: now covered by boundedOutcome around the
  entire prospective reducer update, before any new state is accepted.
- Finality rejection: retains its guarded warning/counter update.
- Accepted capture gaps: now guarded before committing gap revision/content;
  overflow keeps prior gaps and does not count a transcript rejection.
- emergencyBlock: uses non-incrementing merge for its terminal diagnostic and
  checks the actual auxiliary ceiling. Already-blocked intake stays closed.
- New-request warning projection and prepareNotes: do not increment historical
  warning counts. No historical invalidation is copied as current validity.
- buildResult: its result-warning assembly is caught by acceptNotes on failure;
  direct calls remain validation APIs that can return a typed exception.
  Request provenance is not mutated. This does not claim a transcript block
  from a notes-only validation function that returns no transcript state.
- reconcileNotes/projectMinutes: non-incrementing warning projections;
  result revalidation reconstructs from immutable request provenance, not from
  successively incremented result warnings. Their existing safe error outcomes
  remain. generateNotes supplies fresh fixed diagnostics, not an unbounded log.

No counter saturation, limit reduction, history erasure or uncharged side map
is proposed. The numeric and combined-byte limits remain unchanged.

## Exact C1 source allocation

backend/k135z_copilot_notes/contract.cjs
backend/k135z_copilot_notes/transcript.cjs
backend/k135z_copilot_notes/notes_processor.cjs
backend/k135z_copilot_notes/evidence.cjs
backend/k135z_copilot_notes/minutes_preview.cjs
backend/test/k135z_korlixai_transcript.test.cjs
backend/test/k135z_korlixai_notes.test.cjs
backend/test/k135z_korlixai_minutes.test.cjs
docs/k135z/korlixai/CONTRACT_V1.md
docs/k135z/korlixai/CHECKPOINTS.md
docs/k135z/korlixai/fixtures/contract_v1.json

## Static preparation versus execution

The separately supplied draft manifest hashes only the authored UTF-8 text.
It does not establish matching files in a Codespace, executable identities,
launcher hashes, tests passing, checkout clearance or a commit. Actual candidate
bytes and import closure must be checked again before an authorized test run.

All imports are literal. Modules use only the allocated modules and node:crypto.
Tests use allocated modules, node:test, node:assert/strict and the exact shared
JSON fixture. The test runner's internal child processes are not candidate code
spawning subprocesses. No subprocess import or real provider is present.

No assertion is deleted from the existing project. No test skip, todo, force-exit,
watch or rerun-failure option is proposed. Heavy history/window boundary cases
have not been timed; meeting the 120-second whole-suite limit is unproven.
A failure requires evidence and explicit review, not an automatic rerun or
weakening of a case. The result reporter remains the specified default spec
reporter; no TAP parser or hidden reporting preload is supplied here.

## Main-owned execution adapter still required

The designated future adapter location is:
/home/codespace/.k135z_korlixai_notes_ui_v1/c1_v1/execution_adapter.py

It is not a twelfth repository file, has not been created by this draft and has
no assigned content checksum in this record. Main supplies or explicitly reviews
its complete contents and Git effect integration. The qualification.py identity
must not be attached to another program or silently reused as a project runner.

Main's package must check non-root Codespace identity; the exact complete local
base/tree; executable/hook/filter/attribute identities and delegated Git LFS
effects; worker/branch/evidence collisions; free bytes/inodes and reserve; and
current protected state. No missing object fetch, skipped smudge, hook bypass,
permission/configuration weakening, pruning or cleanup is permitted.

Ordinary Git checkout/stage/commit needs its own reviewed offline/effect wrapper,
not the no-write project-test guard. Prevent unapproved automatic maintenance
without persisted settings changes or skipped hooks. Stage only these eleven
additions. Recheck their bytes after testing and before the single commit.

## Planned exact test invocation (NOT executed)

Executable: /usr/local/share/nvm/versions/node/v24.14.0/bin/node
Working directory: /workspaces/Ai-wiz-command-center-k135z-korlixai-notes-ui
Arguments:
--test
backend/test/k135z_korlixai_transcript.test.cjs
backend/test/k135z_korlixai_notes.test.cjs
backend/test/k135z_korlixai_minutes.test.cjs

The adapter must use an explicit non-secret environment, disable compile-cache
generation, apply inherited network/write restrictions before project code,
and account for/reap only owned descendants with one 120-second deadline.
No read-path-isolation or hostile-code-sandbox guarantee is asserted.

## Proposed evidence/output boundary (not created by this draft)

Root: /home/codespace/.k135z_korlixai_notes_ui_v1
Attempt: c1_v1/
Files:
execution_adapter.py
EXECUTION_PLAN.json
BEFORE.json
CANDIDATE_MANIFEST.json
PART1_READY.json
TEST_STARTED.json
tests.stdout
tests.stderr
TEST_RESULT.json
AFTER_TESTS.json
COMMIT_STARTED.json
COMMIT_RESULT.json
AFTER.json
RESULT.json
STOP.json (failure only)

Total evidence ceiling: 10 MiB. stdout: 1 MiB. stderr: 1 MiB.
No test-created temporary files are required. Only the supervisor writes evidence.
Overflow is failure/incomplete, never clipping followed by PASS. Preserve V1/V2
qualification locations, B5B records and every failed attempt. Collision means
STOP, not overwrite, deletion, suffix selection or retry.

## Later candidate results

PROJECT_TEST_EXECUTION=NOT_RUN
PASS_COUNT=NOT_ESTABLISHED
FAIL_COUNT=NOT_ESTABLISHED
ACTUAL_EXECUTABLE_AND_LAUNCHER_VERIFICATION=PENDING_MAIN_PACKAGE
CANDIDATE_RUNTIME_AND_IMPORT_VERIFICATION=PENDING_AUTHORIZED_RUN
WORKTREE_CREATION=NOT_PERFORMED
LOCAL_COMMIT=NONE

A static authored test inventory accompanies the review packet. It is not an
executed count. Main must verify all three files and all declared cases are
accounted for, with exit 0, no failures/cancellations/unexplained skips/todos,
no timeout/overflow/surviving owned processes, and unchanged candidate/protected
state within the stated scope, before recommending a commit.

## Planned commit and terminal failure behavior

Subject: feat(k135z-korlixai): C1 offline notes and evidence
Parent: the exact designated frontend base.
One local commit only after all required checks pass and Ricardo approves the
final cleared checkpoint package. Inspect actual commit paths, parent and worker
status. A Git/hook failure can occur after a checkout or commit took effect:
inspect/report actual HEAD and output; do not repeat, amend, reset, remove or roll
back automatically. Stop after C1 and return evidence before any C2 approval.

## Remaining work

Main reviews this draft, supplies/reviews the exact adapter and effects, and
closes executable-package clearance. Candidate-specific checks then occur in the
later-authorized package. C2 Flutter resolution, protected regression inputs,
UI lifecycle tests and shared application integration remain separate.
Planning baseline remains 8-14 focused implementation/validation hours after
execution gates clear, excluding coordination waits and setup remediation.
No reduction is inferred from authoring unexecuted draft code.
