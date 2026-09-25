# K201 — Accounts, journals and opening balances

KORLIX Bookkeeping 2027 now offers an **Accounts & journals** workspace from the bookkeeping dashboard. It adds owner contributions and distributions, borrowing and principal repayments, cash transfers, asset purchases, balance-sheet adjustments and opening balances. Every write has a review step and explicit confirmation.

## Accounting behavior

- Eight standard asset, liability and equity accounts are added to existing and newly created businesses. Owners can create named cash, asset, liability and equity accounts, up to 100 accounts total. Names are unique within a business (case-insensitive). Account names/types are immutable after confirmation.
- Guided transactions enforce account types at the database boundary. Asset purchases may credit cash or a liability. Principal repayments exclude interest and fees; those are recorded separately using the operating expense form. Tax classifications, eligibility and depreciation are not inferred.
- Opening balances and adjustments contain 2–100 distinct accounts. Each line has one positive debit or credit, with exact integer cents. Total debits must equal credits. The application never manufactures a balancing amount.
- One active opening document is allowed. Its closing date must precede all recorded operating activity and non-opening journals. Subsequent cash, receipt and journal entries must be dated after that closing date. Reverse an opening document before replacing it; original history remains. This is a starting-balance workflow, not annual closing or midyear income/expense carry-forward.
- Journals are immutable. A reviewed reversal swaps every debit/credit on the original date, requires a reason and appends an audit event. To correct details, reverse and then record a new journal. Reversal and replacement are separate deliberate operations.
- Recorded account balances are cumulative through the selected month end, including existing cash/receipt entries, journals, opening balances and reversals. Debit and credit balance sides are explicit. Balanced totals do not establish that records are complete or correctly classified.
- Journal history is monthly and paginated at 50 documents. The main dashboard still shows operating cash history/totals. Monthly combined CSV includes both histories and every debit/credit line, with original reversal references and timestamps; it explicitly errors above 10,000 lines. Sum debit/credit columns, including reversals. It is not a trial-balance or financial-statement export package.

## Current boundaries

Manual USD bookkeeping. Operating income/expense forms still post through Recorded cash control (1000); named cash accounts currently support transfers and journals. Selecting a bank account directly for operating entries is a follow-up before bank reconciliation. Private receipts remain associated with existing operating cash entries; attachments to the new journal documents are not yet supported. Mileage is separate and does not create accounting entries.

No bank connection, statement reconciliation, payroll, tax filing, depreciation, annual closing entries, automatic tax classification, complete P&L/balance sheet, or external accountant collaboration is claimed. Existing businesses should verify opening balances and classifications against prior records. A real-owner acceptance check and real-provider receipt scan acceptance remain outstanding.

## Data and privacy

Migration source `supabase/migrations/20260925062141_bookkeeping_ledger.sql` (created with Supabase CLI 2.101.0). Apply once as `bookkeeping_ledger`; remote migration timestamp may differ. The migration extends account constraints/metadata, backfills standard accounts, installs a new-business seed trigger, and adds `korlix_bookkeeping_journals` plus the combined `korlix_bookkeeping_all_lines` view.

Each journal stores its complete line array atomically in an immutable document. A database INSERT guard validates every line's canonical integer cents and same-business account existence/type, distinct accounts, balance, ownership and reversal fidelity. Accounts are immutable, so validated line references cannot be removed or retargeted. The same guard enforces opening cutover on the legacy entries table. Business row locks serialize posting, cutover and request replay checks. Invalid receipt posts roll back entry/link changes together.

The new table has RLS and no browser grants. The view uses `security_invoker=true`. RPC `korlix_bookkeeping_ledger_v1` uses SECURITY INVOKER and a fixed search path, with execution restricted to service_role. Service-role table grants are SELECT/INSERT, not UPDATE/DELETE; triggers also reject elevated edits/deletions. The server supplies the verified actor and checks business ownership before any data operation. Constraint row details are redacted. Routes are no-store.

Request keys make identical retries safe and reject altered reuse within the account or journal namespace. The client freezes reviewed payloads after a save attempt. Logout/account changes clear private views and nested forms and reject late responses/exports. Already-dispatched writes may finish; there are no automatic write retries.

Authenticated endpoints under `/api/bookkeeping/businesses/:id/ledger`: GET root, GET `/export`, POST `/accounts`, POST `/journals`, POST `/journals/:journal/reverse`. Reads take `month=YYYY-MM` and optional `offset`.

## Verification

- 63 backend tests passed across foundation, receipts, mileage and ledger. Actual migrations run in PGlite with service-role permissions. Includes backfill/new-business behavior, exact cents, all guided kinds, ownership/authentication, opening cutover, rejected receipt rollback, balanced atomic writes, concurrent identical replay, immutable history, exact reversals, combined CSV, pagination and export overflow.
- 44 frontend tests passed, including 10 ledger checks covering review/retry, mismatched opening totals, named account confirmation, reversal review, month/export behavior, duplicate opening prevention, 320/390/1280-pixel layouts in the actual theme, and nested logout. Existing bookkeeping/receipt/mileage regressions pass.
- Changed bookkeeping code and tests analyze with no issues. Node syntax and git whitespace checks pass. Release JavaScript web build passed in 62.2 seconds. The pre-existing optional Wasm warning in ua_client_hints remains. Production verification is required before marking deployed.
- Local SQL uses PGlite, which serializes connections; this is not a hosted concurrent-load test. Production is not populated with invented financial records for verification.

## Rollout and continuation

Publish tested feature commits, verify the public source tree/parent, apply the migration once, verify schema/grants/advisors, and fast-forward the existing backend release branch. Deploy backend and verify health/auth before releasing frontend. Both Render services have autoDeploy disabled. Preserve the additive migration and user history if reverting app code to K200. No infrastructure or billing changes are needed.

Remaining planned first-release estimate: **26–48 active working hours**. Ledger completion, reports and accountant exports: 8–14h; statement import/reconciliation: 6–12h; onboarding/accessibility/hardening/acceptance: 12–22h. This is a scope estimate, not an unattended timer. Funnel work remains paused.

References checked for implementation:

- IRS Publication 583, double-entry recordkeeping (balanced journals, ledger accounts and retained records): https://www.irs.gov/publications/p583 — see the Bookkeeping System section. No tax rates or deduction rules are encoded by this release.
- Supabase database functions: https://supabase.com/docs/guides/database/functions
- Supabase Data API privilege change: https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically — explicit grants/revokes are used.
- Supabase intentional server-only RLS/no-policy notice: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy
