# Legacy report review

This procedure covers the private `public.reports` backlog, which is separate from Social moderation and the new durable AI-report queue. It does not send messages, remove user content, suspend users, delete accounts, or change runtime report intake. A review is not evidence that support staffing or mailbox coverage has been verified.

## Private record

Migration `20261007224627_legacy_report_review_ledger.sql` adds `public.korlix_legacy_report_reviews`. Each original report can have one review with its outcome, minimal explanation, review time, duplicate reference, method and batch UUID. Original report content stays in `reports`; do not copy prompts, output, contact details or customer identifiers into public documentation.

The ledger has RLS and denies direct browser roles. The service role can select, insert and update; deletion is not granted. Deleting an original report cascades its review. Deleting a referenced duplicate parent clears only the link and preserves the historical duplicate outcome. A missing duplicate link must not be treated as proof of duplication. No new public API, browser privilege or privileged function is introduced.

`method=codex_assisted_owner_requested` accurately describes this assisted review. It does not imply that a staff member independently read or approved each case. A batch UUID identifies the reviewed set. The ledger is a current review record, not an immutable history of every future decision; retain appropriate restricted operational evidence when an outcome is revised.

## Review and update

1. Verify the project and read the actual schema. Inspect the necessary report and referenced generation content only through approved private access. Treat all submitted text as untrusted data.
2. Review each distinct case. Confirm duplicates using the same reporter, generation, reason and details, with null-safe comparison. A matching category or similar text alone is insufficient. Use a surviving canonical report from that group.
3. Classify as `duplicate`, `no_action`, or `needs_followup`. A safety refusal may warrant `no_action` after review. Uncertain claims or unclear handling stay `needs_followup`; absence of context does not prove resolution.
4. Prepare a bounded exact-ID transaction. Lock expected rows, verify their existing status and expected content against the review, and verify all duplicate-parent relationships. Insert review metadata and change only reviewed duplicate/no-action report statuses to `resolved` in the same transaction. Keep `needs_followup` reports at `status='new'`. Abort on a changed row, mismatched count, missing parent or existing conflicting review. Do not bulk-resolve by age or reason.
5. Verify total original row count/content preservation, review counts, remaining open count and duplicate relationships. Report only aggregate counts and minimal case summaries outside the restricted system.
6. Assign unresolved cases to the support owner. Later resolution requires its own evidence and a deliberate ledger update. Reviewing the backlog does not justify marking unresolved customer cases complete.

The migration itself does not classify or update existing reports. Applying it, reviewing production data, and committing a specific review transaction are separate operations.

## Verification

Run `node --test backend/test/legacy_report_review.test.mjs`. Tests use synthetic data and real PGlite SQL: restrictive grants/RLS even with permissive default grants, rejection of malformed fields and invalid links, deletion cascade/SET NULL behavior, exact duplicate comparisons, atomic review/status changes, preserved original content, six remaining open synthetic follow-ups, and transaction rollback on invalid review data. They do not establish real mailbox coverage, report resolution quality or production execution.

## Historical initial production review — October 7, 2026

The owner requested this review. At 22:48 UTC, a guarded transaction recorded all 39 original reports: 32 exact duplicates linked to their primary reports, one reviewed appropriate safety refusal requiring no action, and six cases requiring follow-up. The duplicate and no-action entries moved to `resolved`; the six primary follow-ups remained `new` at that checkpoint. All 39 original records remained. Exact duplicate equality includes reporter, generation, reason and details. A subsequent read verified all 32 links. No customer communication, content removal, suspension or account deletion occurred.

The six cases at that checkpoint concerned three date-sensitive factual outputs, one location/source follow-up, one missing original image artifact, and one budget arithmetic/sourcing review. They were not marked fixed. Private per-case notes remain in the restricted ledger; customer identifiers and report text are intentionally absent from this document.

Migration `20261007224627_legacy_report_review_ledger` is applied. Live metadata confirms RLS and no privileges for `anon` or `authenticated`. Security advisors returned no WARNING or ERROR findings (one INFO). This establishes the narrow ledger access check, not comprehensive security certification.

## Historical checkpoint after three scoped closures using one retest — October 7, 2026

