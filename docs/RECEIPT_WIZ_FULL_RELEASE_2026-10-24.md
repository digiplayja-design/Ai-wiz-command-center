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

## Release gate

An automatic approval review rejected triggering the shared production Render backend deploy because explicit production approval is required. No deployment or live quota migration was performed. Backend release branch is prepared and automatic deployment remains off. The currently live backend remains `f35201cc93233b614d28598d0a7bef00657bbcba`; internal Android version 1.0.0 remains active.

After approval, apply `backend/receipt_wiz/subscription_schema.sql` via Supabase apply_migration (`receipt_wiz_full_subscription`), record the returned migration version, and verify RLS and service-only function/table privileges. Deploy the prepared backend to the existing service and require a live deploy plus HTTP health/access checks. Configure the separate Play product and existing authenticated RTDN delivery, require a successful catalog check for the new app, then enable `KORLIX_RECEIPT_WIZ_BILLING_ENABLED=true` through a merged environment update and verified deployment. Keep the hub billing settings unchanged. Publish the subscription terms from the candidate and update the saved digital-purchases rating answer and Data safety draft.

Only then roll out Android 1.1.0 (2) to the existing internal test track. A Basic license-test account must complete a Google Play test purchase/restore and expiry/cancellation checks; a Pro/Ultra/Enterprise account must show included Full and no extra charge. The owner/developer account intentionally cannot test buying redundant Full. No real purchase was made by the assistant. Public release still requires reviewer sign-in details, target-audience completion and Data safety certification.
