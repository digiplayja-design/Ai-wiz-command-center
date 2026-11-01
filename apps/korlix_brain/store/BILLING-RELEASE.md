# Brain+Voice store billing candidate — build 14

User confirmed build 13 works and authorized public App Store and Google Play release with purchasable AI GAS. This candidate adds native store checkout; it is not yet a submitted store release.

The monthly plan is USD 34.99 with 60 Live minutes per store billing period. The three retained AI GAS packs are 60 minutes / USD 30, 120 minutes / USD 55 and 180 minutes / USD 80. All exact product IDs are in `billing-products.json`. AI GAS is a consumable one-time purchase with a durable, non-expiring server balance. Included minutes are spent first; they do not roll over. No free trial or extra package was added. Deep Think continues to use the existing account limits.

## Implemented

- Native Apple / Google purchase stream, pending/canceled states, receipt verification, restore/retry and store subscription management.
- Account-bound Apple appAccountToken and obfuscated Google account IDs; only verified store observations can grant minutes.
- Durable transaction/order deduplication, subscription renewal periods, GAS refunds and periodic store reconciliation. Google is consumed/acknowledged only after the credit is committed.
- Server-clock Live usage, one active conversation per account, reservation of available seconds, return of unused reservations and provider hangup on Stop, time limit or lost heartbeat. Persistent call IDs allow termination to retry after server restart.
- Local welcome/music are not metered. Existing Live/Deep Think models, Marin voice and Risi pronunciation are unchanged.
- Release Android signing accepts CI-managed credentials or an untracked local key.properties; a release build fails if the upload key is missing.

## Required before store submission

1. Create/verify the four products in the dedicated Brain+Voice App Store / Play records. Monthly plan has no trial; Google base plan ID is `monthly`, duration `P1M`. The three GAS products are consumables, not subscriptions.
2. Apple first subscription and consumables must accompany the app-version review. Add localized descriptions and IAP review screenshots, confirm pricing/availability and paid-app agreement status. Product prices must match the approved USD catalog before setting readiness flags.
3. Configure Apple Server Notifications V2 at `/api/brain/billing/apple/notifications`. Google purchases are reconciled by the server every 10 minutes; allow the existing server service account to verify Brain+Voice purchases in Play Console.
4. Run the paired backend migration and deploy its billing module. Keep `KORLIX_BRAIN_BILLING_ENABLED=false` until products and device purchase tests are ready. Existing Apple and Google server credentials stay server-side.
5. Enable only verified stores with `KORLIX_BRAIN_APPLE_PRODUCTS_READY=true` / `KORLIX_BRAIN_GOOGLE_PRODUCTS_READY=true`, then `KORLIX_BRAIN_BILLING_ENABLED=true`. Health: `/api/brain/billing/health`. Flags alone are not purchase-test evidence.
6. On designated store test accounts, verify monthly buy/restore/renewal, each of the three GAS packs, repeated restore without duplicate minutes, exhausted allowance, pending/canceled purchase, refund, account switch, reinstallation and Stop returning unused minutes. Sandbox receipts require an existing server allowlist entry.
7. Build a signed IPA and Android AAB. Android upload signing and the Play app record still need verification. Run the standard signed iOS identity checks, mobile tests and UI checks. Select the new build and IAPs for Apple review; submit the AAB and matching subscriptions/products to Play's appropriate release track.

## Current access blockers

Apple sign-in reached two-factor verification but rejected the supplied code. Complete secure browser authentication to configure its products and submission. Play Console was blocked by automatic approval review after the browser origin gate evaluated `https://google.play` even though the requested URL was `https://play.google.com/console`; no Play mutations were made. Neither store submission is confirmed.
