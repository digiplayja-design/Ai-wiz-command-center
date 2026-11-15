# Esha native membership and consultation meter

This module implements an independent Esha membership. The approved commercial offer is a three-day trial followed by US$4.99 per month, subject to store eligibility and localized store pricing. A verified store subscription starts the trial; installing the app or starting a local timer does not. These candidate store identifiers are **not proof that a store record exists**:

| Item | Candidate identifier |
| --- | --- |
| iOS bundle / Android package | `com.korlixdeveloper.esha` |
| Apple subscription | `com.korlixdeveloper.esha.monthly` |
| Google subscription | `esha_monthly` |
| Google base plan | `monthly` |
| Google trial offer | `trial-3-days` |

The native client must show the actual store-localized price and eligible offer returned by StoreKit/Play Billing. The server catalog's USD amount is the approved offer, not a substitute for the store purchase sheet. This code does not create store products, change account tiers, enable production charges, or determine that the offer is available to a particular customer.

## Server integration

Register this module using the existing authenticated user function, Supabase service-role client, and Astra text adapter:

```js
import {createEshaBilling} from './esha/billing/routes.mjs';

const eshaBilling = createEshaBilling({
  database: supabaseAdmin,
  requireUser,
  generate: ({instructions, input, maxOutputTokens, textFormat, signal}) =>
    korlixAstra.createTextResponse(new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
      maxRetries: 0,
      timeout: 180000,
    }), {
      instructions,
      input,
      max_output_tokens: maxOutputTokens,
      text: {format: textFormat},
      store: false,
    }, {signal, timeout: 180000, maxRetries: 0}),
});
eshaBilling.register(app);
```

The existing `requireUser` verifies the bearer token, disabled-account state and supplied device identity. Keep these checks. The dedicated `/api/esha/consult` path uses the Esha ledger. Do not route it through core credit deduction, developer unlimited access, or core tier upgrades. Existing Esha web requests to `/api/generate` keep their current Korlix credit behavior. No changes to that route or the shared model adapter are required.

Apply `supabase/migrations/20261115172402_esha_store_billing.sql` through the normal migration process before serving the endpoints. This creates five Esha-only tables and one service-only command function. All tables have RLS enabled; `public`, `anon`, and `authenticated` cannot read receipts or invoke the command. Tokens and response-cache rows are never returned by the billing APIs. Raw purchase tokens are kept only in the private purchases table for store refresh. Completed consultation answers are retained privately to replay a lost response without another generation; deleting the owning account cascades its consultation data. Hash-only confirmed refund tombstones persist independently of an account so an unbound refund cannot later become an entitlement.

## Configuration and safe defaults

New sales and native AI are off by default. There is no unlimited entitlement and there are no default consultation counts. Required configuration is factual, not a browser-side entitlement:

| Variable | Meaning |
| --- | --- |
| `KORLIX_ESHA_TRIAL_CONSULTATIONS` | Explicit positive count for one verified trial period; required, no default. |
| `KORLIX_ESHA_MONTHLY_CONSULTATIONS` | Explicit positive count for one verified paid billing period; required, no default. |
| `KORLIX_ESHA_MAX_OUTPUT_TOKENS` | Explicit provider output budget; must be compatible with the existing Astra adapter. |
| `KORLIX_ESHA_NATIVE_AI_ENABLED` | Must equal `true` to serve new native consultations. |
| `KORLIX_ESHA_BILLING_ENABLED` | Must equal `true` to prepare new store purchases. |
| `KORLIX_ESHA_APPLE_PRODUCTS_READY` | Set `true` only after the Esha app, monthly product, US$4.99 price, three-day intro offer, server notification URL and device purchase flow have actually been checked in Apple systems. |
| `KORLIX_ESHA_GOOGLE_PRODUCTS_READY` | Set `true` only after the Esha package, monthly base plan, price, trial offer, notification wiring and device purchase flow have actually been checked in Play systems. |
| `KORLIX_ESHA_APPLE_APP_ID` | The actual numeric Apple app ID; no placeholder is accepted as a configured app. |
| `KORLIX_ESHA_TEST_USER_IDS` | Explicit comma-separated Korlix UUIDs allowed to redeem sandbox/test purchases. |
| `KORLIX_ESHA_GOOGLE_RTDN_AUDIENCE` | Exact audience of the Google push OIDC token for the Esha notification endpoint. |
| `KORLIX_ESHA_GOOGLE_RTDN_SERVICE_ACCOUNT` | Exact verified push-service-account email. |
| `KORLIX_ESHA_GOOGLE_RTDN_SUBSCRIPTION` | Exact Pub/Sub subscription resource name. |

