# K203E bank balance worksheet

In **Saved statements**, choose one import and enter the opening and closing USD balances from the original bank statement. The worksheet computes `opening bank balance + signed total of imported rows` and shows `bank closing balance - expected closing balance`. It uses exact integer cents, supports negative overdraft balances, and rejects imprecise formats and unsupported amounts. Editing either input immediately clears the prior result.

This is a temporary screen calculation. The entered balances and result are not posted, persisted or exported, and there is no backend or database migration. Verify that the balances refer to the same complete statement period as the imported rows. A difference can point to omitted, duplicate or sign-reversed rows, or a period mismatch. A zero difference only confirms arithmetic; offsetting omissions can still exist, and matches to book entries remain a separate review. The worksheet does not calculate a book balance or certify reconciliation.

Run the bookkeeping widget suite and Flutter production web build before deployment.
