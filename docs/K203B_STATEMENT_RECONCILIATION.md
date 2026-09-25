# K203B reviewed statement imports

Current behavior update: K203G permits documented, owner-confirmed repeated rows within one CSV. See `K203G_REPEATED_STATEMENT_ROWS.md`. The K203B duplicate restriction below describes the original release.

K203B saves reviewed, normalized CSV statement rows and lets the business owner record explicit matches to existing cash journal movements. It does not connect to a bank, post financial entries, change balances, or certify a bank reconciliation.

## Import

- Choose a CSV of 1–500 rows (up to 256 KB), a calendar year, distinct date/description/amount columns, and a named cash account. Signed amounts or separate debit and credit columns are supported. Dates must use `YYYY-MM-DD`, amounts are exact USD cents, and all rows must belong to the selected year.
- Preview possible cash movements before confirming. Invalid and duplicate rows within the file block import. Confirmation stores normalized date, description, signed cents, original line number, account, year, source SHA-256 digest, actor, and time. The original CSV bytes are not retained.
- A retry with the same request key and identical normalized request returns the saved import. Importing the identical source digest returns its existing import when its mapping and account agree. A changed request conflicts. An overlapping row with the same date, signed amount, and case-insensitive description on that account and year is conservatively blocked across imports; review saved statements if this happens. Legitimate repeated bank transactions with identical details require a separate resolution before they can be imported.

## Match and correction

- Saved statements show rows, current candidate suggestions and the complete decision history. The owner explicitly confirms each match. The existing journal line must use the selected cash account, equal signed cents, and a date within three calendar days. Reversals and reversed originals are excluded. One active statement row can hold each journal entry.
- Correcting a match requires an explicit reason and appends an unmatch decision referencing the prior match. The owner can then review a replacement. Neither imported rows nor decisions may be edited or deleted. Every successful action is audited.
- Request keys make lost-response retries safe. A reused key with changed data conflicts. Requests and underlying SQL both enforce owner scoping; browser roles have no table or RPC access. Business row locks serialize overlapping decisions and imports.

## Operational verification

Migration: `supabase/migrations/20260925163933_bookkeeping_statement_imports.sql`. Backend routes: `GET /api/bookkeeping/businesses/:id/statements`, `GET /:statement`, `POST /import`, `POST /:statement/rows/:line/match`, and `POST /:statement/rows/:line/unmatch` under the statements prefix. Existing `POST /preview` remains read-only.

Run `node --test backend/test/bookkeeping*.test.mjs`. Test real SQL against a local PostgreSQL-compatible database; check idempotency, immutable rows and corrections, cross-owner access, and browser grants. Deploy the migration before backend and frontend. Owner acceptance still needs real bank exports and a check against statements and books. This feature does not compute cleared balances or completeness of reconciliation.