The existing `KORLIX_APPLE_ISSUER_ID`, `KORLIX_APPLE_KEY_ID`, `KORLIX_APPLE_PRIVATE_KEY` or `KORLIX_APPLE_PRIVATE_KEY_BASE64`, and `KORLIX_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` credentials are reused only on the server. The credential must have access to the actual Esha app. `OPENAI_API_KEY` stays on the server. Nothing in this module requires exposing or rotating these existing secrets.

The current repository adapter fixes text to `gpt-6-astra`, reasoning `max`, and raises output limits to at least 32,768 tokens. Therefore an Esha output budget below 32,768 is rejected as incompatible; it would not actually constrain this adapter. The explicit cap is passed unchanged to `createTextResponse`, with a 180-second provider timeout, cancellation signal, and no automatic generation retries. Counts and this cap must be chosen to fit the approved $4.99 offer before activation. This implementation does not assert that any particular allowance is commercially viable. Other apps' model choices and limits are unchanged.

Membership can be stored and restored while new sales are paused. AI must have real allowance configuration, output budget, provider credentials, server catalog, and its explicit activation flag. Removing a sales flag does not stop refund/expiry reconciliation.

## Native API v1

Every authenticated endpoint uses existing Korlix bearer authentication and device headers. Membership/consultation endpoints require a verified account email. Responses are `Cache-Control: no-store`.

| Endpoint | Contract |
| --- | --- |
| `GET /api/esha/catalog` | Public manufacturer-sourced starter catalog. Current file contains 12 products, dated price snapshots and explicit unknown prices/ingredients/availability. |
| `GET /api/esha/billing/catalog?provider=apple\|google` | Public offer: `catalogVersion`, `provider`, `bundleId`, `product`, `purchasesEnabled`, `storeConfigurationVerified`, `allowanceConfigured`, `consultationLimits`, `consultationEnabled`, `state`. |
| `GET /api/esha/billing/status?provider=apple\|google&refresh=1` | Same catalog fields plus `membership`, `allowance`, and optional `warning`; `refresh=1` performs fresh store lookups. |
| `POST /api/esha/billing/prepare` | Input `{provider,productId}`. Returns `{canPurchase,accountId,bundleId,productId,basePlanId,offerId}` only if purchases are enabled and no current Esha membership exists. |
| `POST /api/esha/billing/verify` | Apple: `{provider:'apple',productId,purchaseId}` with the StoreKit transaction ID. Google: `{provider:'google',productId,purchaseToken}` with server verification data. Returns `{verified,completePurchase,active,status}`. |
| `POST /api/esha/consult` | Input `{requestId,question,preferences?,history?}`. Returns `{requestId,answer,productIds,usage}`. |

`product` contains `productId`, `billingPeriod:'P1M'`, `trialDays:3`, `monthlyPriceCents:499`, `currency:'USD'`, and Google `basePlanId`/`offerId` (null for Apple). It never contains provider credentials.

`consultationLimits` contains the configured `{trial,monthly}` consultation counts so a person without a membership can review the allowance before purchase. Both are null if either count is unconfigured. These advertised limits are separate from an existing member's stored allowance; changing configuration never refills or changes an already granted period.

`membership` contains `active`, `provider`, `expiresAt`, `trial`, `verificationFresh`, and `autoRenewing`. `allowance`/`usage` contains `configured`, `limit`, `used`, `reserved`, `remaining`, and `periodEndsAt`. Unknown/unconfigured limits are null. Cancellation can leave membership active until the store's expiry; a device does not infer the entitlement from its clock.

For Apple checkout, `accountId` is the signed-in Korlix UUID and must be supplied as the actual StoreKit `appAccountToken`. For Google checkout, it is a distinct Esha-scoped SHA-256 account ID and must be supplied as `obfuscatedAccountId`. A Flutter API parameter named `applicationUserName` must be checked against the selected plugin's real StoreKit/Play mapping; this backend rejects transactions without the expected store-returned binding. Complete the native pending purchase only when the server returns both `verified:true` and `completePurchase:true` for the still-signed-in account. A purchase callback alone never activates AI.

