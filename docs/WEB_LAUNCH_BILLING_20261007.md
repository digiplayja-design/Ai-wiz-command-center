# Web launch billing verification — October 7, 2026

**Decision: the free web service can be assessed independently; new paid web subscriptions and paid Directory memberships must remain paused under the owner's October 4 instruction.** The billing integration is configured against the intended live account. The remaining direct-sales gate is the owner's registration/tax decision and its implementation, followed by the outstanding launch acceptance. A countdown must not enable checkout or represent these gates as complete.

This review used read-only Stripe GET operations, three public health GETs, source review and local fixture tests. It created no customers, sessions, payments, subscriptions, refunds, merchant accounts or tax registrations. It changed no credentials, runtime flags or provider configuration. The API version remains `2026-09-30.endive`.

## Current direct-sales evidence

Observed on October 7, approximately 21:33–21:39 UTC (17:33–17:39 EDT). Source reviewed: backend `fee1d83a3a7210a054da647ea7974260d000e2d4`.

| Check | Verified result |
| --- | --- |
| Intended Stripe platform | Connector and existing configuration records match live **Korlix INC**, `acct_1UMs8D22E1oIiTRb`. A Stripe display name is not independent proof of the registered legal entity. |
| Platform readiness | Charges enabled, payouts enabled, details submitted; no currently due, past due, pending-verification requirements or disabled reason. This is the platform snapshot, not merchant Connect readiness. |
| Web subscription health | HTTP 200, configured, live payments, connection verified, **checkout disabled**. Pro USD 34.99/month and Ultra Premium USD 124.99/month. |
| Live web price catalog | Both configured prices active, USD, licensed monthly interval, one product per tier, amounts 3499 and 12499 cents. Tax behavior is unspecified. |
| Web lifecycle destination | Enabled live webhook `we_1UMwlF22E1oIiTRbf4nbm4hl` matches `/api/billing/web/webhook`, pinned Endive version, and all 16 events consumed by the web billing handler, including renewal, payment failure, cancellation, refund and fraud/dispute signals. Configuration is not proof of a completed production payment delivery. |
| Web customer portal | Active live configuration `bpc_1UMwkA22E1oIiTRbU9EAlMkB`; invoice history, payment-method updates, period-end cancellation and price changes enabled. Public portal login disabled. The runtime's catalog/configuration probe reports verified. |
| Web return links | Checkout and portal source use `https://www.korlixdeveloper.com/app/?billing=return`; cancellation uses `?billing=cancel`. A return URL never grants access; server verification controls entitlements. |
| Directory health | HTTP 200, credentials configured, live payments, connection verified, **checkout disabled**. Free listings and public browsing enabled. Prices remain USD 4.99/month or USD 49/year. |
| Directory lifecycle destination | Enabled live Endive webhook `we_1UMtFQ22E1oIiTRbqPqBVeqp` matches `/api/directory/billing/webhook` and its required 12 events. The earlier Clover endpoint remains disabled. |
| Directory customer portal | Active live configuration `bpc_1UMsX222E1oIiTRbi0pFRMWZ`; invoice history, payment-method changes and period-end cancellation enabled; subscription/quantity updates and public portal login disabled. |
| Directory return links | Source uses `https://www.korlixdeveloper.com/business-directory/?membership=return` and `?membership=cancel`; portal returns to `/app/`. |
| Stripe Tax | Settings status active, head office OH/US. **Zero registrations** returned, no further pages; default tax code and tax behavior unset. Source does not enable automatic tax for either direct-sales checkout. An active settings object is not an active tax registration. |

Health paths above are on `https://chee-chai-chee-backend.onrender.com`:

- `/api/billing/web/health`
- `/api/directory/health`
- `/api/scheduling/payments/health`

The check did not read customers or unrelated transaction histories. It did not expose API keys, signing secrets or customer addresses. Runtime health verifies that the deployed credential can read the expected portal; raw Render environment values were not requested.

## Evidence levels: do not combine the three payment products

### 1. KORLIX Pro and Ultra web subscriptions

The original sandbox `acct_1UMI5OLx6hd5l5Vo` was inspected read-only for the exact existing synthetic subscription `sub_1UMwbsLx6hd5l5VoxeyX4o4O`. Stripe currently reports it canceled. Its complete invoice list contains:

| Invoice | Provider result |
| --- | --- |
| `in_1UMwbsLx6hd5l5VofvfAx8bT` | Test mode, paid USD 34.99, `subscription_create` |
| `in_1UMweJLx6hd5l5Vo0gfY1509` | Test mode, paid USD 90.00, `subscription_update` (Pro-to-Ultra proration) |

