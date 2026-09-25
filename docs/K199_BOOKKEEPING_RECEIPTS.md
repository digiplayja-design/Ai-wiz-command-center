# K199 — Private receipts and reviewed scanning

KORLIX Bookkeeping 2027 now supports a private receipt inbox, file/camera selection, original-file download, image preview, receipt-to-entry links, corrections with history, and optional AI field extraction. Open Utility → Bookkeeping 2027 → Receipt inbox. An entry's **Entry receipts** button shows present and previous associations.

## User workflow

1. Choose a JPG, PNG, WebP or PDF, or take a photo on a supported device. Confirm **Upload original**. The uploaded bytes are preserved; a separate image preview is generated.
2. Open **View / scan** to inspect an image preview or download the original PDF/image. PDF originals are served as downloads, never inline executable content.
3. Optionally confirm **Scan now**. The file is sent to the configured AI provider to suggest vendor, printed date, amount, currency, document type and payment status. No category, tax deductibility or ledger entry is inferred automatically.
4. Review all fields. Only positively identified USD amounts prefill the USD entry form. Verify the date money was actually paid/received, add a business purpose and category, check the receipt review box, then confirm the entry. An unpaid invoice is not proof of cash activity.
5. Alternatively attach to an existing eligible entry after a separate confirmation. **Correct link** requires a reason and retains the original association in history. Files ever used as evidence cannot be removed with **Delete unused**; a future retention/privacy workflow is separate from correcting bookkeeping history.

The 2027 name does not restrict recording to 2027. Existing business-profile and manual cash-entry behavior remains. This is an early-access USD cash-activity recordbook, not bank balance reporting, complete corporate accounts or tax filing.

## Limits and recovery

- Up to 8 MiB per file; still images up to 24 megapixels; unlocked PDFs of 1–10 pages. Scan PDFs of at most 3 pages.
- Originals and previews together count toward 250 MiB and 1,000 live/pending files per owner across businesses. Lists paginate at 30; entry selection at 50.
- Original hashes deduplicate within a business. Files use immutable object paths and `upsert:false`. Duplicate/lost object responses are accepted only after size and SHA-256 verification.
- A pending upload reserves quota and holds a 10-minute dispatcher lease. A retry during the lease returns pending and does not upload again. Once expired, the same file can resume with a new lease token. Incomplete unused uploads can be deleted after the lease expires. Storage transport is bounded at 45 seconds per request. Failed deletes remain retryable; quota is released only after confirmed storage removal.
- Deletion is blocked for an active scan and for any historical receipt link. No automatic evidence deletion occurs.
- Scan attempts use owner-bound request keys, one active attempt per owner, a daily attempt cap based on the existing plan request limit, and a five-minute stalled-job window. The provider request has a 90-second timeout and no automatic retries. Global in-process upload/scan concurrency is two each.
- All current plans pass the existing document-access helpers. Current daily usage/credit limits still apply. A successful extraction invokes existing accounting for one standard generation and one credit. Failed attempts still count toward the receipt attempt cap. A persistence failure after a completed provider call may consume a credit without a saved result; refresh status rather than blindly retrying.
- Existing cross-feature usage counters use legacy read/update accounting. This milestone does not claim globally atomic billing across concurrent unrelated features. The receipt attempt journal separately bounds dispatch.

## Data and privacy

Migration source: `supabase/migrations/20260925024651_bookkeeping_receipts.sql`. Check the actual remote migration record before applying; the remote tool assigns a different version timestamp. The K198 foundation migration is a prerequisite and must not be reapplied.

Tables: `korlix_bookkeeping_receipts`, `korlix_bookkeeping_receipt_links`, `korlix_bookkeeping_receipt_scans`. RLS is enabled, direct browser privileges revoked, service-role updates limited to state columns, and immutable triggers protect originals and history. The server-only SECURITY INVOKER RPC has a fixed search path and no anon/authenticated execution. Every operation validates the owner of the business and same-business references. Owner quota lock → business lock → receipt lock is the write lock order.

Bucket `korlix-bookkeeping-receipts` is private with MIME/size limits. A restrictive storage policy additionally prevents future permissive policies for other buckets from exposing these objects. No public or signed file URLs are returned to the browser. Authenticated backend endpoints download verified bytes with `no-store`, `nosniff`, attachment or image-only handling, sandbox CSP and noindex. Upload ownership is checked before multipart decoding. SQL errors that could contain row data are redacted.

Receipt + new ledger entry + association are committed in one SQL transaction. Retry keys cannot duplicate an entry. A receipt already linked elsewhere cannot produce another expense through this operation; its attempted ledger insert rolls back. Link correction preserves original actor/time/reason; reversed entries cannot receive a new active association.

OCR uses strict structured JSON with validated lengths, dates, amounts and currency syntax. The prompt treats document instructions as untrusted, uses no tools, and excludes addresses, tax IDs and card data from intended extracted fields. Model output remains untrusted suggestions. Provider `store:false` is set; do not interpret this as a universal provider zero-retention guarantee. The private scan journal stores suggestions; generation history does not receive copies of the financial document/extraction.

The client remains bound to issuer/user/session. Session replacement clears loaded records and previews, evicts preview images, closes nested dialogs, rejects late binary/upload results, and blocks further writes. An already dispatched server operation may finish; no background client retries occur.

## API additions

All routes are beneath `/api/bookkeeping/businesses/:id` and require authentication and business ownership.

| Method | Route | Behavior |
| --- | --- | --- |
| GET / POST | `/receipts` | Page metadata / upload one multipart `receipt` with `X-Receipt-Request-Key` |
| GET | `/receipts/:receipt/file` | Download immutable original |
| GET | `/receipts/:receipt/preview` | Private safe image preview |
| DELETE | `/receipts/:receipt` | Confirm deletion of unused original |
| POST | `/receipts/:receipt/link` | Confirm association with an existing entry |
| POST | `/receipts/:receipt/unlink` | Correct association with a reason |
| POST | `/receipts/:receipt/entries` | Reviewed new entry + receipt association atomically |
| GET | `/entries/:entry/receipts` | Full association history |
| GET / POST | `/receipts/:receipt/scan` | Status / explicitly confirmed extraction |

## Validation and release

35 backend tests cover the actual K198/K199 migrations in PGlite, local Express routes, original preservation, ownership, content validation, quota, upload recovery, history, atomic posting/retries, review acknowledgement, PDF limits, AI dispatch/usage boundaries and RLS/immutable grants. PGlite serializes its connection; this is not a hosted multi-connection load test. The provider is mocked in automated tests.

24 frontend tests cover the existing bookkeeping foundation and new multipart/binary session guards, retry identity, reviewed entry creation, foreign currency, explicit AI confirmation and lost-response recovery, original download, links/corrections, desktop/390px/320px layouts and nested logout cleanup. Changed module analysis and a release web build are required before publishing. Live verification checks the exact deployed commits, anonymous route rejection and matching public frontend bundles; no fabricated financial records are entered into production. A real owner receipt/provider acceptance run remains separate.

Deploy backend before frontend after applying the additive migration. Roll back application code to K198 if necessary, retaining the new tables/bucket and any user evidence; never drop history as routine rollback.

## Remaining planned first release

Mileage; expanded ledger entry types and opening balances; reports and accountant export packages; statement import and reconciliation; onboarding, accessibility and release hardening. Bank feeds, payroll, tax filing and external accountant collaboration remain outside the current estimate. Funnel work remains paused.
