# Hosted Stripe sandbox staging

This isolated runtime implements durable sandbox booking storage, a Stripe-signed webhook receiver, an HTTPS customer return page, and private controls for one synthetic USD 1.00 Checkout and full refund. The hosted schema upgrade, identity verification and HTTPS boundaries have passed; the local suite passed 64/64 tests. Payment issuance remains paused pending endpoint setup and the genuine sandbox acceptance run below.

The credentials last verified on the hosted service provide identity reads only. A new hosted payment, its Stripe-to-customer return, and its full refund have not yet been proven. Production checkout remains paused, and the separate saved-result display is not payment acceptance evidence.

## Why a separate runtime is needed

Both genuine sandbox payments in the existing local ledger are fully refunded. Their old Checkout sessions retain the `.invalid` return URLs. Replaying those completion events can test terminal-state idempotency, but cannot prove a new paid-booking transition or a Stripe-to-booking redirect. On 2026-10-05 at 16:27 UTC, the attempted terminal replay stopped at CLI identity validation: the dedicated configuration reported `authenticated:false`. No listener, harness, resend, new payment or refund ran. The original ledger was unchanged, and the temporary copy was removed.

The Stripe connector currently exposes only the original Korlix INC live account and sandbox. The isolated testing sandbox is separate. CLI OAuth credentials are not exported to Render. The user entered a dedicated sandbox restricted API key directly in the hosted service's Render environment settings; its identity verification passed on 2026-10-05 at 23:17:35.121 UTC.

## Isolated identities and storage

| Item | Value |
| --- | --- |
| Expected sandbox platform | `acct_1UN1QuLwavBaepoe` |
| Expected test merchant | `acct_1UN1WiLwavcz7g46` |
| Render workspace | `tea-d8cskuf7f7vs73emq1p0` |
| Postgres instance | `dpg-db1svtm0tbcc73caq380-a` |
| Postgres display name | `korlix-2meetu-acceptance` |
| Internal database host | `dpg-db1svtm0tbcc73caq380-a` |
| Database name | `korlix_2meetu_acceptance` |
| Region / version / plan | Ohio / PostgreSQL 17 / Free |
| Created | 2026-10-05 16:27:34 UTC |
| Expires | 2026-11-04 16:27:34 UTC |

External database access is disabled (`ipAllowList: []`). Render reports the instance available. Its hosted MCP SQL tool cannot query databases with external access disabled; this restriction remains intact. The new web service uses the internal connection. Database bootstrap completed at 2026-10-05 23:16:42.854 UTC, and authenticated runtime verification subsequently passed.

