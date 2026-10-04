# Business Directory Stripe activation

Scope: optional verified Business Directory memberships at the existing USD
$4.99/month or $49/year. Free listings remain available. This setup does not
enable KORLIX plan subscriptions, AI GAS, Music Studio, or 2MEETU Connect billing.

## Backend configuration

Store credentials only in the Render backend environment, never in Flutter,
Git, chat, or logs. Use a restricted Stripe API key dedicated to this feature.

| Variable | Purpose |
| --- | --- |
| `KORLIX_DIRECTORY_STRIPE_SECRET_KEY` | Server-side restricted key (`rk_`); the historical variable name also supports existing `sk_` keys. |
| `KORLIX_DIRECTORY_STRIPE_WEBHOOK_SECRET` | Signing secret of the matching-mode endpoint below. |
| `KORLIX_DIRECTORY_STRIPE_PORTAL_CONFIGURATION_ID` | Expected account's `bpc_` configuration, used for portal sessions and a read-only credential check. |
| `KORLIX_DIRECTORY_STRIPE_ENABLED` | Exact string `true` enables new checkout after configuration. Missing or any other value keeps new checkout paused. |

Saving credentials alone never enables new checkout. Pausing checkout leaves
verified lifecycle callbacks, refresh, billing management, and renewal
cancellation available. Existing Stripe subscriptions continue renewing until
the member cancels; disabling new purchases does not cancel existing members.

`GET /api/directory/health` reports credential presence, checkout activation,
payment mode, pinned API version and a sanitized `paymentConnection` status.
The connection probe reads the exact configured portal to confirm the key can
access the intended account. Results are cached for 60 seconds and concurrent
checks share one request. It never creates a payment or exposes credentials.
When a portal configuration is specified, checkout also requires this probe
to succeed. A malformed/missing key, incorrect account, or inaccessible portal
must be resolved before activation.

The restricted key needs the API operations used by this adapter: creating and
reading Checkout Sessions; reading and updating Subscriptions; reading expanded
Invoices; reading Charges for dispute/refund ownership; reading portal
configurations and creating portal sessions. Validate the key against these
operations in a sandbox before enabling production checkout. Do not grant
payout, transfer, refund-write, or account-administration access for this feature.

## Provider and webhook configuration

The Directory adapter pins `2026-09-30.endive`, the current stable version
reported by https://docs.stripe.com/api/versioning on October 4, 2026. The
reviewed Clover-to-Dahlia and Endive changes do not affect the adapter's hosted
UI mode, price/invoice checks, subscription-item period end, or billing anchor
inputs. New sessions use flexible billing and a stable integration identifier;
the persisted generation remains the retry idempotency key.

Endpoint (events from this account, not connected accounts):

`https://chee-chai-chee-backend.onrender.com/api/directory/billing/webhook`

