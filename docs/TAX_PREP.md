# KORLIX Tax Prep — first release

## Purpose and scope
Tax Prep is a private U.S. calendar-year preparation organizer connected to KORLIX Bookkeeping. It helps a person gather records, review each linked business, and download a PDF or CSV handoff for a preparer.

This release does not calculate tax, refunds, estimated payments, deductions or credits, select a legally correct return, produce completed tax forms, or transmit returns. It does not include an e-file provider integration. All book amounts are recorded USD figures; net book results are not taxable income. The state selector records discussion topics, not supported state filing engines. The Schedule C source was the IRS 2025 instructions at release; it is not a 2026 rules engine.

## User workflow
1. Open **Tax Prep** from the home quick actions or Tools, or choose **Bookkeeping → Tax preparation** for a selected business/year.
2. Start one organizer for the calendar year. A personal organizer can exist without a business.
3. Mark document groups To gather, Organized or Not applicable. Record an expected filing status, states and preparer questions; these selections are unverified.
4. Choose **Link / refresh books** to select up to 25 owned businesses. Each entity has separate income, expenses, book balances, active mileage and receipt-link counts.
5. Review account classifications and supporting records. A Reviewed mark does not establish deductibility or filing readiness.
6. Save edits and explicitly download a PDF packet or CSV. Obtain general ledgers and original evidence separately from Bookkeeping.
7. If source records change, refresh and review the new snapshot before export.

## Data and correctness
- Uses the existing Bookkeeping reporting and mileage RPCs inside a transaction with sorted business locks; it does not post or modify financial entries.
- Income/expense accounts reflect annual recorded activity; cash/assets/liabilities/equity reflect recorded year-end balances. Reversals, year boundaries, owner contributions, borrowing and asset purchases retain the existing ledger treatment.
- Amounts use PostgreSQL integer cents and JavaScript/Dart BigInt, avoiding floating-point financial arithmetic.
- Every business stays separate, including partnerships, S corporations and C corporations. LLC legal structure does not determine tax treatment.
- Active mileage is distance only. Missing receipt links identify evidence to review, not disallowed expenses.
- A canonical source fingerprint plus audit revision detects changed entries, same-net corrections, business metadata, receipt links and mileage corrections. Changes in another period can conservatively require a fresh review.
- Refresh is explicit. Changed source records reset account review marks and retain notes for remaining accounts; an unchanged refresh retains review marks. Removing a linked business removes its snapshot and review notes.
- Export checks the workspace revision and current source fingerprint in a transaction. It is a verified snapshot at that moment, not a promise that subsequent records cannot change.
- Statement matching does not certify reconciliation. Completeness, inventory, depreciation, accruals, payroll, owner basis, fiscal years and jurisdiction-specific adjustments require separate review.

## Privacy and reliability
- Owner-scoped authenticated routes use the existing Bookkeeping session handling and no-store responses.
- Two new tables have RLS enabled with no direct browser grants. Security-invoker functions are executable only by the backend service role.
- Tables cascade on account deletion. Confirmed organizer removal deletes its snapshots, notes and request receipts while preserving Bookkeeping records.
- This version has no original-tax-form uploads or dedicated tax ID/bank credential fields. Users are asked not to put those details in notes.
- Tax Prep does not call an AI provider or use generation credits. No automatic external sharing occurs. Local downloads are explicitly requested; copies shared by the user cannot be recalled.
- Optimistic versions reject competing edits. Stable request keys deduplicate save/refresh retries; later revisions reject old replay attempts.
- Session changes remove private screen data/dialogs and prevent a late export from triggering a download.
- Notes are bounded; up to 25 businesses, 150 review accounts per business and 2,000 saved mutations per organizer are supported. Oversized snapshots fail atomically.
- CSV text neutralizes formula prefixes while preserving exact numeric amounts. PDF uses bundled fonts and includes scope, revision, snapshot and source-check provenance.

## API
All paths start with `/api/bookkeeping/tax-prep`.
- GET /: owned organizer summaries and business options.
- POST /: start or return the owner's organizer for a year.
- GET /:id: retrieve the snapshot and current staleness flag.
- PUT /:id: save bounded organizer fields with version and request key.
- POST /:id/books: explicitly confirm links/refresh with version and request key.
- POST /:id/export: validate current source and version, then return CSV or PDF packet data.
- DELETE /:id: confirm organizer deletion with expected version.

The additive migration is the single `*_tax_prep_workspace.sql` file in this release. Existing deferred Bookkeeping migrations must not be deployed as part of this feature.

## Release verification
Backend integration tests run the actual SQL migrations in PGlite and authenticated Express routes. They cover ownership, browser grants, calendar boundaries, exact large amounts, separate entities, financial-entry exclusions, reversals, retry/version conflicts, stale source checks, receipt links, mileage voids, CSV safety and preserving original books.

Flutter tests cover the Bookkeeping entry point, private session changes, save/refresh retry keys, unsaved edits, review notes, stale exports, explicit deletion, validated PDF/CSV downloads and 320/390/1440 px layouts at 125% text scale. The PDF fixture is rendered and visually inspected. Production Flutter build, migration/grant verification, live health and unauthenticated-route rejection are release checks. Tests use synthetic local fixtures only; no fabricated production financial records or owner impersonation.

## Next phase
Confirm target jurisdictions and return types, then select an authorized filing partner and its supported API workflow. A future release needs provider-specific onboarding, tax-year rules/form coverage, identity and consent requirements, signature/payment flows, submission acknowledgements and rejection handling. None of those capabilities are represented as enabled in this release.

## Primary references
- https://www.irs.gov/publications/p583
- https://www.irs.gov/instructions/i1040sc (2025 instructions at release)
- https://www.irs.gov/businesses/small-businesses-self-employed/business-structures
- https://www.irs.gov/e-file-providers/electronic-return-originator-ero-technical-fact-sheet
