# K198 — KORLIX Bookkeeping 2027 foundation

Status: first implementation milestone, early access. This is a working manual USD cash recordbook, not the complete bookkeeping release. Funnel work remains paused; no Meta/Google configuration, funnel campaigns, follow-ups, or owner tests are part of K198.

## What business owners can do

Sign in at https://www.korlixdeveloper.com/app/, open Utility, then **Bookkeeping 2027**.

- Create separate private business profiles (maximum 25 per owner).
- Record legal structure separately from federal tax treatment. LLCs can record an S/C corporation treatment; receiving contractor/1099 income is a separate flag. Choosing a treatment in this app does not make a tax election.
- Record money received or paid for business operations, with date, exact USD amount, category, customer/vendor, business purpose, and optional receipt/invoice reference.
- Review an entry before saving. Repeated submission of the same reviewed request uses one request key and creates one entry.
- See monthly recorded income, expenses and net activity, with pagination at 50 entries.
- Reverse an incorrect entry with a reason. The original remains, an equal offset is posted on its original date, and that month's totals change. Create any replacement as a separate reviewed entry.
- Export up to 5,000 entries for the selected month to CSV; a larger month produces an explicit error rather than a partial export. CSV includes original and reversal identifiers and journal account codes. Do not sum the unsigned Amount USD column as net activity: reversal rows are offsets and the debit/credit account columns identify direction.

Bookkeeping early access is available to authenticated users, scoped to the owning user; K198 adds no billing charge or subscription entitlement change. It adds one Utility entry and leaves existing feature entitlements intact.

## Explicit first-milestone limits

- USD manual cash activity only. No bank connections, opening balances, account reconciliation, accrual accounting, invoices/bills, payroll, inventory, foreign currencies or tax filing yet.
- The optional receipt reference is text, not an uploaded file. Receipt attachment, capture and OCR are the next milestone.
- Loans, owner contributions/distributions, transfers and capital assets require additional entry types; users are told not to record those as operating income/expenses here.
- Dashboard net activity is not a bank balance or a complete profit and loss statement. Expense categories do not establish deductibility; no 2027 tax rates or legal/tax guarantees are implemented.
- No joint access/accountant sharing, closed periods, editable journal entries, or in-app business deletion. Immutable history and owner foreign keys require a reviewed retention/deletion workflow before adding account deletion for businesses with records.
- Native CSV uses the system share sheet; web uses a local download. No export is sent to another person automatically.

## Backend and migration

New files: `backend/bookkeeping/core.mjs`, `routes.mjs`, `backend/test/bookkeeping_foundation.test.mjs`.

Migration generated with Supabase CLI 2.101.0: `supabase/migrations/20260925015926_bookkeeping_foundation.sql`. Apply once using the migration tool. Its timestamp is the generated local filename; record the actual remote migration version in the deployment checkpoint.

Tables: `korlix_bookkeeping_businesses`, `accounts`, `entries`, `audit`. The prefix `korlix_bookkeeping_` applies to all four. `korlix_bookkeeping_journal_lines` is a security-invoker view over two equal journal legs per entry. The immutable entry row stores one debit account, one credit account and one positive integer-cent amount, so a partial or unbalanced pair cannot be saved. Cash control is an internal recorded-activity account, not a bank balance.

`korlix_bookkeeping_v1` is SECURITY INVOKER with a fixed search_path and server-only execution. All four tables have RLS enabled; anon/authenticated roles have no table/view/function access. The verified server derives p_actor from the existing auth helper; request bodies never set ownership. Each business RPC checks owner_id before reading or writing. Profile saves use optimistic versions and audit before/after; transaction writes use business row locks, canonical idempotency payloads, uniqueness constraints, immutable-history triggers and composite foreign keys. The service role has no UPDATE/DELETE grant on journal entries, accounts or audits and only specified profile-column UPDATE grants.

Money enters the API as decimal strings, converts with BigInt to cents, and is stored as bigint. Per-entry maximum is $9,999,999,999.99. Aggregate numeric totals return cents as strings; Flutter formats BigInt values without floating-point loss. Browser/HTTP error responses never include raw constraint rows. CSV text cells escape quotes/newlines and neutralize formula prefixes.

