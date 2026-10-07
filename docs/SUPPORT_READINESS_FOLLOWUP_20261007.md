# Support-readiness follow-up — October 7, 2026

**Overall checklist item: partially complete.** The owner confirmed they will handle support and identified Titan as the mailbox provider. Backlog review is complete. Mailbox access, backup/cadence, six remaining cases and full account-deletion fulfillment still need evidence.

## Completed

- Reviewed all 39 legacy reports and their seven distinct saved outputs through private access. Linked 32 exact duplicate submissions, closed one appropriate safety refusal without further action, and retained six uncertain cases as open. All original records remain; a private, service-only review ledger records the outcome and reasoning.
- Applied the review ledger migration with RLS and no browser privileges. Verified 39 review records, all original 39 report records, 32 exact duplicate links and six remaining open primary cases.
- Fixed the saved-history report action, which referenced an obsolete endpoint. It now uses the durable reporting route and asks for a reason/details while including the saved response context.
- All three report flows use one bounded request and reject repeated taps during submission. Automatic alias retries and new raw local pending-report writes were removed. Existing stored data is untouched. A successful receipt is required before showing success; ambiguous timeouts explain that the report may already be saved.
- Passed 12 focused client/dialog tests and the full selected 166-test Flutter release gate. New support code/tests analyze cleanly and main.dart has no analysis errors.
- Completed a local synthetic deletion rehearsal: 66 checks across request intake, selected storage cleanup, cross-user isolation, provider disconnection and the deletion dialog. Eight additional focused new SQL/rehearsal tests passed together. These counts overlap; they are not a cumulative distinct total.

## Remaining evidence

| Item | Current result | Needed to close |
| --- | --- | --- |
| Primary support contact | Owner confirmed “I will.” | Record practical review cadence and absence coverage. No ongoing automated monitoring or 24/7 staffing is implied. |
| Support mailbox | Titan routed the secure login through GoDaddy. GoDaddy displayed an unusual-browser block. | Verify actual inbox access and receipt handling through an approved supported path. This session did not read the mailbox or send a test email. The block is specific to this cloud browser; it is not proof the mailbox is unavailable. |
| Legacy follow-ups | Six cases remain open. Source research is complete for three sports responses and one enrollment-locator response; correction follow-up remains. One original-image evidence gap and one budget arithmetic/sourcing issue also remain. | Per-case evidence and resolution. Reviewing and deduplicating are not equivalent to fixing the original output. Private details remain in the ledger. |
| Complete account deletion | Intake and selected components are tested. Auth-only deletion leaves independent receipt bytes; immutable bookkeeping dependencies block a generic purge. | A controlled real-stack test account, complete per-account manifest, approved finance/shared-record retention decisions, feature/provider cleanup, and final verification. No production customer deletion was attempted. |

The backend branch contains the detailed records: `docs/LEGACY_REPORT_REVIEW_20261007.md`, `docs/SUPPORT_DELETION_REHEARSAL_20261007.md` and the updated operations runbook. Deployment evidence for the frontend change appears below and in `docs/SUPPORT_LIVE_VERIFICATION_20261007.json`.

No customer message, account deletion, privilege expansion, paid purchase or provider connection was performed during this work.

## Publication and live verification

- Frontend commit: `d7a71ef78035b76b19900e80e02cdbf5747a5ee9`.
- Render deployment: `dep-db3cqk5g1s2s739ttdeg`; live at **2026-10-07 22:55:49 UTC**.
- Render also passed the complete selected **166-test** Flutter release gate before building.
- At **2026-10-07 22:58:21 UTC**, the public app entry, Flutter bootstrap and compiled bundle returned HTTP 200. The bundle contains the new report-confirmation messages and durable reporting route. The backend health check returned HTTP 200 and healthy status; unauthenticated report-list access was rejected with HTTP 403.
- No signed-in production report was submitted during this verification. Client behavior is covered by the focused tests; static asset publication and the unauthenticated access boundary were checked live.
- Backend evidence commit: `61efefee0de33dae9f1c0cde5d505a0401fc6174`. It changes migration, tests and documentation only; the existing backend runtime was not redeployed.
- Source research for four remaining cases was added to the private review ledger. The cited regular-season records were verified; the sports issue concerns missing or stale playoff context. The location response needs an actionable official locator. All six cases remain open until resolution is recorded.

The backlog **review** and primary-support assignment can be marked complete. The combined support/deletion readiness item remains open for the evidence in the table above.
