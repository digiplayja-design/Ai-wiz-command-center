# Account deletion rehearsal — October 7, 2026

**Result: local intake and selected cleanup paths verified; complete account fulfillment is not yet verified.** No production account, customer file, report, subscription, provider connection, or email was created, changed, deleted, or sent by this rehearsal. The new files are tests and this record, not an automatic deletion service.

## Evidence

| Check | Result and boundary |
| --- | --- |
| Real deletion HTTP route and shared authentication guard into the deployed SQL migration | Passed using synthetic users and PGlite. User/email come from verified identity, not submitted fields. Repeated requests produce one pending record. Anonymous intake is rejected. Database failure does not return success. A request does not delete the account or receipt files. |
| Controlled Receipt Wiz sequence | Passed with real feature routes/SQL and a local byte store. A failed object removal leaves the receipt in `deleting` and the support case `requested`. Disabling the account prevents client access; service-only, owner-scoped feature commands can still finish operator cleanup. Original and preview bytes are removed before the account row. A second user's receipt and access remain intact. |
| Auth-only deletion limitation | Reproduced deliberately: Receipt Wiz metadata cascades, but the two independently stored object byte streams remain. This expected test result documents an incomplete deletion, not successful fulfillment. |
| Bookkeeping dependency limitation | Reproduced with the actual foundation migration and business-creation RPC. Direct Auth deletion is blocked by a foreign key. Removing the business is blocked by dependencies; removing audit history is blocked by immutable-history protection. No triggers, constraints, or retention safeguards were bypassed. |
| App Studio portal files | Existing real SQL/HTTP tests pass for account cascade into durable cleanup, object removal, stale portal-session rejection, failed-removal retry, and abandoned-upload cleanup. Storage is simulated. |
| Receipt Wiz and Bookkeeping receipt controls | Existing tests pass for deletion failure/retry, active-scan fences, quota release after successful removal, and preservation of evidence previously linked to ledger entries. These are feature-level controls, not a complete account purger. |
| Social media | Existing tests pass for delete/profile-cascade cleanup of Discover media, voice attachment cleanup records, and immediate access removal. Storage is simulated; shared recipients and moderation evidence still need case-specific decisions. |
| FieldProof | Existing tests pass for cancellation of waiting emails after deletion, durable PDF cleanup after job/account cascade, storage acknowledgment before clearing references, and garbage-collection acknowledgment. No real email is sent. |
| YouTube / Live Studio | Existing tests pass for local credential and API-data removal, queued-show handling, retention sweeps, and rejection of late writes that would restore deleted data. Provider HTTP responses are simulated. Failed revocation is reported as unconfirmed, not claimed successful. |
| In-app request dialog | Eight Flutter tests pass, including honest request-only wording, retry after timeout, session changes, and small-screen access. This is not a live-device or mailbox test. |

### Executed checks

Five new rehearsal cases and 17 existing intake/auth checks passed (22 total):

```sh
node --test \
  backend/test/account_deletion_rehearsal.test.mjs \
  backend/test/account_deletion_rehearsal_bookkeeping.test.mjs \
  backend/test/support_intake_database_security.test.mjs \
  backend/test/final_auth_security.test.mjs
```

Thirty-six selected existing cleanup/retention/provider checks passed:

```sh
node --test --test-concurrency=2 \
  --test-name-pattern='deletion|delete|cleanup|disconnect|revocation|late worker|grants|retention' \
  backend/test/app_portal.test.mjs \
  backend/test/receipt_wiz.test.mjs \
  backend/test/bookkeeping_receipts.test.mjs \
  backend/test/live_studio_retention_sql.test.mjs \
  backend/test/live_studio_connections.test.mjs \
  backend/test/social_discover.test.mjs \
  backend/test/social_wall_voice.test.mjs \
  backend/test/fieldproof_email_database.test.mjs \
  backend/test/fieldproof_email_service.test.mjs
```

In the authoritative frontend checkout, eight UI tests passed:

```sh
flutter test test/account_deletion_dialog_test.dart
```

Total: **66 passing checks**. Tests that deliberately reproduce an incomplete-deletion boundary count as evidence of that boundary; they do not certify erasure. PGlite runs actual PostgreSQL SQL locally, while Auth, object storage and provider services use synthetic adapters. Production Supabase Auth, physical cloud-object deletion, delivery of customer notices, and provider-side erasure were not exercised.

## What is required to close the fulfillment item

1. Assign the person handling verified deletion requests and the backup reviewer. Verify access to the real support inbox and the restricted request queue.
2. Use an explicitly identified disposable test account in the real or isolated staging stack. Seed representative enabled feature families and record an owner-scoped manifest of database dependencies, originals/previews/derived files, scheduled work, and provider connections. Do not use a customer account or assume a Storage `owner_id` search finds every server-uploaded file.
3. Approve the retention/transfer decisions for organization-owned records, posted bookkeeping/tax evidence, shared Social records, billing records and safety evidence. Bookkeeping's current immutable records require a reviewed retention/de-identification or fulfillment implementation. Broad cascades or disabling its guards are not an acceptable shortcut.
4. Execute the existing feature cleanup paths and provider disconnections under controlled operator access. Pause jobs and prevent new writes; revoke applicable sessions. Store only minimal case evidence. An unconfirmed provider revocation or failed file removal keeps the corresponding action open for retry.
5. Verify every manifest item and any retained exception, remove Auth only after its dependencies are handled, then test that the old session cannot use protected operations. Mark the request completed and send the completion notice only after the full case is actually fulfilled.

The app currently has a secure request queue plus feature-specific cleanup components. It does **not** have one complete account/storage/provider purger, a complete cross-feature erasure manifest, or a tested solution for all retained finance dependencies. A manual support process can remain appropriate, but its actual completion must be demonstrated before this checklist line is marked fully done.

## Current provider guidance checked

Supabase's changelog was checked for relevant changes. Its current [User Management documentation](https://supabase.com/docs/guides/auth/managing-user-data) states that removing an Auth user does not immediately invalidate issued JWTs and that owned Storage objects can prevent Auth deletion. Its [Storage ownership documentation](https://supabase.com/docs/guides/storage/security/ownership) explains that service-key uploads do not automatically carry the end user's `owner_id`. This is why fulfillment must inspect application references and bytes as well as Auth rows.

See also [the operations runbook](WEB_LAUNCH_OPERATIONS_20261007.md). This record establishes local technical evidence; it does not establish staffed support coverage or legal retention determinations.
