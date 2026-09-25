# K203F statement review guide

The Bookkeeping dashboard now includes an expandable **Statement review guide** next to the existing statement controls. It walks an owner through choosing the correct business cash account, reviewing a CSV before import, comparing original bank balances in Saved statements, confirming or correcting matches, and exporting a review record. It links directly to the preview and saved reviews. The guide explicitly says that matching worksheet arithmetic does not prove complete reconciliation.

The early access scope copy now reflects the shipped statement import, review and export features. It directs the next step to owner acceptance with real statements and completeness checks. There is no backend, schema or data change. No walkthrough acknowledgement or certification is recorded.

Verify with the bookkeeping widget suite, static analysis of changed files, and a production web build. The test opens the guide from the dashboard and navigates to Saved statements; the empty recordbook test checks the corrected scope copy.
