# Receipt Wiz Full Android internal release — 24 October 2026

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

## Released Google Play build

The existing signing key produced `KORLIX-Receipt-Wiz-2.aab` from runtime commit `466eb4e7e3361f1818f0e46764c04e956acf8cc6`: 56,171,705 bytes, SHA-256 `d45f66604d9497a15a6777223cce08ce9c58f5e75f54aa0cd5f3ae7662e344d3`. Jarsigner and bundletool validation passed. The manifest is package `com.korlixdeveloper.receiptwiz`, version 1.1.0 (2), min SDK 24, target SDK 36, with `com.android.vending.BILLING`. The temporary artifact download server was stopped after download.

Google Play published version **1.1.0 (2)** to the existing internal track at **4:45 PM America/New_York on 24 October 2026**. The track is Active and the release says **Available to internal testers**. Device support is unchanged. The existing nine-tester list was preserved; no invitations or messages were sent. [Manage the release](https://play.google.com/console/u/0/developers/4772708594176030332/app/4974803615919424879/tracks/4701326269245146922/releases/2/details). Test link: https://play.google.com/apps/internaltest/4701326269245146922. Google notes that updates usually appear within an hour, sometimes longer.

The colorful feature graphic, five actual Flutter UI screenshots and Free/Full store description were saved to the listing draft. Only the feature graphic has the approved AI label. The listing was not sent for public review.

The `receipt_wiz_full` product and base plan `monthly` are **Active**, with monthly auto-renewal, a seven-day grace period, automatic 53-day account hold, resubscribe allowed, and no introductory offer. The US price is USD 8.99, with Google-generated localized prices. All **174 named supported countries/regions** are enabled. The selector labeled “175 countries / regions” includes “New countries / regions” as its 175th option; automatic future expansion is off. An initial review rejection over the 174/175 discrepancy was resolved by expanding the selector and proving that only the future-market option was excluded, after which Apply was allowed. This corrects the earlier preparation record's 175-country count. The generic Save error came from stale ID validation: the field displayed `monthly` but had `aria-invalid=true`; re-entering the same ID cleared validation and the plan saved successfully.

The owner explicitly approved app-scoped access for `korlix-play-billing@korlix-ai.iam.gserviceaccount.com`. Receipt Wiz access was saved with **View app information (read-only)** (including inherited app quality access), **View financial data**, and **Manage orders and subscriptions** (including refunds and cancellation). Existing Korlix AI permissions and the absence of account-wide permissions were preserved. The successful backend catalog check confirms API access to the new app's active monthly plan.

Receipt Wiz real-time notifications are enabled for **subscriptions and voided purchases only**, using `projects/korlix-ai/topics/korlix-play-billing`. Google Play sent a test notification; the backend logged `[google-play] authenticated RTDN test notification received` at `2026-10-24T20:35:26.798634433Z`. Delivery uses the existing authenticated push subscription and endpoint. No new cloud identity or topic was created.

The subscription terms are **live** from exact commit `23079f9e5193672ce6d71ffd784265968820409e`, based on the previous live website commit `44e3f3d518a17f528dc4ed0f9adefb00f64d18f0`. Render deployment `dep-dbehc04s728c73c878kg` became live at `2026-10-24T20:38:04Z`. The public URL https://www.korlixdeveloper.com/subscription-terms.html returned HTTP 200 and contains Receipt Wiz, USD 8.99, 20 Free scans and 1,000 Full scans. Unrelated unpublished website branch changes were not deployed.

## Live deployment and verification

The owner's subsequent **Approved** authorized production deployment, subscription terms, notifications, the reviewed sales scope, the explicit billing access grant, and release to existing internal testers. The earlier preparation-stage approval blocks are resolved.

- Supabase migration `receipt_wiz_full_subscription` succeeded with returned version **20261024202256**. Its exact applied SQL is recorded in `supabase/migrations/20261024202256_receipt_wiz_full_subscription.sql` on the backend feature branch, commit `2af3c306df2a5315195df59383fb84b79ca663dd`. The source and applied SQL match byte for byte. MCP was used because the local CLI was unavailable; no migration timestamp was invented.
- RLS is enabled on the three billing/usage tables; anon/authenticated table access is revoked and service-role access is present. The three RPCs are security-invoker and executable only by the service role. Security advisors reported no WARN/ERROR findings; service-only tables intentionally have no browser policies.
- Live plan checks returned Free 20/100/250 MB, paid Full 1,000/5,000/2 GB, and the developer unlimited override. The next monthly reset is `2026-11-01T00:00:00Z`. Two existing usage rows were backfilled.
- Backend runtime commit `fc1e11a5dd5fbce58e45d5c4fb99f11cbb88a379` deployed successfully in `dep-dbeh7atg1s2s73fjbga0` with Receipt Wiz checkout initially off. Health returned 200 and unauthenticated subscription status returned 401.
- After the active Play catalog and public terms were verified, a merged environment update set `KORLIX_RECEIPT_WIZ_BILLING_ENABLED=true`. This automatically deployed the same runtime commit in **dep-dbehgb3ncjis73e93odg**, live at `2026-10-24T20:42:56Z`.
- Final Receipt Wiz and existing KORLIX billing health endpoints both returned HTTP 200, `configured=true`, `billingEnabled=true`, `notificationsConfigured=true`, and `catalogCheck.ready=true`. No customer purchase was made during verification.

## Remaining public-release and device checks

A Basic Google Play license-test account whose KORLIX UUID is authorized in `KORLIX_GOOGLE_PLAY_TEST_USER_IDS` must complete purchase/restore and expiry/cancellation checks on a physical Android device. Pro/Ultra/Enterprise accounts must show included Full and no extra charge. The owner/developer account intentionally cannot buy redundant Full. Public production was not submitted.

The advertising-ID declaration was saved as **No**, consistent with the verified signed manifest and standalone dependencies. After the owner explicitly approved renewed IARC Terms acceptance, the terms were accepted and the revised questionnaire was saved at **5:00 PM America/New_York on 24 October 2026**. Digital purchases are Yes; random/chance-based purchases are No. All other previous content answers remain No. Console shows **IARC Completed** and the interactive element **In-App Purchases**. ESRB remains Everyone and PEGI remains 3; Brazil now receives Rated 14+, with the other regional ratings unchanged. The app's intended 16+ audience remains separate from these content ratings. The change is saved in Publishing overview and has not been sent for Google review. Existing reviewer sign-in details, target audience and provider/logging verification for Data safety also remain prerequisites for public submission. These do not block the active internal test track.

The Data safety draft was updated to add **Account management** and **Fraud prevention, security, and compliance** as collection purposes for Purchase history, alongside App functionality. The same 10 data types remain selected. This includes subscription identifiers/state and entitlement/ownership verification. The draft is saved but remains uncertified pending the previously identified provider/logging checks.