These current reads corroborate the October 4 sandbox paid-subscription, upgrade and final-cancellation record. Scheduled cancellation and portal session creation are historical evidence in [WEB_BILLING_20261004.md](WEB_BILLING_20261004.md). They were not repeated today. No cycle-renewal invoice exists in this exact subscription's complete invoice list.

The earlier hosted Checkout was created **unpaid**; the API-driven sandbox subscription is distinct from a user completing that Checkout. This is not evidence of an authenticated production web purchase, a production entitlement activated by its signed webhook, a production customer return or an actual failed renewal. Those claims remain unverified. Current local tests cover the payment-state and security rules described below.

### 2. Business Directory memberships

The October 4 evidence in [BUSINESS_DIRECTORY_BILLING_SETUP.md](BUSINESS_DIRECTORY_BILLING_SETUP.md) includes genuine sandbox hosted monthly Checkout, the browser return, portal cancellation, signed delivery and a clock-advanced renewal. Today, exact existing renewal invoice `in_1UMv0pLx6hd5l5VoarmSKPM6` was re-read: **test mode, paid USD 4.99, `subscription_cycle`**, bound to `sub_1UMurhLx6hd5l5VoRMxFV3yf`. That synthetic subscription remains canceled after cleanup. No new test ran against Stripe.

The historical signed-in **live** Directory Checkout was displayed with the correct price but left unpaid. It does not establish a paid live badge lifecycle. These Directory results do not prove Pro/Ultra or scheduling acceptance.

### 3. 2MEETU merchant booking payments (Stripe Connect)

Production scheduling health reports configured, **test mode**, merchant setup enabled, **checkout disabled**, direct charges, zero platform transaction fee, Accounts v2 readiness and Endive API. The complete current live webhook list contains no `/api/scheduling/payments/webhook` destination.

The separate isolated USD 1.00 hosted acceptance described in [STRIPE_HOSTED_SANDBOX_STAGING.md](STRIPE_HOSTED_SANDBOX_STAGING.md) covered one synthetic booking, signed completion, the actual iPad return, zero application fee, restart recovery, full refund and duplicate preservation. Its separate platform/merchant are not exposed through the current Stripe connector; that historical ledger was not re-read today. The harness did not mount the complete production authenticated-owner/public-booking journey or certify production worker, role separation, email or calendar effects.

Matching live merchant setup, live scheduling webhook/configuration, merchant readiness and remaining Connect acceptance are separate gates in [STRIPE_PRODUCTION_READINESS_20261006.md](STRIPE_PRODUCTION_READINESS_20261006.md). Keeping paid bookings disabled does not prevent a free web launch or free scheduling; do not advertise paid merchant booking readiness.

## Current local verification

All **55 focused backend tests passed** on October 7:

```bash
cd backend
node --test test/web_billing.test.mjs test/web_billing_database.test.mjs \
  test/directory_routes.test.mjs test/directory.test.mjs \
  test/directory_billing_activation.test.mjs test/directory_webhook_probe.test.mjs
```

These use local provider fixtures and PGlite, not live payments. They cover authentication, verified email, ownership and generation binding, RLS/browser grants, fixed prices, retries, signed-event mode/integrity/idempotency, unpaid renewals, cancellations, refund holds, entitlement composition, paused checkout and continued billing management. No defect requiring a backend billing change was identified in this bounded review.

## What can proceed and what still needs a decision

**Can proceed autonomously:** preserve all sales switches; make the public pricing/countdown availability language match the actual pause; maintain account/billing access and webhook reconciliation; finish the remaining free-web operational checks; prepare a scoped paid-release checklist and sandbox acceptance after the tax choice is known. Root owns the pricing/countdown edit.

**Needs owner/account information:** confirm whether the applicable registration and product tax treatment have been resolved, and the approved selling jurisdictions. The October 4 owner pause remains in force. Do not infer a legal registration obligation from the Stripe settings or choose a product tax code on the owner's behalf.

**Before paid release:** record confirmed registrations where applicable, confirm product tax codes and tax behavior, implement and verify the corresponding checkout tax configuration in the designated sandbox, complete the actual hosted web-plan purchase/return/lifecycle acceptance, and only then enable the specific authorized direct-sales switch. Test tax calculations must be inspected for their taxability reason; zero tax alone does not prove success. Adding a registration in Stripe records a registration and is not registration with a tax authority. Tax collection and tax filing are separate operations.

References reviewed through the installed Stripe guidance: [go-live checklist](https://docs.stripe.com/get-started/checklist/go-live), [tax setup](https://docs.stripe.com/tax/set-up), [registrations](https://docs.stripe.com/tax/registering), [testing Stripe Tax](https://docs.stripe.com/tax/testing). This record does not certify legal tax compliance or a completed paid launch.