Routes, all authenticated and Cache-Control: no-store:

- GET/POST `/api/bookkeeping/businesses`
- PUT `/api/bookkeeping/businesses/:id`
- GET `/api/bookkeeping/businesses/:id/overview?month=YYYY-MM&offset=0`
- POST `/api/bookkeeping/businesses/:id/entries`
- POST `/api/bookkeeping/businesses/:id/entries/:entry/reverse`
- GET `/api/bookkeeping/businesses/:id/export?month=YYYY-MM`

## Frontend

`lib/bookkeeping/` provides a responsive navy/cyan dashboard, business setup, reviewed entries, corrections, export, exact money formatting and a route-scoped authenticated client. The client pins issuer/user/session identity, accepts refresh within that session, invalidates on logout/user/session replacement, rejects late private responses, and removes listeners on disposal. Auth loss clears records and closes open forms. Tokens are not used as proof of identity on the client; server authentication remains authoritative.

Failed entry saves retain the same immutable reviewed payload and request key. Users can retry it or close and refresh. Successful entry saves navigate the dashboard to the entry's month. Profile updates use version conflicts; after an ambiguous successful update a retry may conflict and the user should close/refresh.

## Verification

- 16 backend tests run against the actual SQL migration in PGlite plus local Express HTTP routes: owner isolation, auth, profile version audit, money/date validation, balanced journals, concurrent HTTP replay, month boundaries, reversals, immutable history, forged SQL rejection, RLS/grants, CSV escaping and pagination. PGlite serializes its SQL connection; this does not claim a multi-connection hosted load test.
- 12 frontend tests: exact BigInt formatting, token refresh, late-session response rejection, setup, stable retries, reviewed posting, reversals, CSV handoff, desktop/390px/320px layouts, sign-out cleanup and selected-month behavior.
- `flutter analyze lib/bookkeeping test/bookkeeping_test.dart`: no issues. Shared main.dart has the same 217 baseline diagnostics, with no added diagnostics; these unrelated pre-existing diagnostics were not changed.
- Focused frontend regression suite: 33 tests passed across Bookkeeping, existing funnel session boundaries and the app widget smoke test.
- Web release build passed in 62.9 seconds. The existing ua_client_hints dependency reports an optional Wasm dry-run incompatibility; the JavaScript release build succeeds. Deployment results are recorded in the K198 checkpoint.
- Production verification is read-only/unauthenticated HTTP plus schema checks. No fabricated production financial records are seeded. Actual ledger journeys use isolated local fixtures.

Commands:

```sh
node --test backend/test/bookkeeping_foundation.test.mjs
KORLIX_FLUTTER_ROOT=/tmp/korlix-flutter flutter test test/bookkeeping_test.dart --reporter expanded
flutter analyze lib/bookkeeping test/bookkeeping_test.dart
flutter build web --release --base-href /app/
```

## Remaining estimated work after this milestone

Estimated active development effort: **44–80 hours**, not a scheduled/background countdown and not a guaranteed deadline.

| Next work | Estimated hours |
| --- | ---: |
| Private receipt uploads, capture, OCR review and transaction matching | 10–18 |
| Mileage logs and supporting records | 4–8 |
| Additional ledger entry types, opening balances, reports and accountant exports | 12–20 |
| Statement import and reconciliation | 6–12 |
| Onboarding, accessibility, release hardening and end-to-end verification | 12–22 |
| **Total** | **44–80** |

Live bank feeds, tax filing, payroll and external accountant collaboration are outside this first-release estimate. OCR must preserve the original file and require review of extracted dates, amounts and categories before posting; it must use existing provider authorization/metering controls.

Background: IRS recordkeeping and business-structure guidance informed the separation of receipt evidence, business purpose, legal structure and tax treatment. The app does not implement tax advice:
- https://www.irs.gov/publications/p583
- https://www.irs.gov/businesses/small-businesses-self-employed/business-structures
- https://www.irs.gov/faqs/small-business-self-employed-other-business/entities/entities-3

## Rollback

Rollback application code to the preceding published backend K196 / frontend K197 commits if needed. This migration is additive and can remain in place. Do not drop or mutate the new bookkeeping tables if an owner has started recording data; preserve immutable history. No existing migration or funnel schema was modified.