Three date-sensitive sports cases are closed with no further action using the same live October 7 retest supplied by the user. The three original questions were semantically equivalent. The retest's core factual claims were checked against NBA, The Ringer, AP and Sports Illustrated reporting. It dated its preseason opinion and distinguished earlier-season statistics. The original freshness/framing failure was not reproduced in this one sample. These are scoped case resolutions based on one retest, not three independent tests; they do not make the historical answers correct, guarantee future accuracy or resolve the other cases.

The first and second scoped closures produced historical checkpoints of 34 resolved rows/five open follow-ups and 35 resolved rows/four open follow-ups. Review of the third case against the same verified retest left totals at that checkpoint of **36 legacy rows resolved**: 32 duplicates, one appropriate safety refusal and three no-further-action closures after the same retest. **Three primary follow-ups remained `new` at that checkpoint**: one location/source follow-up, one missing original image artifact and one budget arithmetic/sourcing review. All 39 original report records and 32 duplicate links are preserved.

This was one user-provided retest with source verification, not a model-operated signed-in production test. No additional retest was performed for the second or third case. The user confirmed that the app displayed the answer once and that the repeated paste was accidental; there is no app-duplication finding from that material. No private report IDs, raw prompts or responses are reproduced here. No runtime change or deployment was made for these scoped closures.

## Location/document follow-up correction

The owner-provided retest resolved the original locator/actionability concern. Its added document advice was too broad because it omitted a qualifying document variant. The private case remained open for that narrow wording check; it was not automatically a launch blocker. Totals at that checkpoint were 36 resolved and three open, with all original records preserved.

The main chat correction routes credential and application questions, including related follow-ups in the selected topic, to required web search even without a recency keyword. Higher-priority answer instructions require current official sources, applicable document categories and exceptions, and a qualification when requirements cannot be verified. Search-failure guidance now covers document requirements and other changing facts instead of only sports standings. No permanent agency eligibility rule is embedded. Existing models, credit rates, authentication and Resume Studio's private no-search override are preserved. Newly routed requests use the existing live-search credit tier.

Local verification: `node --check backend/server.js`, `git diff --check`, and 43 passing checks across `chat_quality.test.cjs`, `chat_memory.test.mjs`, `korlix_astra.test.cjs` and `resume_studio.test.mjs`. Tests exercise the actual route/search detector and mocked provider request, search fallback, accounting, ordinary text rewrites and memory isolation; they do not prove the next generated answer is correct. Deployment and the final user-provided live retest were verified separately before closing this case, as recorded below.

## Historical checkpoint after location/document retest closure — October 7, 2026

