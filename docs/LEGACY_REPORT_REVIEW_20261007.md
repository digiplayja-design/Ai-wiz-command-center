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

## Production review completed October 7, 2026

The owner requested this review. At 22:48 UTC, a guarded transaction recorded all 39 original reports: 32 exact duplicates linked to their primary reports, one reviewed appropriate safety refusal requiring no action, and six cases requiring follow-up. The duplicate and no-action entries moved to `resolved`; the six primary follow-ups remain `new`. All 39 original records remain. Exact duplicate equality includes reporter, generation, reason and details. A subsequent read verified all 32 links. No customer communication, content removal, suspension or account deletion occurred.

The six remaining cases concern three date-sensitive factual outputs, one location/source follow-up, one missing original image artifact, and one budget arithmetic/sourcing review. They are not marked fixed. Private per-case notes remain in the restricted ledger; customer identifiers and report text are intentionally absent from this document.

Migration `20261007224627_legacy_report_review_ledger` is applied. Live metadata confirms RLS and no privileges for `anon` or `authenticated`. Security advisors returned no WARNING or ERROR findings (one INFO). This establishes the narrow ledger access check, not comprehensive security certification.
