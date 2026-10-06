# THE RECEIPT WIZ

Free, authenticated receipt scanning and storage. Home has a standalone entry
in the personal tools section and finder; it does not wait on the paid-feature
lookup. Separate Scan and Receipts tabs provide capture and private history.
The web camera uses the rear lens by default, occupies the available screen,
requests no microphone, stops on backgrounding/account change/disposal and keeps
the smoke screensaver inactive while a camera frame is available. Native builds
use the platform camera. A zoomable photo review precedes upload.

JPG, PNG, WebP and PDF originals are preserved. The service accepts one receipt
file at a time, up to 8 MB (PDF: up to 10 pages). OCR follows the existing OpenAI
consent flow and can be declined; manual receipts remain available. Automatic
merchant, date, total, subtotal, tax, tip, category, description and item text
are suggestions. Users review and correct the original, choose a date with a
calendar, add an optional purpose, and mark the result reviewed or save it for
later. Failed reading never removes the original. Exact file duplicates reuse
the existing receipt; reviewed saves warn about another merchant/date/total
match. Search, category/year/review filters, pagination, original download and
CSV export are included. Export keeps filters and neutralizes formula cells.

After either reviewed saving or saving for later succeeds, a persistent footer
offers **Scan next receipt** and **View receipts**. Continuous scanning reopens
the camera, including from an existing or connected inbox, without accumulating
review routes. Canceled capture returns to the inbox. Pending, failed, dirty or
expired-session states cannot advance; back navigation is blocked during a save.
Receipt items are editable one per line (40 maximum, 180 characters each), and
rescan results carry their own items and warnings. Refreshing a pending rescan
can recover its suggestions without losing the stored original. Dates, amounts
and currency receive inline validation, including on partially completed saves.
Reset filters restores the connected inbox's initial year and preserves its
workspace scope. Tapping the vault lock explains that receipts use the current
Korlix account sign-in; there is no separate vault password or PIN.

Bookkeeping's dashboard and receipt library, and Tax Prep's selected year, have
an embedded entry to the shared Receipt Wiz inbox. These views read the same
private record, not detached copies. Correcting a receipt updates every inbox.
Tax Prep includes undated receipts for explicit review. Backend checks the
ownership of any passed business or organizer. Existing finance workspaces are
reported as connected; creating one later also makes earlier receipts available.
Receipts remain unassigned evidence: this integration does not automatically
post ledger entries, choose a business for an expense, or claim tax deductions.
Tax Prep's existing book snapshots and packet exports retain their own workflow.

All plans receive the same 100 AI scan attempts/day (UTC), with no AI GAS or
paid generation credits consumed. The private vault allows 1,000 receipts or
250 MB; manual entry is available after the daily scan allowance is exhausted.
Upload keys, file hashes, upload leases and scan keys prevent duplicate work.
Scans have a three-minute recovery window; a late scan cannot overwrite edits.
Version checks prevent stale manual saves. Account changes clear rendered
private data and reject late responses. Removing an original removes it from
all shared inboxes; downloaded copies are separate.

Backend: `backend/receipt_wiz`. Database: `korlix_receipt_wiz`, scans and daily
usage, plus a private `korlix-receipt-wiz` bucket. Service-role-only RPCs perform
owner checks and serialized quotas. Direct browser table/function access is
revoked; RLS and explicit restrictive deny policies are enabled. Storage has
its own restrictive policy. No public original URLs are generated.

Validation: the Flutter suite covers the new flow, existing receipt and
Tax Prep screens, home catalog/navigation, 320px/390px phones, landscape,
1024px tablets and enlarged text. This includes manual fallback, duplicates,
corrections, CSV scope and session replacement. 45 backend checks cover actual
SQL/RPC behavior in PGlite, HTTP routes, ownership, private storage grants,
upload/delete recovery, scan expiry, quotas surviving deletion, safe CSV and
existing finance regressions. Provider replies and media permissions are mocked;
physical camera capture and live-provider OCR need a signed-in device check.
Follow-up coverage includes a continuous two-receipt session, failed/pending
save protection, next scanning from an existing inbox, vault access explanation,
item/scan-note corrections, invalid dates, scoped filter reset and the saved
footer on narrow phones, landscape and enlarged text.
Changed Dart code and tests pass static analysis. Phone/tablet renders reviewed.

```bash
CI=true flutter test --no-pub test/receipt_wiz_test.dart test/home_tool_catalog_test.dart test/bookkeeping_receipts_test.dart test/tax_prep_test.dart test/home_navigation_test.dart
```

Optional UI exports: set `RECEIPT_WIZ_PREVIEWS` to a scratch folder and
`KORLIX_FLUTTER_ROOT` to the SDK folder. Publishing the web build does not update
already-installed iOS/Android binaries; those require their own release builds.