The Free database is temporary, expires after 30 days, and has no managed backups. Preserve any future test evidence before expiry. Do not upgrade or attach production data automatically. See [Render Free instance limits](https://render.com/docs/free).

## Runtime contract

Entry point: `backend/test/manual/hosted_stripe_acceptance.mjs`. Supporting modules are `hosted_acceptance_database.mjs`, `hosted_acceptance_flow.mjs` and `hosted_acceptance_return.mjs` in the same directory. The isolated dependency directory is `backend/test/manual/hosted-runtime`, with pinned `pg@8.23.1`. Production entry points and dependency manifests are unchanged. The sandbox reuses the production scheduling SQL, connected-payment handlers and Stripe adapter behind an exact request allowlist; it does not mount the full production routing surface.

### Durable database and one-booking boundary

- The database URL must identify the exact dedicated internal host and database. The existing private sentinel binds the origin, database, expected accounts and encryption-key hash. Control-token rotation or expiry refresh does not alter this binding.
- `KORLIX_HOSTED_ACCEPTANCE_PAYMENT_RUNTIME=scheduling-v2` opts into the scheduling schema upgrade. Before upgrading, the runtime validates the stage-one sentinel and refuses unrelated objects. It checksum-verifies the original `20260930152919_scheduling_engine.sql` and `20260930163605_scheduling_connected.sql` migrations, then changes only their terminal privilege blocks in memory. The source migration files remain unchanged.
- The dedicated database gets minimal synthetic `auth.users` and `public.user_profiles` tables. Scheduling functions remain `SECURITY INVOKER`, table RLS stays enabled, and public grants are revoked. The runtime uses the dedicated table-owning database user and creates no PostgreSQL roles. This exercises production scheduling behavior, **not production role/ACL separation**: table ownership bypasses non-FORCE RLS, including the production separation around audit mutation.
- A versioned schema manifest and catalog fingerprint reject unrelated objects or schema drift after restart. Bootstrap uses a transaction and advisory lock; payment commands use the same lock keys with a session lock to serialize the complete operation.
- One permanent run row owns one synthetic host, event and booking. The booking association is committed before outbound payment effects. Repeated booking requests return that booking; they do not mint another test booking. Stable idempotency keys and the persisted, encrypted Checkout request support recovery without widening the test scope.
- The original hold lasts 50 minutes; Checkout expires 40 minutes after creation of the payment ledger entry. Retries and restarts do not extend either deadline. A checkout attempt without enough remaining time is refused.
- After the database upgrade, do not switch this database back to the stage-one runtime or deploy stage-one-only code. Pause new issuance through the durable `pause` control. A fresh database would require a separately reviewed setup.

### Stripe and customer behavior

- Every provider request is restricted to Stripe, the pinned API version `2026-09-30.endive`, the expected sandbox platform or connected merchant, and the owned test booking. Live keys and other account identities cannot establish readiness. Checkout and refund writes are bounded to USD 1.00 and the synthetic guest; application fees, transfers and `on_behalf_of` fields are refused.
- New Checkout issuance requires the durable enable flag, unexpired test access, fresh identity checks and matching endpoint configuration. Missing credentials or failed checks leave readiness blocked. No application or platform transaction fee is set.
- Webhook handling verifies the raw-body signature and requires the expected connected merchant, `livemode:false`, an allowed event type and the owned Checkout Session or PaymentIntent. Payment observations use independent Stripe reads. Processed event receipts make duplicate deliveries idempotent.
- Endpoint configuration evidence and connected-account delivery evidence are separate. `GET /v1/webhook_endpoints/{id}` verifies the endpoint ID, URL, enabled status, sandbox mode, version and exact event list. Its documented response has no `connect` flag; its `application` field is not a documented equivalent. A valid signed event from the expected merchant establishes connected-delivery evidence.
- Stripe success and cancel URLs both use `/book/manage#BOOKING_ID.MANAGE_TOKEN`. The fragment stays in the browser rather than the request URL. Same-origin JavaScript posts the booking ID and private token to the customer-status endpoint, which reads only the saved booking ledger. Returning from Stripe or refreshing the page does not contact Stripe, reconcile a payment or infer success from the URL.
- Customer pages show explicit sandbox/payment state, use local assets, escaping, a restrictive CSP, `no-store` and `no-referrer`. They make no booking-email or calendar-delivery claims. No public booking creation, OAuth, scheduling-owner, email, calendar or general worker controls are exposed.
- Expiry stops enable, booking and Checkout creation. Existing signed events, private status/pause/refund controls, refund retry processing and customer ledger reads remain available to settle and inspect the owned booking.

### Routes

| Method and route | Purpose |
| --- | --- |
| `GET /health` | Public readiness and block reasons; readiness does not claim acceptance has passed |
| `GET /book/manage` | Customer return shell; booking credentials are supplied through its URL fragment |
| `GET /acceptance/assets/return.css` and `GET /acceptance/assets/return.js` | Local customer-page assets |
| `POST /acceptance/customer/status` | Same-origin, rate-limited ledger read requiring the owned booking ID and private manage token |
| `POST /acceptance/payments/webhook` | Stripe-signed events for the expected sandbox merchant and booking |
| `POST /acceptance/status` | Private durable run, booking and event-receipt status |
| `POST /acceptance/verify` | Private database and read-only platform/merchant identity verification |
| `POST /acceptance/enable` | Fresh identity/endpoint checks, synthetic host/event setup and durable issuance enable |
| `POST /acceptance/pause` | Durable pause of new issuance |
| `POST /acceptance/book` | Create or reuse the sole synthetic booking |
| `POST /acceptance/checkout` | Create or reuse its bounded Checkout Session |
| `POST /acceptance/refund` | Request and process its full sandbox refund |
| `POST /acceptance/tick` | Retry pending refund work for the owned booking |
| `POST /acceptance/fee-proof` | Read the owned PaymentIntent and expanded Charge to verify zero platform fees |

Private controls require the service-specific bearer token in the Authorization header and an empty JSON body. Browser-origin private commands and credentials in URLs are rejected. All routes reject query strings; error responses are sanitized.

## Historical deployment and verification evidence

These records describe the identity-only stage-one deployments. Their disabled or absent payment routes are historical observations, not the current scheduling-v2 route contract above.

### Deployment approval blocker — 2026-10-05 UTC

Implementation and ten focused tests are committed as `1941e6acc84c1cdc39c37fd93823bbf91ef2c1b8`. Creating the intended Free Ohio web service `korlix-2meetu-payment-sandbox` was rejected by automatic approval review before a service was created. The stated reason was transmission of a fresh bearer-token hash and encryption key to an external Render destination without explicit approval for that secret-bearing deployment. No alternate route or reduced-guard deployment was attempted. The dedicated database already existed; at that point, the web deployment was pending user approval. No live Stripe key, production credential or database URL was included in the rejected request.

The concrete deployment uses the existing GitHub repository and release branch, auto-deploy off, Node 24, the isolated build/start commands below, and newly generated service-specific security values. It starts without a database URL or Stripe key and exposes only blocked health plus authenticated identity-readiness commands.

### Approved deployment — 2026-10-05 17:00 UTC

The user explicitly approved this secret-bearing Free staging deployment at 16:58:36 UTC. Render created `korlix-2meetu-payment-sandbox`, service `srv-db1tevlg1s2s73bn4s60`, with fresh service-specific security values and no database URL or Stripe key. Deploy `dep-db1tevtg1s2s73bn4t70` of commit `d771d2cc44b0fbb8dcc602406ea9f3fcdeb236ac` became live at 17:00:10 UTC. The Free Ohio Node service has auto-deploy off and no shared environment group. This resolves the deployment-approval blocker above; provider acceptance remains open.

- [Service Dashboard](https://dashboard.render.com/web/srv-db1tevlg1s2s73bn4s60)
- [Environment configuration](https://dashboard.render.com/web/srv-db1tevlg1s2s73bn4s60/env)
- [Dedicated database](https://dashboard.render.com/d/dpg-db1svtm0tbcc73caq380-a)
- [Public health](https://korlix-2meetu-payment-sandbox.onrender.com/health)

Production scheduling, web billing and Directory health each returned HTTP 200 and `checkoutEnabled:false` at 16:59 UTC. The new service's error-log query through 17:00:49 UTC returned no entries. Production services and credentials were not changed.

Nine live HTTPS checks passed at 17:02:06 UTC: health and authenticated private status returned 200; missing authentication returned 401; a browser Origin returned 403; URL-token, webhook, checkout and customer booking routes returned 404; private verification without the database URL returned 503. All responses used `Cache-Control:no-store`. Health reports missing database credential, missing Stripe test key and payment runtime not implemented. Checkout, payment connectivity and webhooks are all false. This verifies deployed staging boundaries, not database bootstrap or Stripe identity. No provider operation ran.

### Database and sandbox identity verified — 2026-10-05 23:17 UTC

The user configured the dedicated Internal Database URL and restricted sandbox key directly in this service's Environment page. Deploy `dep-db22vjss728c73assmi0` of commit `1ab9451cac746f20a2e1925ab11100d54b256a63` became live at 23:16:44.178995 UTC. The database guard was bootstrapped at 23:16:42.854 UTC. No Stripe secret values were returned to the assistant or recorded in verification evidence.

Authenticated `POST /acceptance/verify` returned HTTP 200 with `databaseReady:true` and `identityVerified:true`. Its evidence matched platform `acct_1UN1QuLwavBaepoe`, merchant `acct_1UN1WiLwavcz7g46`, `livemode:false`, `source:accounts_v2`, `cardPayments:active` and `payouts:active`. Both `identity.checkedAt` and `database.lastVerifiedAt` were `2026-10-05T23:17:35.121Z`.

The only remaining blocker was `payment_runtime_not_implemented`. Readiness remained `blocked`, with `checkoutEnabled:false`, `paymentsConnected:false` and `webhookEnabled:false`. This verifies the hosted database and sandbox identity access; it does not establish payment, webhook or customer-redirect acceptance.

## Scheduling-v2 deployment evidence

### Upgrade blocked — 2026-10-05 23:44 UTC

Deploy `dep-db23c6b0hr2s73bbh2l0` of commit `ae1b1c4bcb2becd71306d93f798b254243e6b201` became live at `2026-10-05T23:44:08.382813Z`, with `KORLIX_HOSTED_ACCEPTANCE_PAYMENT_RUNTIME=scheduling-v2` configured. The hosted `/health` response reported `databaseReady:false`, and authenticated private status reported `database:null`. The upgrade failed closed before a booking was created. The cause was not established by those initial responses; subsequent diagnostics are recorded below.

The webhook signing secret and endpoint ID are still missing, and the existing identity-only restricted key is unchanged. This deployment does not establish a successful hosted schema upgrade, payment, signed event delivery, redirect or refund.

### Default-privilege diagnosis and correction — 2026-10-06 00:00 UTC

Diagnostic commit `ae93b9101aff6996c1404c5b70c2ef4f395a4cba` identified the database rejection as `catalog_privileges`. The first ACL correction, `8ef3222`, remained blocked: diagnostics showed four default-ACL entries containing 15 foreign grants, while actual table, function and column foreign-grant counts were all zero.

Correction `03856ab34ed992b43d75236158d87e3bbba731f2` scopes the default-ACL denial to the current object-creating role. It continues to fingerprint all default-ACL entries and requires zero foreign grants on the actual application tables, functions and columns. This follows [PostgreSQL 17 default-privilege semantics](https://www.postgresql.org/docs/17/sql-alterdefaultprivileges.html): new objects use the current creator's defaults, not defaults inherited from other roles. Focused tests cover allowing another creator's defaults and rejecting later drift. The full local suite passed **64/64 tests**.

Deploy `dep-db23k73bc2fs73f436gg` for correction `03856ab34ed992b43d75236158d87e3bbba731f2` was created at `2026-10-06T00:00:28.664417Z` and became live at `2026-10-06T00:01:09.600047Z`. Hosted verification then passed as recorded below.

### Hosted ledger and HTTPS boundaries verified — 2026-10-06 00:02 UTC

Eleven HTTPS checks completed at `2026-10-06T00:02:07.509723Z`. Public health returned HTTP 200 with `databaseReady:true`. Authenticated `POST /acceptance/verify` returned HTTP 200 with `identityVerified:true`, checked at `2026-10-06T00:01:33.245Z`, matching the expected platform and merchant with `livemode:false`, `source:accounts_v2`, `cardPayments:active` and `payouts:active`.

The durable schema reported `schemaVersion:scheduling-ledger-v1` and run `33290d13-b099-474b-b13d-56f0960c1454`. Event and booking IDs were null, `enabled:false`, `outboundCount:0`, `receivedEvents:[]` and `booking:null`. The flow outbound counter excludes the separate identity-verification reads. No Checkout or refund was created. The only reported health blockers were `webhook_signing_secret_missing`, `webhook_endpoint_id_missing` and `sandbox_checkout_paused`.

Unauthenticated private access returned 401; a browser Origin on private controls returned 403; an unknown customer booking returned 404; the return HTML, CSS and JavaScript returned 200; a query-string token returned 404. Every checked response used `Cache-Control:no-store`. These results establish the hosted ledger, identity access and HTTP boundaries. They do not establish endpoint configuration, a genuine payment, signed connected-account delivery, an actual Stripe return or a refund.

The production backend still had auto-deploy off and live commit `d682b32acde91522b570ac8c6ba9a24ccb8074aa` (deploy `dep-db22qkcs728c73asc5b0`, live `2026-10-05T23:06:08.590359Z`); these sandbox branch pushes caused no new production deployment.

## Current configuration

The dedicated Node 24 service uses auto-deploy off and no environment group. Build with `npm ci --prefix backend/test/manual/hosted-runtime --ignore-scripts --no-audit --no-fund && node --check backend/test/manual/hosted_stripe_acceptance.mjs`; start with `node backend/test/manual/hosted_stripe_acceptance.mjs`. `SKIP_INSTALL_DEPS=true` avoids installing the unrelated root app dependencies.

| Environment variable | Configuration |
| --- | --- |
| `KORLIX_HOSTED_ACCEPTANCE_MODE` | `isolated-postgres-sandbox-v1` |
| `KORLIX_HOSTED_ACCEPTANCE_PAYMENT_RUNTIME` | `scheduling-v2` opts into the durable scheduling upgrade; issuance remains paused until the private enable control succeeds |
| `KORLIX_HOSTED_ACCEPTANCE_DATABASE_HOST` | Exact internal host above |
| `KORLIX_HOSTED_ACCEPTANCE_DATABASE_URL` | Dedicated database's Internal Database URL; configured privately in Render |
| `KORLIX_HOSTED_ACCEPTANCE_STRIPE_KEY` | Dedicated restricted key from KORLIX 2MEETU Testing sandbox; configured privately in Render |
| `KORLIX_HOSTED_ACCEPTANCE_WEBHOOK_SECRET` | The new endpoint's `whsec_…` signing secret; configured privately in Render, separate from the API key |
| `KORLIX_HOSTED_ACCEPTANCE_WEBHOOK_ENDPOINT_ID` | Exact new sandbox `we_…` endpoint ID; the current runtime verifies it through the v1 Webhook Endpoints API |
| `KORLIX_HOSTED_ACCEPTANCE_TOKEN_HASH` | SHA-256 of a fresh private 32-byte token |
| `KORLIX_HOSTED_ACCEPTANCE_ENCRYPTION_KEY` | Fresh private 32-byte hexadecimal value |
| `KORLIX_HOSTED_ACCEPTANCE_EXPIRES_AT` | Short test-access expiry, at most seven days |
| `KORLIX_HOSTED_ACCEPTANCE_ORIGIN` | Optional explicit origin; otherwise Render's HTTPS external URL |

Do not copy production environment groups, Supabase credentials, provider keys, the local ledger encryption key, control token, CLI config or keyring. No secret values or private links belong in this document or Git.

The private identity verification performs only `GET /v1/account` and `GET /v2/core/accounts/{id}` with `configuration.merchant` and `defaults` included. The user's last saved restricted-key review showed these selected Read permissions:

| Dashboard resource | Selected Read scopes |
| --- | --- |
| Accounts | Own account |
| Accounts v2 | Own account and connected accounts |
| Merchant Configuration | Own account and connected accounts |

Recipient Configuration was removed and no Write permissions were selected. The origin of the mirrored connected-account selections was not established; this records the reviewed configuration that passed, not proof that every selection is required or an automatic dependency. Those identity-only permissions do not authorize the new Checkout/refund flow. A generic HTTP 503 `readiness_verification_failed` response does not identify its cause: permissions, provider/network failures, identity mismatches and database failures can share that response. Do not substitute a live or production-attached key to pass the check.

### iPad setup for the new payment flow

Use **KORLIX 2MEETU Testing sandbox**, platform `acct_1UN1QuLwavBaepoe`, throughout. Keep the existing identity reads. Under **API keys**, open the dedicated key's overflow menu, choose **Edit key/permissions**, and add these resource permissions:

| Dashboard resource | In your account | In connected accounts | Purpose |
| --- | --- | --- | --- |
| Webhook Endpoints, Event Destinations | Read | None | Read the expected endpoint configuration |
| Checkout Sessions | None | Write | Create and read the owned test Checkout Session |
| Charges and Refunds | None | Write | Read its charge and create/read its full refund |
| Payment Intents | None | Read | Read the payment intent for payment/fee evidence |

The current [Stripe permissions catalog](https://docs.stripe.com/stripe-apps/reference/permissions) groups refunds under **Charges and Refunds**. Write includes Read. Apply permissions to individual resources rather than whole categories. No documented Checkout dependency was found requiring extra Products, Prices, Customers or Payment Intents Write permissions; if the UI adds dependent permissions, review the displayed explanation instead of assuming why they appeared. Editing permissions does not require replacing the key's existing value in Render. See [restricted API keys](https://docs.stripe.com/keys/restricted-api-keys).

Then create the endpoint:

1. Open **Workbench → Webhooks → Add destination** (or **Create an event destination**).
2. Set **Events from** to **Connected accounts**.
3. Select snapshot events and API version **2026-09-30.endive**. Select exactly `checkout.session.completed`, `checkout.session.expired`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed` and `charge.refunded`.
4. Choose **Webhook endpoint** and enter `https://korlix-2meetu-payment-sandbox.onrender.com/acceptance/payments/webhook`.
5. Create the destination. Open its details and copy the endpoint ID. Reveal its signing secret and paste it directly into `KORLIX_HOSTED_ACCEPTANCE_WEBHOOK_SECRET` on the [payment sandbox's Render Environment page](https://dashboard.render.com/web/srv-db1tevlg1s2s73bn4s60/env). Set `KORLIX_HOSTED_ACCEPTANCE_WEBHOOK_ENDPOINT_ID` to the copied `we_…` ID. Keep secret values out of chat, screenshots and Git.

If the current Dashboard creates a destination with a different ID format, review that object before changing the runtime configuration. The implemented verifier supports v1 `we_…` endpoints. Stripe's [v2 Event Destination object](https://docs.stripe.com/api/v2/core/event_destinations/object) exposes `events_from`, `event_payload` and `snapshot_api_version`, but v2 retrieval is not interchangeable with the implemented v1 verifier.

The [v1 endpoint response](https://docs.stripe.com/api/webhook_endpoints/retrieve) omits the creation-time `connect` flag. The Dashboard selection establishes the intended setup; actual [connected-account delivery](https://docs.stripe.com/connect/webhooks) must be demonstrated by a verified signed event with the expected merchant's top-level `account` value. Neither a configured endpoint nor a successful identity check proves payment acceptance.

## Remaining acceptance work

The historical stage-one suite passed ten focused tests in `backend/test/manual/hosted_stripe_acceptance.test.mjs`, covering isolated configuration, database guards, private access, absent payment routes, identity reads, expiry and sanitized errors. It used provider and PostgreSQL test doubles. A separate local PGlite catalog smoke check exercised guard creation and matching restart, substituting only the dedicated fixture's database-name identity query. These are historical results, not a test count for scheduling-v2.

| New scheduling-v2 evidence | Status |
| --- | --- |
| Reviewed code and focused test counts | 64/64 tests passed across database, payment flow, HTTP integration, return UI and stage-one boundaries, including the corrected creator-specific default-ACL checks. Database/flow/HTTP fixtures execute real PostgreSQL catalogs and production scheduling SQL in PGlite; Stripe is mocked. Independent review found no remaining critical isolation or locking issues. |
| Hosted deployment ID, commit and live timestamp | Commit `03856ab34ed992b43d75236158d87e3bbba731f2`, deploy `dep-db23k73bc2fs73f436gg`, live `2026-10-06T00:01:09.600047Z` |
| Hosted schema upgrade, identity and HTTP boundaries | Passed: `scheduling-ledger-v1`, expected sandbox identities, paused empty run and 11 HTTPS checks completed `2026-10-06T00:02:07.509723Z` |
| Webhook endpoint configuration | Pending: webhook secret and endpoint ID are not yet configured |
| New genuine sandbox payment and signed completion delivery | Not yet proven |
| Actual Stripe-to-HTTPS return and ledger-only status display | Not yet proven |
| Duplicate delivery, restart recovery and full refund | Not yet proven for the new hosted run |
| Zero platform transaction fee evidence | Not yet proven for the new hosted run |

The next acceptance run must use the new owned booking, matching signed events and the actual Stripe redirect. Existing refunded records must not be reset, relabeled unpaid or treated as a new paid transition. Record provider IDs, signed-delivery evidence, resulting ledger state and sanitized test output without private links or secrets. All production checkout flags remain false.
