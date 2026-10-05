# Hosted Stripe sandbox staging

This is a separate, disabled foundation for durable provider acceptance. It is not the production backend, the saved-result display service, or a public version of the loopback acceptance harness. It does not yet accept payment webhooks, create bookings or Checkout sessions, issue refunds, or serve a customer return flow.

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

Entry point: `backend/test/manual/hosted_stripe_acceptance.mjs`. The isolated dependency directory is `backend/test/manual/hosted-runtime`, with pinned `pg@8.23.1`. Production entry points and dependency manifests are unchanged; staging reuses the existing provider identity adapter behind a GET-only request guard.

- Public `/health` is safe to inspect and always reports checkout, payment connectivity and webhook processing disabled for this staging implementation.
- Missing database or Stripe credentials leave readiness blocked; they do not cause fake successful verification.
- Private status/verification requests require a new service-specific token in the Authorization header. Browser-origin requests and tokens in URLs are rejected.
- The database URL must identify the exact new internal host and database. A private sentinel binds the database to this staging service. Existing unrelated application objects or a mismatched sentinel are refused.
- The sentinel binds the origin, database, expected accounts and encryption-key hash. Control-token rotation or expiry refresh does not change that binding. Bootstrap and verification use a transaction and advisory lock.
- Stripe verification is limited to independent read-only checks of the expected sandbox platform and merchant. A live key or a key for another account cannot establish readiness.
- No booking, Checkout, refund, webhook, OAuth, scheduling-owner, email or calendar operations are available.

## Configuration

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

The dedicated Node 24 service uses auto-deploy off and no environment group. Build with `npm ci --prefix backend/test/manual/hosted-runtime --ignore-scripts --no-audit --no-fund && node --check backend/test/manual/hosted_stripe_acceptance.mjs`; start with `node backend/test/manual/hosted_stripe_acceptance.mjs`. `SKIP_INSTALL_DEPS=true` avoids installing the unrelated root app dependencies.

| Environment variable | Configuration |
| --- | --- |
| `KORLIX_HOSTED_ACCEPTANCE_MODE` | `isolated-postgres-sandbox-v1` |
| `KORLIX_HOSTED_ACCEPTANCE_DATABASE_HOST` | Exact internal host above |
| `KORLIX_HOSTED_ACCEPTANCE_DATABASE_URL` | Dedicated database's Internal Database URL; configured privately in Render |
| `KORLIX_HOSTED_ACCEPTANCE_STRIPE_KEY` | Dedicated restricted key from KORLIX 2MEETU Testing sandbox; configured privately in Render |
| `KORLIX_HOSTED_ACCEPTANCE_TOKEN_HASH` | SHA-256 of a fresh private 32-byte token |
| `KORLIX_HOSTED_ACCEPTANCE_ENCRYPTION_KEY` | Fresh private 32-byte hexadecimal value |
| `KORLIX_HOSTED_ACCEPTANCE_EXPIRES_AT` | Short test-access expiry, at most seven days |
| `KORLIX_HOSTED_ACCEPTANCE_ORIGIN` | Optional explicit origin; otherwise Render's HTTPS external URL |

Do not copy production environment groups, Supabase credentials, provider keys, the local ledger encryption key, control token, CLI config or keyring. No secret values or private links belong in this document or Git.

Identity verification performs only `GET /v1/account` and `GET /v2/core/accounts/{id}` with `configuration.merchant` and `defaults` included. The user's final restricted-key review showed these selected Read permissions:

| Dashboard resource | Selected Read scopes |
| --- | --- |
| Accounts | Own account |
| Accounts v2 | Own account and connected accounts |
| Merchant Configuration | Own account and connected accounts |

Recipient Configuration was removed and no Write permissions were selected. The origin of the mirrored connected-account selections was not established; this records the reviewed configuration that passed, not proof that every selection is required or an automatic dependency. Checkout/refund writes are not required by this staging implementation. A generic HTTP 503 `readiness_verification_failed` response does not identify its cause: permissions, provider/network failures, identity mismatches and database failures can share that response. Do not substitute a live or production-attached key to pass the check.

## Remaining acceptance work

Ten focused tests pass in `backend/test/manual/hosted_stripe_acceptance.test.mjs`. They cover isolated configuration, database guard creation/restart and refusal of foreign objects, private HTTP access, absent payment routes, missing credentials, serialized identity reads, mismatched Stripe identity, expiry and sanitized errors. Those tests use provider and PostgreSQL test doubles; the real hosted database and Stripe identity evidence is recorded separately above. An additional local PGlite catalog smoke check exercised guard creation and matching restart, with only the database-name identity query substituted for the dedicated fixture name.

Database and credential identity verification are complete. Next, implement and review the durable scheduling ledger, tightly scoped synthetic booking provisioning, Stripe-signed webhook handling, private customer return page and controlled one-run Checkout issuance. Then run one new genuine sandbox checkout to establish the new paid transition and actual HTTPS Stripe redirect. Existing refunded records must not be reset, relabeled unpaid or treated as a new transition. Until that test passes, paid-booking and redirect acceptance remain open. All production checkout flags remain false.
