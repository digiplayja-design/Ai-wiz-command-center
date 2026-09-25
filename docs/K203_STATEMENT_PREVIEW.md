# K203A — Statement CSV preview

Owners can select a business cash account, choose a UTF-8 bank statement CSV and explicitly map date, description and either signed amount or separate debit/credit columns. The read-only preview checks up to 500 rows and suggests recorded cash-account entries with the same exact integer-cent amount and a date within three days. Duplicate statement rows and multiple candidates are flagged for review; invalid dates and amounts stay visible as errors. Nothing is imported, posted, reconciled or persisted.

The endpoint is `POST /api/bookkeeping/businesses/:id/statements/preview`. It requires the existing authenticated bookkeeping owner and returns no-store. CSV is limited to 256 KiB; the owner-scoped K202 reports RPC supplies the recorded candidate lines. It does not accept bank credentials or contact a bank. Only the selected owner's cash account can be matched. The annual report's 50,000-line cap still applies. Every response is advisory: equal amount and nearby date do not prove two records represent the same transaction.

K203A intentionally has no database migration. It creates no statement storage or reconciliation state. The next K203 phase must provide durable imports, duplicate handling across earlier imports, owner-confirmed one-to-one matches and an auditable correction path before showing any item as reconciled. Do not use preview suggestions as a bank balance or financial statement completeness claim.

Backend focused parser and real PGlite route tests pass; Flutter CSV mapping and existing dashboard tests pass. No real bank statement or authenticated owner journey has been exercised. Existing K202 accounting paths and migration stay unchanged.
