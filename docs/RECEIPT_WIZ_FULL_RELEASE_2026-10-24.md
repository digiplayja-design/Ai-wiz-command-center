# Receipt Wiz Full Android candidate — 24 October 2026

The owner confirmed the original internal build downloaded and tested successfully, requested a more colorful frontend and an $8.99/month Full subscription, selected 20 Free AI scans/month and 1,000 Full scans/month, and chose to include Full with existing Pro, Ultra and Enterprise access.

| Plan | Monthly AI scans | Stored receipts | Storage |
|---|---:|---:|---:|
| Free | 20 | 100 | 250 MB |
| Full | 1,000 | 5,000 | 2 GB |

Full uses Google Play product `receipt_wiz_full`, auto-renewing base plan `monthly`, package `com.korlixdeveloper.receiptwiz`, US base price $8.99. The actual local offer is read from Play. Allowances reset on the first of each calendar month at 00:00 UTC, without rollover, and are shared across KORLIX receipt tools. Failed/expired scan reservations are refunded once. Manual editing, search and CSV export remain available, including after cancellation or when above the Free storage allowance. Existing developer unlimited overrides remain intact.

The new receipt entitlement never writes the hub subscription tier. Server verification binds the exact package, product and obfuscated account, preserves purchase-token ownership, rejects test purchases outside the authorized tester IDs, and acknowledges only after the grant is stored. The existing authenticated RTDN endpoint can dispatch Receipt Wiz events separately from hub events. Browser roles cannot read purchase tokens or write usage/entitlements.

## Validation

- 100 backend tests passed across receipt allowances/billing, existing Google/Apple/web billing, signup and session security.
- 81 shared receipt tests and 22 standalone tests passed; optional screenshot exporters are separate.
- Static analysis passed for core and standalone app.
- Real Flutter UI screenshots were regenerated using local sample data only. Phone, landscape, tablet and enlarged-text layout tests passed after the final badge-contrast fix.
- Runtime app commit: `466eb4e7e3361f1818f0e46764c04e956acf8cc6`.
- Backend commit: `fc1e11a5dd5fbce58e45d5c4fb99f11cbb88a379`.
- Final runtime CI run [40125218882](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40125218882) passed Android and iOS simulator builds.

## Prepared Google Play release

The existing signing key produced `KORLIX-Receipt-Wiz-2.aab` from runtime commit `466eb4e7e3361f1818f0e46764c04e956acf8cc6`: 56,171,705 bytes, SHA-256 `d45f66604d9497a15a6777223cce08ce9c58f5e75f54aa0cd5f3ae7662e344d3`. Jarsigner and bundletool validation passed. The manifest is package `com.korlixdeveloper.receiptwiz`, version 1.1.0 (2), min SDK 24, target SDK 36, with `com.android.vending.BILLING`. The temporary artifact download server was stopped after download.

Google Play accepted the bundle and the saved internal draft says **Ready to release**. Device support is unchanged. The final **Save and publish** action was not taken. The existing internal tester list was preserved; no invitations or messages were sent. [Review the draft](https://play.google.com/console/u/0/developers/4772708594176030332/app/4974803615919424879/tracks/4701326269245146922/releases/2/review).

The colorful feature graphic, five actual Flutter UI screenshots and Free/Full store description were saved to the listing draft. Only the feature graphic has the approved AI label. The listing was not sent for public review.

The `receipt_wiz_full` product was created and its benefits saved: 1,000 AI scans/month and 5,000 receipts within 2 GB. Base plan `monthly` is prepared with monthly auto-renewal, a seven-day grace period, automatic 53-day account hold, and no introductory offer. USD 8.99 and Google-generated local prices were entered. The country selector has the existing standard 175-country scope. **An automatic approval review rejected Apply for that scope, so the base-plan form remains unsaved and no plan was activated.** Do not retry or indirectly commit this scope until the owner explicitly approves it. The browser form is preserved; if it expires, recreate the same reviewed settings after approval.

The existing billing service account `korlix-play-billing@korlix-ai.iam.gserviceaccount.com` has access only to Korlix AI and no account-wide permissions. Receipt Wiz needs app-scoped **View app information (read-only)** (including inherited app quality access), **View financial data**, and **Manage orders and subscriptions**. The last permission also permits refunds and cancellation. Receipt Wiz is selected in the Add app picker, but no access was applied or saved. Browser policy requires action-time owner confirmation before this grant. Keep other app access and account-level permissions unchanged.

Receipt Wiz real-time notifications are currently disabled. After the backend is deployed, configure the existing authenticated path using topic `projects/korlix-ai/topics/korlix-play-billing`, with subscriptions and voided purchases only, then verify a test notification reaches the shared endpoint. No new cloud identity or topic is needed. No notification was sent during preparation.

The subscription terms are prepared in commit `23079f9e5193672ce6d71ffd784265968820409e` on `feature/receipt-wiz-full-policy-20261024`, based on the currently live website commit `44e3f3d518a17f528dc4ed0f9adefb00f64d18f0`. Deploy that exact commit after approval, avoiding unrelated unpublished changes on the website release branch.

## Release gate

An automatic approval review rejected triggering the shared production Render backend deploy because explicit production approval is required and the shared service could be disrupted while the changes and migration are not deployed and verified. A separate automatic review rejected committing subscription availability across 175 countries because that sales scope was not explicitly authorized. No deployment, live quota migration, billing activation, access grant or Android rollout was performed. Backend release branch is prepared and automatic deployment remains off. The currently live backend remains `f35201cc93233b614d28598d0a7bef00657bbcba`; internal Android version 1.0.0 remains active.

After approval, apply `backend/receipt_wiz/subscription_schema.sql` via Supabase apply_migration (`receipt_wiz_full_subscription`), record the returned migration version, and verify RLS and service-only function/table privileges. Deploy the prepared backend to the existing service and require a live deploy plus HTTP health/access checks. Configure the separate Play product and existing authenticated RTDN delivery, require a successful catalog check for the new app, then enable `KORLIX_RECEIPT_WIZ_BILLING_ENABLED=true` through a merged environment update and verified deployment. Keep the hub billing settings unchanged. Publish the subscription terms from the candidate and update the saved digital-purchases rating answer and Data safety draft.

Only then roll out Android 1.1.0 (2) to the existing internal test track. A Basic license-test account must complete a Google Play test purchase/restore and expiry/cancellation checks; a Pro/Ultra/Enterprise account must show included Full and no extra charge. The owner/developer account intentionally cannot test buying redundant Full. No real purchase was made by the assistant. Public release still requires reviewer sign-in details, target-audience completion and Data safety certification.
