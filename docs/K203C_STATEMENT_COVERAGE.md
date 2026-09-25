# K203C statement review coverage

Saved statement detail now returns `coverage`, calculated on each owner-scoped read from immutable imported rows and the latest decision for each line. It contains imported date bounds, row count, matched and open counts, signed net cents for all rows, matched rows and open rows. All monetary arithmetic uses integer cents, including negative debits. A correction immediately moves the row back to open; a later reviewed replacement moves it to matched.

This is review progress for one imported file, not a bank reconciliation. It does not establish that every bank transaction was imported, compare opening or closing bank balances, adjust timing differences, post accounting entries, or certify completeness. It performs no database writes and requires no migration. Existing owner checks and private statement RPC remain in force. The frontend presents the scope directly alongside the totals.

Test with `node --test backend/test/bookkeeping*.test.mjs` and compare the widget coverage display before match, after match and after correction.