Consultation questions are limited to 3,000 characters. Optional preferences are limited to 6,000 serialized characters and primitive/string-list values. The server keeps at most ten selected history turns of 1,500 characters each. System-role history is discarded. Client catalog data are ignored; the server loads `backend/esha/catalog.json`. Product recommendation IDs must be from that catalog, and generated external product links are checked against its manufacturer URLs. Unknown prices are not treated as zero or included in a claimed within-budget shopping total. No photo analysis, external action, web search or core-chat memory is available to this endpoint.

Reuse the same request UUID and same body after a network interruption. A committed result is replayed without another generation or charge. Reusing that ID with different normalized input returns `409 idempotency_mismatch`. `409 request_in_progress` means keep the ID and retry later. `409 request_finished` means that a failed/timed-out attempt has ended; use a fresh ID only when the user explicitly retries. Provider failure releases a reserved allowance exactly once. The ten-minute reservation lease survives process restarts and outlasts the provider timeout. One account can have only one active consultation reservation.

Errors contain `{error,code}`: `401` authentication required, `403` email/test access, `409` pending purchase/ownership/duplicate or in-progress request, `402` missing membership or exhausted allowance, and `503` unconfigured services, failed refresh or unavailable provider. A result cannot be committed after its billing period is revoked.

## Store lifecycle and notifications

Apple notification URL: `/api/esha/billing/apple/notifications`. Notification JWS and transaction JWS are verified with Apple's server library and pinned Apple roots; notifications trigger a fresh subscription-status lookup. The server checks exact bundle, product, account token, purchased ownership, quantity, transaction/original IDs, signed dates, status and expiry. Grace periods require a matching signed renewal record. Ambiguous introductory phases fail closed.

Google notification URL: `/api/esha/billing/google/notifications`. The server verifies the push OIDC token, exact audience, verified service-account email, issuer, subscription resource and Esha package. It fetches the subscription from the fixed Esha package URL, checks account binding, exact product/base plan, state, current offer phase, and last successful order. Pending, paused, on-hold or expired subscriptions do not grant access. A canceled but unexpired subscription retains paid access. Acknowledgement follows durable entitlement storage.

Confirmed Google void events are checked against `purchases.voidedpurchases.list`, with current `pageSelection.*` pagination parameters, then stored as hash-only order/token tombstones **before** attempting owner lookup. This includes refunds received before first restore. Recording the confirmed refund immediately revokes the matching current order and consultation grant under the account lock; a second store lookup is not needed to block a reserved response. Purchase-scoped transaction locks serialize this with first restore even before a purchase row exists. A later ACTIVE status for that same order cannot reverse the refund. Refunds of an older order do not revoke a distinct later paid renewal. The void lookup searches at most five pages per attempt and fails/retries if a match has not been confirmed. Operational notification delivery must remain working; the store's voided-purchase API retains a finite history.

Purchase reconciliation runs every minute for rows whose next check is due: normally ten minutes for active purchases, one day for inactive ones, and five minutes after a failure. The database independently checks actual expiry for every reservation. A last successful store verification older than fifteen minutes blocks new AI until refreshed. This bounds stale access after missed notifications and fails closed during a prolonged store outage. It is not an assertion of instantaneous refund delivery. Multiple backend instances may perform a duplicate store lookup; account/receipt/period locks and immutable grants prevent duplicate allowance.

One verified transaction/order creates one allowance for that period. Restore/config changes do not refill it. Renewal creates a fresh period without rollover. Concurrent/overlapping Apple and Google memberships do not stack allowances. Trial and paid-period counts are distinct. These limits are stored in the Esha tables and never alter core Pro/Ultra access or shared credits.

## Verification

Run from `backend/`:

```sh
node --test test/esha_native_billing.test.mjs
```

Tests execute the actual migration using PGlite and exercise service-role commands, RLS denial, ownership, no core-tier changes, expiry, stale verification, permanent refunds, pre-binding refunds, idempotency, allowance exhaustion, provider failure, the real 12-product catalog, server-only catalog grounding, Google notification identity, and HTTP activation guards. They use offline fixtures and never call a real store or AI provider. These tests do not establish that a real store product, approved app, receipt, offer or production credential works. Signed device checkout, restore, cancellation, expiration, refund, account-switch and store-notification tests remain release prerequisites.
