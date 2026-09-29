# Bookkeeping rebuild — 29 September 2026

This release reconstructs the missing K203H–K221 bookkeeping improvements from the saved acceptance checkpoints. It is a new implementation on the current published application, preserving the later Tax Prep integration and other features. It does not claim to recover the original unpublished commits or ZIP.

## Owner workflow

Open **Bookkeeping → Guide** for the eight-step path from business setup to reports and Tax Prep. Existing books and receipt originals stay in place.

- Add supporting documents to an active journal from **Accounts & journals → Supporting documents**. Receipt history remains available after correction or reversal. A receipt has at most one active cash-entry or journal attachment; attaching it does not post money.
- Preview a statement CSV before saving. Blank or zero unused debit/credit cells are accepted; conflicting, negative, malformed or zero-only rows are rejected. Repeated source rows and partial overlap with earlier imports need explicit review and an explanation. A fully repeated import is blocked.
- Open saved statements, review the recorded purpose, date, source, signed amount and exact record ID, then confirm a match. **Show more candidates** loads five at a time with a visible total. A changed ledger requires a fresh review. Reversed matches return to **Needs review**, with the previous decision retained.
- A lost response offers the same request for retry. Confirmed financial saves and scans temporarily guard navigation; a bounded timeout releases it. Closing an uncertain save refreshes the period of the attempted entry. Mileage keeps the chosen month/year scope and removes a vehicle filter after a confirmed attempt.
- Receipt scans recover the exact submitted scan; an older result cannot stand in for it. Preview loading is independent. Upload recovery uses the known receipt ID, and receipt-history read failures never appear as an empty history.
- CSV exports show errors and preparation feedback beside their controls. Native share anchors use the current layout after the export response. Journal and ledger exports include supporting-document references, without private file paths.

## Database rollout

Apply these additive migrations in order, then deploy the backend, then the frontend:

1. `20260929121715_bookkeeping_statement_review_rebuild.sql`
2. `20260929121726_bookkeeping_journal_evidence_rebuild.sql`
3. `20260929121737_bookkeeping_scan_recovery_rebuild.sql`

The statement overlap lookup is owner scoped, ordered, and bounded at 5,000 source matches; exceeding it returns an explicit limit error. Candidate pages require the same selected account, row, offset and ledger revision. PostgreSQL still authoritatively validates every confirmed match.

Journal evidence extends the existing receipt-link table with exactly one target per link, a same-business journal foreign key, immutable history, and a unique optional request key. Existing cash receipt links remain valid. RPCs and helpers remain unavailable to browser roles; RLS continues to deny direct access. Existing backend callers remain compatible with the extended schema.

If application rollback is necessary, deploy the previous backend/frontend commits. **Do not drop the new columns or delete financial, receipt, scan or statement history.** Old applications cannot present the newly added journal-evidence workflow; use a forward fix when that workflow has already been used.

## Validation

The backend suite passes **107 tests**, including a real PostgreSQL-compatible upgrade from the seven published bookkeeping migrations, old balance/evidence preservation, cross-owner and browser-role denial, direct-write guards, exact retries, 13 candidates, reversed matches, adjacent-year matching, and Tax Prep integration.

The **102 frontend tests** pass across the existing 59 bookkeeping tests, 23 rebuild/recovery tests and 20 Tax Prep tests. Coverage includes existing bookkeeping workflows plus exact scan and upload recovery, failed history reads, candidate paging and conflicts, guarded saves/timeouts, attempted-period refresh, CSV feedback, complete file reads, narrow layouts and large text. Final analyzer/build results and production commit/deploy identifiers are recorded in the deployment checkpoint.

Reproduction:

```sh
node --test --test-concurrency=2 backend/test/bookkeeping*.test.mjs backend/test/tax_prep*.test.mjs
CI=true FLUTTER_SUPPRESS_ANALYTICS=true flutter test --no-pub --concurrency=1 test/bookkeeping_test.dart test/bookkeeping_receipts_test.dart test/bookkeeping_ledger_test.dart test/bookkeeping_mileage_test.dart test/bookkeeping_reports_test.dart test/bookkeeping_statement_preview_test.dart test/bookkeeping_rebuild_test.dart test/bookkeeping_recovery_ui_test.dart test/tax_prep_test.dart
CI=true FLUTTER_SUPPRESS_ANALYTICS=true flutter analyze --no-pub lib/bookkeeping test/bookkeeping_rebuild_test.dart test/bookkeeping_recovery_ui_test.dart
CI=true FLUTTER_SUPPRESS_ANALYTICS=true flutter build web --release --base-href /app/ --no-pub
```

Use the locked dependencies and Flutter 3.47.5 / Dart 3.13.4. Set `KORLIX_FLUTTER_ROOT` for native test fonts and `KORLIX_BOOKKEEPING_PREVIEW` for fixture screenshots. Tests use synthetic records; no production financial fixtures, owner session, receipt scan provider or paid credits are used.

Real statement acceptance, original-file/provider scanning and physical-device share-sheet acceptance remain owner checks. This release does not add bank feeds, payroll, depreciation or electronic tax filing. Tax Prep remains a draft organizer linked to recorded books.
