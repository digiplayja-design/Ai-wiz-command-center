# K202 — Cash-account selection and recorded financial reports

KORLIX Bookkeeping 2027 now lets owners choose a cash account when recording operating income or expenses, including reviewed receipt entries. The dashboard's Reports workspace adds month/year recorded profit and loss, balance sheets, trial balances and CSV exports. This builds on K201; historical K201 limitations are superseded only where described here.

## Recorded accounting behavior

- Operating entries default to Recorded cash control (1000). Named cash accounts are scoped to the selected business and can be created in Accounts & journals. The choice appears in entry review/history and activity CSV. Reversals retain the original cash account and date. Returning from the ledger refreshes choices on the dashboard.
- Existing request history is immutable. Omitting cash_account or explicitly supplying 1000 produces the pre-K202 canonical request, so an old lost response can be retried. A different account under the same key conflicts. Receipt posting still creates the entry and evidence association atomically, with the same opening-date guard.
- Profit and loss sums recorded income credits minus debits, and expense debits minus credits, for the selected month or calendar year. Owner funding, distributions, debt principal, transfers and capital assets are balance-sheet movements, not operating income/expenses.
- The balance sheet uses all recorded lines through the selected period end. Assets minus liabilities equal booked equity plus recorded unclosed earnings. Prior-calendar-year and current-calendar-year-to-date earnings are shown separately and are not added to booked equity twice. Annual closing journals are not generated; calendar labels do not select a business's tax or fiscal year.
- Trial balances show beginning balances, period debit/credit movements and closing balances, using exact integer cents throughout SQL/JavaScript/Dart. Accounts retain negative or credit balances rather than converting them to misleading positive assets. The CSV includes all accounts; the screen omits entirely inactive accounts.
- Opening balances represent an initial cutover, not a midyear operating-profit carry-forward. Reports identify missing opening balances, periods before/including cutover, zero-activity periods and any imbalance. Reversed documents remain in history and offset at their original dates, so historical reports are recomputed from current recorded corrections.
- Balancing does not establish completeness, correct classifications, reconciliation or tax readiness. These are owner-supplied manual USD records. No bank feed/reconciliation, accruals, depreciation, automatic tax calculation/filing, payroll or external accountant collaboration is performed.

## Exports

Reports export as UTF-8 BOM CSV with business identity, USD currency, period, generation timestamp, opening-date metadata and scope/warnings. Profit/loss and balance sheets list accounts and totals; trial balance provides separate beginning/period/closing debit and credit columns. Text formula prefixes are neutralized; trusted numeric cells retain exact negative values.

General-ledger CSV contains every recorded line in the period, document IDs/dates/types/descriptions, account codes/names/types, exact debits/credits, reversal references, timestamps and currently linked receipt IDs/filenames/SHA-256 hashes. Receipt metadata repeats on each cash-entry leg and reversals refer to original evidence. Original files stay private in the receipt inbox; they are not embedded. Journal attachments are not implemented. Period ledger exports above 50,000 lines fail explicitly and instruct the owner to choose a shorter period; financial totals are not truncated.

## API, migration and privacy

Authenticated, no-store GET endpoints:

- `/api/bookkeeping/businesses/:id/reports?period=2027` (or `2027-01`).
- `/api/bookkeeping/businesses/:id/reports/export?period=2027&kind=profit_loss`; other kinds: `balance_sheet`, `trial_balance`, `ledger`.

Apply source `supabase/migrations/20260925152053_bookkeeping_reports.sql` once as `bookkeeping_reports`. It replaces the original cash-only entry constraint with validated operating legs, strengthens the immutable INSERT guard to check account kinds, updates the existing cash RPC without rewriting history, and adds the owner-scoped reporting RPC. Existing K201 cutover guards and journal/account immutability remain. No new tables or storage buckets are added.

`korlix_bookkeeping_reports_v1(uuid,uuid,jsonb)` is SECURITY INVOKER with a fixed search_path; execute is revoked from public/anon/authenticated and granted to service_role. The server binds p_actor to the authenticated owner; business row locks serialize reports with financial/receipt mutations. Reports perform reads only and create no audit events. SQL failure internals are redacted. The client clears private reports on session change and rejects late financial responses/downloads.

## Validation and rollout

- 73 backend tests pass against actual migrations in isolated PGlite with service-role privileges. Covers pre-migration replay, selected/foreign/noncash accounts, receipt atomicity/evidence references, cutover, financial identities, prior-year/current-year boundaries, leap dates, large exact totals, negative values, CSV formula defenses, privacy, read-only behavior and 50,000-line overflow, plus all existing bookkeeping regressions.
- 52 Flutter tests pass, including report filtering/export behavior, stale-data removal and retry, selected-account review/replay, receipt-account submission, refreshed choices, late-export session privacy, and 320/390/1280-pixel report layouts in the actual theme. Screenshots were rendered and inspected. Changed bookkeeping code/tests analyze cleanly; Node syntax and git whitespace checks pass.
- Release JavaScript web build passed in 60.6 seconds. Flutter 3.47.5 / Dart 3.13.4; dependency locks unchanged. Existing optional ua_client_hints Wasm dry-run warnings do not block the JavaScript target.
- Publish tested source, verify public trees and parents, apply migration and check grants/advisors, then fast-forward/deploy backend and verify health/auth routes before the frontend. Existing Render services have autoDeploy disabled. Production commit IDs, deployment IDs, migration version, bundle hashes and checks are recorded in the K202 checkpoint after rollout.
- Authenticated behavior is tested with isolated fixtures; no invented financial records are added to production. Real-owner acceptance, real-provider receipt scanning and hosted multi-connection load checks remain outstanding. Existing unrelated Supabase advisor findings are tracked separately, not claimed fixed.

## Next work

First-release estimate: **22–42 active working hours**: remaining ledger/evidence and report usability 4–8h; statement import/reconciliation 6–12h; onboarding/accessibility/hardening/acceptance 12–22h. This is a scope estimate, not an unattended countdown. Bank feeds, payroll, tax filing and external accountant collaboration are outside this estimate. Funnel and Meta work remain paused.

Next milestone: statement CSV import with explicit field mapping, validation/duplicate handling, account/date/amount matching, reviewed reconciliation and an auditable correction path. Finish journal evidence and acceptance before claiming complete books or launch readiness.

References checked: IRS Publication 583 (https://www.irs.gov/publications/p583), SEC financial statement guide (https://www.sec.gov/investor/pubs/begfinstmtguide.htm), Supabase database functions (https://supabase.com/docs/guides/database/functions), and Supabase explicit Data API grants (https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically). No tax rates or deduction rules are encoded.
