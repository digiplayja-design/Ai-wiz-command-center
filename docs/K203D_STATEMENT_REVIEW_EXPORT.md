# K203D saved statement review CSV

Owners can export one saved statement at `GET /api/bookkeeping/businesses/:id/statements/:statement/export`. The route calls the existing private, owner-scoped `get` RPC and emits a UTF-8 BOM CSV in JSON (`filename`, `csv`, `scope`). There is no new database write or migration.

The file identifies the statement and cash account, carries K203C counts and signed totals, then lists imported rows with current match status and entry ID. A second section records every decision in chronological order with decision ID, line, action, linked entry, corrected decision, reason and timestamp. This is a review artifact, not an original bank statement or proof of reconciliation. Original CSV bytes are not available for export.

Every untrusted text field is quoted and CSV escaped. Leading formula characters (`=`, `+`, `-`, `@`) and control characters are prefixed with an apostrophe. Signed cent amounts are exported as apostrophe-prefixed text to preserve integer precision in spreadsheet applications. At most 500 rows and 5,000 decisions may be exported; larger histories fail clearly rather than silently truncating. Access uses the same authentication, business ownership and no-store response policy as other bookkeeping routes.

Verify with `node --test backend/test/bookkeeping*.test.mjs`, including cross-owner export denial, formula neutralization, exact large negative cents and match correction history.
