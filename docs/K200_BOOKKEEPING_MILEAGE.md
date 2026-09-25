# K200 — Business mileage log

Open Utility → Bookkeeping 2027 → **Mileage log**. Owners can record a trip date, vehicle nickname, starting place, destination, business purpose and either miles driven or starting/ending odometer readings. Every trip requires a review and explicit confirmation before it is saved.

Distances use exact integer tenths of a mile. Trip distance must be 0.1–9,999.9 miles; odometer readings must be 0–9,999,999.9, with ending greater than starting. Dates support 2000–2099, including valid leap dates. This is a manual miles-only log: no GPS, automatic route calculation, distance conversion, reimbursement, mileage rate, tax deduction or cash entry is generated. Business purpose and classification are owner supplied; the app does not determine eligibility.

## History, totals and exports

A saved trip cannot be edited in place or deleted. **Correct trip** creates a replacement and excludes the original in one transaction, requires a reason and preserves both records. **Void trip** records an exclusion with a reason. Both require a separate confirmation. A changed date or vehicle can affect different periods/filters. The UI refreshes to the saved trip's period and clears the vehicle filter so the result is visible. Corrected/voided records remain in history and contribute zero to included miles. A replacement may itself be corrected; old chain members cannot be corrected again.

Month (`YYYY-MM`) and year (`YYYY`) queries support an exact vehicle nickname filter. Give each vehicle a distinct, consistent nickname; names are snapshots on each trip, not a vehicle registry. The recent-name hint shows up to 100 distinct names, while the text filter accepts any existing exact name. There are 50 records per history page. Summary totals cover the complete selected period/filter, not just the page.

CSV exports contain up to 5,000 records for the selected period/filter, including excluded history, recorded distance, included distance, method, odometer values, trip IDs, original/replacement IDs, reason and timestamps. Sum **Included distance (mi)** for the active total. **Recorded distance (mi)** includes excluded history and must not be summed as active mileage. Above 5,000 records the API fails clearly; narrow the period or vehicle. Fields are quoted and formula-like text is neutralized. CSV exports are owner-initiated downloads; an exported copy leaves the app's private storage.

## Database and security

Additive source migration: `supabase/migrations/20260925055030_bookkeeping_mileage.sql`. K198 bookkeeping foundation must already exist; do not reapply it. Verify actual remote version/name before applying K200 because the migration tool assigns its own timestamp.

- `korlix_bookkeeping_trips`: immutable snapshots with exact generated distance, same-business original reference, unique request key and correction reference.
- `korlix_bookkeeping_trip_voids`: immutable exclusions with unique original, optional same-business replacement and correction reason.
- `korlix_bookkeeping_mileage_history`: SECURITY INVOKER view exposing safe trip/exclusion fields and included distance.
- `korlix_bookkeeping_mileage_v1`: SECURITY INVOKER RPC with fixed search_path and no anon/authenticated execution. Service role only. Every action validates business ownership and serializes through the business row lock.
- Both tables enable RLS and revoke browser access. Service role has SELECT/INSERT only, with no UPDATE/DELETE. Triggers reject in-place history changes even with elevated SQL privileges, verify business ownership and same-trip replacements; a deferred constraint trigger requires every replacement to have its matching exclusion before commit.
- A correction inserts replacement and exclusion together. Invalid replacements roll back, leaving the original active. Same-key requests return the saved outcome; changed reuse, wrong actions and cross-business references are rejected. Request payloads and keys are excluded from the history response.
- Audit events append `mileage_post`, `mileage_correct` or `mileage_void` to the existing audit table. Cash ledger entries and totals are unaffected.

Authenticated routes inherit the existing no-store wrapper. Raw SQL constraint details are redacted. The UI uses the existing issuer/user/session-bound client: logout clears mileage data, controllers and nested forms, and late responses cannot restore records or trigger a download. Already dispatched server writes may finish after the session changes. Lost-response retries preserve the same reviewed payload/key; no automatic writes occur.

## API

All routes are under `/api/bookkeeping/businesses/:id/mileage` and validate the authenticated business owner.

| Method | Suffix | Purpose |
| --- | --- | --- |
| GET | empty | Month/year history, included totals and vehicle hints |
| POST | empty | Record a reviewed trip |
| POST | `/:trip/correct` | Atomically replace and exclude original |
| POST | `/:trip/void` | Record a reviewed exclusion |
| GET | `/export` | Full filtered CSV, up to 5,000 records |

Read/export query fields: `period`, optional `vehicle`, optional list `offset`. Post body: `request_key`, `confirmed:true`, `trip_date`, `vehicle`, `origin`, `destination`, `purpose`, `method:'miles'` with string `miles`, or `method:'odometer'` with string `odometer_start`/`odometer_end`. Corrections add `reason`; voids need only key, confirmation and reason. Normalized integer tenths stay server-side.

## Verification and release

48 backend tests pass across foundation, receipts and mileage, using actual migrations in isolated PGlite and local Express. New checks cover exact parsing, date/distance validation, owner isolation, concurrent replay, monthly/year/vehicle totals, pagination, atomic cross-period corrections, rollback, voids, immutable history, deferred correction pairing, CSV safety and export overflow. PGlite serializes its connection; this is not a hosted multi-connection load test.

34 frontend tests pass across the foundation, receipts and mileage. New checks cover decimal arithmetic, reviewed creates/retries, odometer validation, corrections, exclusions, filtered exports, dashboard navigation, phone/desktop layouts and nested logout cleanup. Require clean changed-module analysis and a release web build before publishing. Production checks verify migration security, deployed commit identities, health, anonymous route rejection and public bundle markers. Do not fabricate production trips as a smoke test; real owner acceptance remains separate.

Publish backend and frontend feature branches; apply the additive migration; deploy backend before frontend. Existing Render services and billing settings remain unchanged. Rollback app code to K199 if needed; preserve the additive tables and user history.

Next: expanded journal entry types/opening balances, accounting reports/accountant export packages, statement import/reconciliation, onboarding and release hardening. Funnel work stays paused. Live bank feeds, payroll, tax filing and external accountant collaboration remain outside the current first-release estimate.
