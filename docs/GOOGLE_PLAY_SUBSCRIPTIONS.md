# Google Play subscription release

The Android Plans screen previously used the Apple catalog and returned before
querying Google Play. The prepared fix adds Play purchases for the two main
memberships. It does not activate the separate Music, AI GAS, badge, or video
credit products.

| Plan | Google Play product | Base plan |
| --- | --- | --- |
| Pro | `korlix_pro` | `monthly` |
| Ultra Premium | `korlix_ultra` | `monthly` |

Package: `com.korlixdeveloper.korlixai`. Prices come from the customer's store.
Only the standard monthly, auto-renewing base plan is offered; introductory and
annual offers are excluded until their terms have corresponding UI support.

## Backend setup

1. Migration `supabase/migrations/20261015212823_google_play_subscriptions.sql`
   was applied to the Korlix AI project on October 15, 2026. The version is the
   actual Supabase migration record. The tested source in
   `backend/google_play/schema.sql` is identical. Both new tables have RLS,
   browser roles have no table or function access, and Developer Unlimited was
   verified intact after applying it. Do not apply the migration twice.
2. Deploy the backend commit after that migration. New Play purchases default
   to disabled; receipt refresh and acknowledgment continue when credentials
   are configured, even if new purchases are subsequently disabled.
3. Enable the Google Play Android Developer API in the chosen Google Cloud
   project. Grant the service account access to this app in Play Console,
   including viewing financial/order data and managing orders/subscriptions.
4. Store the service account JSON directly in the backend's Render secret
   environment variable below. Do not put it in Flutter, Git, or a chat message.
5. Connect Google Play real-time developer notifications to a Pub/Sub topic.
   Create an authenticated, wrapped-message push subscription to
   `https://chee-chai-chee-backend.onrender.com/api/billing/google/notifications`.
   Set the expected push service account, exact audience, and full subscription
   resource name below. Grant Google's Play notification publisher permission
   to publish to the topic, and configure Pub/Sub's token creation permission
   for the push identity as described in Google's setup documentation.

| Render backend variable | Value |
| --- | --- |
| `KORLIX_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Service account JSON secret |
| `KORLIX_GOOGLE_PLAY_BILLING_ENABLED` | `true` when ready for the internal test |
| `KORLIX_GOOGLE_PLAY_TEST_USER_IDS` | Comma-separated KORLIX UUIDs for designated Basic license-test accounts |
| `KORLIX_GOOGLE_PLAY_RTDN_AUDIENCE` | Exact HTTPS notifications URL above |
| `KORLIX_GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT` | Authenticated Pub/Sub push service account email |
| `KORLIX_GOOGLE_PLAY_RTDN_SUBSCRIPTION` | `projects/PROJECT/subscriptions/SUBSCRIPTION` |

`GET /api/billing/google/health` exposes configuration booleans, package and
product IDs, never credentials. Configuration booleans do not prove working
API permissions. A server-owned read-only check queries both active monthly
products at startup and every five minutes, including while new purchases are
disabled. Its cached `catalogCheck.ready` and `checkedAt` prove that the configured
identity could read both products at that time; health requests never trigger
Google API calls. This check does not prove an actual purchase or RTDN delivery.
If it fails, `catalogCheck.reason` contains only a fixed diagnostic code, such as
`api_disabled`, `permission_denied` or `authentication_failed`. Raw provider
responses, credential text and account identifiers are never returned.
Before opening the purchase sheet, `/prepare` separately
checks the active monthly product through Google's authenticated server API.

Verification uses `purchases.subscriptionsv2.get`, checks the obfuscated account
binding, product, base plan, payment state and expiry, stores the entitlement,
then acknowledges it with Google. Tokens are server-only and cannot move to
another account. Unknown legacy replacements must first restore the prior
purchase. Current verified state is fetched again for each notification; the
notification body cannot set a tier. A bounded reconciliation worker retries
missed notifications. Expiry is also enforced on account profile reads.

## Android release

Use the existing signed Android Codespace. October 15 Console screenshots
confirm `12.0.0+131` is fully rolled out in Production and Internal testing, and
131 is the latest uploaded bundle shown. Both product IDs above have an active,
monthly auto-renewing base plan named `monthly`, available in 175 regions.
Verify no newer upload or draft exists before selecting the next version code.
The Console permissions for `korlix-play-billing@korlix-ai.iam.gserviceaccount.com`
include app-scoped financial data and order/subscription management. Runtime
catalog checks and an actual license-test purchase still establish API access
and end-to-end behavior; Console checkboxes alone do not.

The build requires the existing public Supabase client settings. Either export
`SUPABASE_URL` and `SUPABASE_ANON_KEY` in the Android Codespace, or set
`KORLIX_ANDROID_DEFINES_FILE` to the existing Flutter client JSON configuration.
The script validates that the key is public, passes the settings into Flutter,
and deletes its temporary file after building. The Google service-account JSON
is a backend-only credential and is never an Android build input.

After the frontend fix is checked out, run:

```bash
bash scripts/build-google-play-billing.sh HIGHEST_PLAY_VERSION_CODE
```

The script runs the billing tests and builds a signed AAB using the next version
code. It uses the existing keystore/signing configuration and does not publish.
Upload the AAB to Internal testing first, opt in with a Play license-test account,
and install through Play. A test-track user who is not a license tester can be
charged real money. The KORLIX test UUID must also be in the backend allowlist.
Use a Basic account for purchase tests; Developer Unlimited accounts already
have access and correctly cannot start an unnecessary subscription.

Verify both Pro and Ultra: localized price, purchase confirmation, verified tier
change, restore after reinstall, account switch, declined/pending payment,
renewal, cancellation, expiry/hold, refund/revocation and RTDN test delivery.
Test Pro-to-Ultra using Restore Purchases before changing plans. Only roll out
to production after these device/store tests pass. Local fixtures do not prove
Play Console configuration, signing, country eligibility, or actual checkout.

## Local validation

Backend: run `node --test test/google_play_billing.test.mjs
test/web_billing_database.test.mjs test/apple_billing_database_security.test.mjs`
from `backend/`. The database tests execute the actual proposed SQL and retain
the existing Apple/web tests against the new shared profile resolver.

Flutter: run `flutter test test/apple_billing_test.dart
test/google_play_billing_test.dart test/web_billing_test.dart`.

## References

- [Google Play API service account setup](https://developers.google.com/android-publisher/getting_started)
- [Purchase verification and acknowledgment](https://developer.android.com/google/play/billing/security)
- [Testing purchases](https://developer.android.com/google/play/billing/test)
- [Authenticated Pub/Sub push](https://cloud.google.com/pubsub/docs/authenticate-push-subscriptions)
- [Flutter in-app purchases](https://pub.dev/packages/in_app_purchase)