Use the same API version and mode as the backend. Required events:

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `checkout.session.async_payment_failed`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.paid`
- `invoice.payment_failed`
- `invoice.payment_action_required`
- `invoice.marked_uncollectible`
- `charge.refunded`
- `charge.dispute.created`

Subscription changes are independently read from Stripe before application.
A Checkout return page or unverified event never grants a badge. Price, currency,
quantity, payment mode, paid invoice, ownership/generation and period remain
validated. Sandbox payments never grant a public live badge.

For a temporary signed-delivery check against the deployed URL without changing
the live API key, set `KORLIX_DIRECTORY_STRIPE_SANDBOX_WEBHOOK_SECRET`, a random
32-character lowercase hexadecimal `KORLIX_DIRECTORY_STRIPE_SANDBOX_PROBE_ID`,
and an ISO `KORLIX_DIRECTORY_STRIPE_SANDBOX_PROBE_EXPIRES` at most two hours ahead.
The sandbox signing secret must differ from the live endpoint's secret. The
check defaults off and expires automatically. Only a Stripe-signed test-mode
`customer.subscription.updated` event with matching
`metadata.korlix_directory_delivery_probe` records a sanitized in-memory receipt
in `health.sandboxWebhookProbe`. This branch never reads Stripe or the database,
and never grants membership. It verifies network delivery and raw-body signature
handling, not owner checkout or membership activation. Disable the sandbox
endpoint and clear all three variables after checking the receipt.

The prepared portal allows invoice history, payment method changes, and
cancellation at the end of the billing period. Plan/quantity updates and the
public portal login link are disabled. Set the configuration ID explicitly
so later default-portal changes cannot alter Directory billing behavior.

## Verification and activation (October 4, 2026)

- Live Stripe account verification completed; charges and payouts enabled.
- The restricted live runtime credential was verified through the deployed
  adapter and its pinned Endive API before checkout activation.
- Sandbox monthly/yearly Checkout Sessions were created with totals 499/4900
  cents. The monthly hosted Checkout was completed using Stripe's documented
  test card and a synthetic customer: Stripe returned a complete, paid session,
  active subscription, and paid 499-cent invoice. Its browser return to KORLIX
  was verified. The annual session was only created, not paid.
- A separate synthetic sandbox subscription produced an active subscription
  and paid 499-cent invoice. Scheduled cancellation kept the paid period;
  immediate test cleanup produced canceled status. No live customer was charged.
- Actual sandbox subscription responses passed the adapter's membership
  validation for active, scheduled-cancel and canceled cases.
- A sandbox customer portal session was created successfully.
- The hosted monthly customer's portal showed the paid invoice and scheduled
  cancellation at the end of its paid period. Stripe returned `cancel_at`
  equal to the subscription item's period end while `cancel_at_period_end`
  remained false. The adapter now recognizes this portal cancellation shape
  and preserves paid access while displaying renewal as canceled. Actual
  provider responses and a regression check passed. The synthetic subscription
  was then canceled immediately as test cleanup; no live customer was charged.
- The return page now keeps membership guidance in its own banner so the
  asynchronous business search cannot overwrite it. The URL alone never
  confirms payment, activates membership, or grants a badge.
- The deployed return banner was visually checked after the business results
  loaded; membership guidance remained visible.
- Real Stripe-signed sandbox delivery reached the deployed webhook on October
  4 at 19:12:53 UTC. Event `evt_1UMuq8Lx6hd5l5Vohv7XCrd1` was acknowledged,
  with zero pending webhooks reported by Stripe. The expiring delivery check
  recorded receipt without payment-provider reads or membership writes.
  Sandbox endpoint `we_1UMuoaLx6hd5l5VohXmT4K27` was disabled afterward; its
  temporary runtime variables are cleared as part of deployment cleanup.
- Local checks cover credential gating, cached read-only connection probing,
  rejected signatures, asynchronous payment failure, fixed prices, paused
  management, ownership, duplicate/stale observations, and test/live isolation.
- All 29 backend checks passed, including expiring sandbox receipt isolation
  and unchanged live reconciliation through the same webhook route.
- Flutter Directory tests and the release web build passed.
- The user advanced the sandbox clock using the Dashboard's simulation controls
  to November 5. Stripe completed the advance and produced renewal invoice
  `in_1UMv0pLx6hd5l5VoarmSKPM6` with `billing_reason=subscription_cycle`,
  `status=paid` and `amount_paid=499`. Subscription
  `sub_1UMurhLx6hd5l5VoRMxFV3yf` remained active and its paid period extended to
  December 4, 2026 at 17:19:01 UTC. The actual provider response passed the
  adapter's membership validation; the live adapter rejected the test-mode
  response. The synthetic subscription was canceled afterward as cleanup.
- The temporary sandbox delivery variables were confirmed cleared on the
  deployed service. The old Clover endpoint and temporary sandbox endpoint
  remain disabled. The live Endive endpoint
  `we_1UMtFQ22E1oIiTRbqPqBVeqp` is enabled with the required events.

Production checkout was activated with
`KORLIX_DIRECTORY_STRIPE_ENABLED=true` on October 4, 2026. The backend deployment
was live at 19:29 UTC, and the deployed Directory health confirmed
`checkoutEnabled=true`, `paymentsReady=true`, `paymentConnection=verified`,
`livePayments=true`, and a disabled sandbox probe.
The existing approved prices remain USD 4.99/month and USD 49/year. Free listings
remain free. Other KORLIX billing features are outside this integration.

The signed-in business owner opened the live monthly hosted Checkout at 19:57
UTC on October 4. The page displayed USD 4.99 per month. Stripe independently
confirmed a live subscription-mode session with a 499-cent USD total,
`status=open`, `payment_status=unpaid`, and no subscription created. This
confirms owner access and Checkout creation through the deployed restricted
live credential. The session was left unpaid to expire normally.

Completed payments, portal cancellation, signed delivery and renewal checks
used synthetic sandbox objects. No live customer was charged and no paid live
badge activation was exercised. Do not describe the actual paid live lifecycle
as verified until a customer completes it normally.

Live tax configuration was reviewed: no active Stripe Tax registrations were
configured. This activation leaves automatic tax collection disabled and does
not add tax registrations. Applicable registrations and tax treatment must be
confirmed before enabling tax collection.
