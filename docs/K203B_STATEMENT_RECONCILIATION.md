# K203B saved statements and reviewed matches

Current behavior update: K203G allows documented, owner-confirmed repeated rows within one CSV. See `K203G_REPEATED_STATEMENT_ROWS.md`. The original K203B duplicate restriction below is historical.

The Bookkeeping screen supports CSV preview, confirmed import, and Saved statements. Choose the statement columns, year and business cash account, inspect the preview, then confirm the normalized rows to save them. Invalid rows and duplicates within the CSV block import. The original CSV bytes are not stored. A failed response offers **Retry same import**, preserving the exact request key and contents.

Saved statements lists imports and their rows, candidate recorded cash movements and full match decision history. Select a candidate and explicitly confirm the match. To correct it, provide a reason, confirm the correction and then review a replacement. A failed decision can be retried with the same request key. Matching never posts or alters a journal entry.

Candidates require the same named cash account, exact signed amount and a date within three days; reversals and reversed originals are excluded. The backend enforces these rules and one active match per recorded entry. Identical CSV sources are replayed when the mapping agrees. Overlapping date, amount and description rows on the same account/year may be rejected, including legitimate indistinguishable repeated transactions; inspect Saved statements and resolve this before retrying.

There is no bank feed, cleared balance calculation or automatic reconciliation. Real owner acceptance must compare actual bank statements against the recorded books. Backend schema and API details are documented in the backend copy of this chapter.

Verify with `flutter analyze --no-pub` and `flutter test --no-pub test/bookkeeping_test.dart test/bookkeeping_receipts_test.dart test/bookkeeping_mileage_test.dart test/bookkeeping_ledger_test.dart test/bookkeeping_reports_test.dart test/bookkeeping_statement_preview_test.dart`.
