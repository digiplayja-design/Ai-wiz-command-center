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

The prepared portal allows invoice history, payment method changes, and
cancellation at the end of the billing period. Plan/quantity updates and the
public portal login link are disabled. Set the configuration ID explicitly
so later default-portal changes cannot alter Directory billing behavior.

## Verification and remaining activation work (October 4, 2026)

- Live Stripe account verification completed; charges and payouts enabled.
- Sandbox monthly/yearly Checkout Sessions were created with totals 499/4900
  cents. They remain unpaid and expire automatically; this was session creation,
  not browser Checkout completion.
- A separate synthetic sandbox subscription produced an active subscription
  and paid 499-cent invoice. Scheduled cancellation kept the paid period;
  immediate test cleanup produced canceled status. No live customer was charged.
- Actual sandbox subscription responses passed the adapter's membership
  validation for active, scheduled-cancel and canceled cases.
- A sandbox customer portal session was created successfully.
- Local checks cover credential gating, cached read-only connection probing,
  rejected signatures, asynchronous payment failure, fixed prices, paused
  management, ownership, duplicate/stale observations, and test/live isolation.
- Flutter Directory tests and the release web build passed.

Still required: restricted server credential entry, validation through the
deployed adapter with its pinned HTTP API version, complete hosted Checkout and
signed webhook delivery into the application, renewal time-travel testing, and
review of tax configuration. The connector exposed test-clock creation but did
not expose advancement during this session, so renewal simulation is not yet
verified. Account connection to ChatGPT does not supply Render with its own
runtime API credential.

Keep production checkout and the new webhook endpoint paused until those
checks are complete. The previous Clover endpoint remains disabled; only the
new Endive endpoint should be enabled at activation. Automatic tax is not
configured by this change; confirm applicable registrations and tax treatment
before enabling tax collection.