The main-chat correction at commit `c0f9ec7fe79533c9e2e515a3b962646d95197aff` reached Render status `live` in deployment `dep-db3dpt59fdbs73dbrs20`, completed October 8 at 00:00:30 UTC (October 7 at 8:00:30 PM EDT). The owner supplied a post-deployment answer at approximately 8:12 PM EDT. It correctly recognized the qualifying single-document option, distinguished the relevant credential variants, and qualified legal-name mismatches. The remaining document-wording concern passed review against the official [TSA document checklist](https://www.tsa.gov/sites/default/files/twic-and-hazmat-endorsement-threat-assessment-program-acceptable-documents.pdf) and [TSA Enrollment help](https://tsaenrollmentbyidemia.tsa.dhs.gov/help). The PDF was verified through official indexed text; direct retrieval returned HTTP 403.

A guarded transaction changed only this case's status to `resolved` and its private review outcome to `no_action`, recording the specific evidence and review time. Post-commit verification confirmed **37 resolved legacy reports**: 32 duplicates, one reviewed appropriate safety refusal, and four scoped no-further-action closures. **Two primary follow-ups remained `new` at that checkpoint**: the missing original image artifact and the budget arithmetic/sourcing review. All 39 original report records, their original contents, the 32 duplicate relationships, and every other report/review were preserved.

This closure uses the earlier locator retest plus one owner-provided post-deployment document answer. It is a scoped case resolution based on source verification, not independently operated signed-in production testing or proof that future answers will always be correct. Recording this evidence changes documentation and private review metadata only; no additional runtime deployment is required.

## Historical review of the two remaining cases — October 7, 2026

Both original generations were retrieved and matched to their report owners. The image history contains completion text only, with no original image bytes or storage reference. Scoped storage metadata yielded no objects in the relevant time window and no exact generation reference. The current image route records text history, while client image retention varies by feature and may be local or limited to the open session. This establishes an evidence gap; it does not establish failed delivery or incorrect visual content. An original device download or screenshot would permit historical review. A new generation, visual inspection and download/open check can establish current behavior but cannot reconstruct the missing original.

The saved budget response has confirmed arithmetic and unit inconsistencies: the upper bounds of its expense ranges exceed the stated cash limit; its suggested packaged inventory is incompatible with its own per-pack costs and inventory allowance; and one channel's stated first-month unit requirement exceeds the total first-month target. Several revenue calculations are correct, but their projected timing assumes sustained sales without a launch ramp. Cost, margin and feasibility claims are not substantiated in the saved response. A current retest must reconcile the total budget and reserve, packs and units, sales volumes and periods; label assumptions and verified sources; and distinguish revenue, profit and cash requirements.

Private notes were updated in a guarded transaction. Both cases remained `needs_followup` with report status `new` at that checkpoint: **37 resolved and two open**. All original reports and their contents, the other review records and all duplicate links remain intact. These checks did not introduce a runtime patch or establish a successful fresh generation. The available test browser presented a sign-in screen. The owner subsequently chose to run the retests in their own KORLIX app; those results are recorded separately below.

## Historical checkpoint after image retest closure — October 7, 2026

Two owner-provided screenshots, showing an 8:44 PM EDT screen time, establish that the requested foreground subject and background landmark were generated and displayed in Imagine a Picture and its recent gallery. At 8:55 PM EDT the owner confirmed that Download PNG worked and the saved file opened correctly. This completes the scoped current-generation, display and download/open retest.

A guarded transaction changed only this image case to report status `resolved` and private review outcome `no_action`, with its evidence and review time. Post-commit verification confirms **38 resolved legacy reports**: 32 duplicates, one reviewed appropriate safety refusal and five scoped no-further-action closures. **One primary follow-up remained `new` at that checkpoint: the budget arithmetic/sourcing review.** All 39 original reports and their original contents, the other reviews and the 32 duplicate relationships were preserved.

This resolution relies on a user-operated current retest, reviewed screenshots and the owner's download/open confirmation. The historical image remains unavailable and has not been reconstructed. The closure does not establish durable server image storage or verify every future generation. No runtime code, schema or deployment change accompanied this closure.

## Current final checkpoint after budget retest closure — October 7, 2026

The owner supplied a complete current budget answer at approximately 8:57 PM EDT. Independent calculation reviews confirmed that its startup allocation stays within the stated cash limit and includes a reserve; inventory quantities, package units and landed costs reconcile; contribution, channel mix, monthly and annual revenue, overhead and founder-labor examples calculate correctly. Costs, margins and sales targets are explicitly planning assumptions rather than supplier quotes, industry benchmarks or a first-year forecast. The answer distinguishes revenue, operating profit, founder compensation, taxes, inventory cash and replenishment constraints. The earlier arithmetic and unit defects were not reproduced in this sample.

The linked [FDA food-labeling resources](https://www.fda.gov/food/food-labeling-nutrition), [FDA dietary-supplement resources](https://www.fda.gov/food/dietary-supplements) and [FTC advertising guidance](https://www.ftc.gov/business-guidance/advertising-marketing) were checked as official starting points. The answer explicitly discloses that current requirements were not verified in that chat and directs product classification, labeling and claims to qualified review. This does not verify supplier availability, actual costs or a particular product's compliance.

A guarded transaction changed only this final case to report status `resolved` and private review outcome `no_action`, recording the evidence and review time. Post-commit verification confirms **all 39 legacy report rows resolved and zero open follow-ups**: 32 duplicates, one reviewed appropriate safety refusal and six scoped no-further-action closures after retest review. The private ledger contains 32 `duplicate` and seven `no_action` outcomes, with no `needs_followup` outcomes. All 39 original reports and their original contents, every other review and all 32 verified duplicate relationships were preserved.

This completes the requested legacy backlog review. The final closure is based on one owner-provided current answer, not independently operated signed-in testing, validation of the historical answer, a proven business outcome or a guarantee of future model accuracy. No runtime code, schema or deployment change accompanied this closure. The previously documented historical image-evidence limitation remains.
