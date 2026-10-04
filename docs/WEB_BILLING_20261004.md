# KORLIX web subscriptions — October 4, 2026

Owner-confirmed offer: Pro USD 34.99/month; Ultra Premium USD 124.99/month. Enterprise remains Contact Sales. Basic and access to all AI characters remain free. AI GAS, Music Studio, Directory verification and paid 2MEETU bookings have separate billing.

## Implementation

`backend/web_billing/` mounts authenticated status, refresh, checkout, close-unpaid-checkout, portal and cancellation routes under `/api/billing/web`. The raw-body Stripe endpoint is `/api/billing/web/webhook`. Hosted Checkout uses immutable server price IDs, quantity one, flexible monthly billing, automatic payment-method selection and generation-bound idempotency keys. Recurring consent is required before creation. Checkout URLs and portal URLs are validated against their respective Stripe hosts.

Only independently retrieved Stripe subscriptions and paid invoices grant access. Ownership, generation, customer, environment, catalog price, quantity, currency and interval must match. An unpaid renewal cannot extend access. Paid upgrades accept prorated invoice amounts. Scheduled cancellation preserves the paid period; final cancellation, pause, refund/dispute hold and expiry remove the web grant. Delayed events read current Stripe state. Refund/dispute holds persist until an operator resolves the underlying case. Do not clear a hold merely because a subscription says active.

The migration `supabase/migrations/20261004203621_web_plan_subscriptions.sql` was applied before deploying the server. Billing records and RPCs are service-role-only with RLS and browser grants revoked. Reconciliation leases prevent concurrent stale writes. The server reconciles due accounts every minute, normally once per account per ten minutes. Profile reads also enforce expiry. Existing custom/Enterprise grants and native entitlements are composed with web access. Apple reconciliation resolves the combined tier in the same transaction; native verification still accepts legitimate receipts.

The Flutter web app opens Settings → Plans & Billing. `/app/?billing=plans` opens the panel after login. Return URLs refresh server state and never grant access themselves. In-flight responses and dialogs are discarded when the signed-in account/session changes. Native store billing stays separate and blocks a second purchase while a web subscription exists. Website pricing and subscription terms disclose recurring prices, allowances, cancellation and support.

## Live configuration

Stripe account: `acct_1UMs8D22E1oIiTRb` (Korlix INC).

| Setting | Value |
| --- | --- |
| API version | `2026-09-30.endive` |
| Pro price | `price_1UMwjD22E1oIiTRbw1koH8k7` |
| Ultra price | `price_1UMwjc22E1oIiTRbpLiZyEFh` |
| Portal configuration | `bpc_1UMwkA22E1oIiTRbU9EAlMkB` |
| Webhook | `we_1UMwlF22E1oIiTRbf4nbm4hl` |

The portal exposes invoices, payment-method changes, period-end cancellation and price changes between the two products. Quantity changes and public portal login are disabled. Price changes use `always_invoice`; the portal displays the resulting charge/credit.

Backend environment names (never commit their secret values):

- `KORLIX_WEB_STRIPE_ENABLED`
- `KORLIX_WEB_STRIPE_PRO_PRICE_ID`
- `KORLIX_WEB_STRIPE_ULTRA_PRICE_ID`
- `KORLIX_WEB_STRIPE_PORTAL_CONFIGURATION_ID`
- `KORLIX_WEB_STRIPE_WEBHOOK_SECRET`
- `KORLIX_WEB_STRIPE_SECRET_KEY`, or explicit `KORLIX_WEB_STRIPE_USE_DIRECTORY_CREDENTIAL=true` to reuse the existing server credential.

Health: `/api/billing/web/health`. Expect configured/checkoutEnabled/livePayments true and connection `verified`. Authentication remains required for every account action. The Directory keeps its own webhook and portal.

Automatic tax is not enabled. Before enabling collection, the owner should confirm applicable registrations and configure Stripe Tax accordingly. No registration or tax jurisdiction was invented by this release.

## Verification

- 25 Node/PGlite tests: actual migration and RLS permissions, ownership, immutable checkout retries, duplicate subscription prevention, signatures/mode, event deduplication, leases, paid upgrades, failed renewal, expiration, cancellation, persistent risk holds, Apple/web composition, and client-controlled price rejection.
- 9 Flutter client/widget tests: 320/390/1440px layouts, large text, explicit recurring consent, account-switch dismissal, late response rejection, return verification and redirect allowlists.
- Flutter billing/client analysis: no issues. Release JavaScript web build and visual review of phone/desktop layouts.
- Sandbox `acct_1UMI5OLx6hd5l5Vo`: hosted Checkout created unpaid; Pro subscription paid 3499 cents; upgrade to Ultra paid a 9000-cent proration; scheduled cancellation retained active status; final cancellation returned canceled. Actual provider objects passed the production normalizers. Portal session creation succeeded. Test subscription `sub_1UMwbsLx6hd5l5VoxeyX4o4O` was canceled after verification. No production test customers, subscriptions, charges or entitlement records were created.
- A sandbox decline token was rejected by Stripe during attachment. Failed-renewal entitlement behavior is covered in local lifecycle tests; a clock-advanced renewal was not performed through the available connector.

## Operations and rollback

Deploy the migration first, publish the backend branch, then merge the six backend configuration values into Render. An environment update triggers a backend deployment even when automatic Git deployment is off; do not start a duplicate deployment. Deploy the frontend branch separately. Check the configured service commit, billing health, protected routes, unsigned webhook rejection, public pricing and app assets.

To pause new purchases, set `KORLIX_WEB_STRIPE_ENABLED=false`; keep the key, webhook secret, prices and portal configuration so existing membership management and reconciliation continue. Prefer this switch over reverting code after live subscribers exist. Never drop billing tables or erase payment bindings to resolve a failed checkout. Retain webhook processing for already billed customers.

Supabase advisors report the expected no-policy informational notice for the two server-only tables; grants were independently checked. Other pre-existing database findings were outside this billing change: a CRM SECURITY DEFINER view, publicly executable legacy custom-access/video RPCs, mutable search paths and disabled leaked-password protection. Follow-up guidance: https://supabase.com/docs/guides/database/database-linter?lint=0010_security_definer_view and https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable . These findings do not justify granting browser access to the new billing records.

Live paid checkout completion remains an owner acceptance check; sandbox success is not evidence of a real production charge.
