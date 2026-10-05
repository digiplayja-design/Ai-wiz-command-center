# Hosted Stripe sandbox staging

This is a separate, disabled foundation for durable provider acceptance. It is not the production backend, the saved-result display service, or a public version of the loopback acceptance harness. It does not yet accept payment webhooks, create bookings or Checkout sessions, issue refunds, or serve a customer return flow.

## Why a separate runtime is needed

Both genuine sandbox payments in the existing local ledger are fully refunded. Their old Checkout sessions retain the `.invalid` return URLs. Replaying those completion events can test terminal-state idempotency, but cannot prove a new paid-booking transition or a Stripe-to-booking redirect. On 2026-10-05 at 16:27 UTC, the attempted terminal replay stopped at CLI identity validation: the dedicated configuration reported `authenticated:false`. No listener, harness, resend, new payment or refund ran. The original ledger was unchanged, and the temporary copy was removed.

The Stripe connector currently exposes only the original Korlix INC live account and sandbox. The isolated testing sandbox is separate. CLI OAuth credentials are not exported to Render. The hosted service needs a dedicated sandbox restricted API key, entered directly in Render's environment settings.

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

External database access is disabled (`ipAllowList: []`). Render reports the instance available. Its hosted MCP SQL tool cannot query databases with external access disabled; this restriction remains intact. The new web service will use the internal connection. Database identity and bootstrap still require runtime verification after its internal URL is configured.

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

Implementation and ten focused tests are committed as `1941e6acc84c1cdc39c37fd93823bbf91ef2c1b8`. Creating the intended Free Ohio web service `korlix-2meetu-payment-sandbox` was rejected by automatic approval review before a service was created. The stated reason was transmission of a fresh bearer-token hash and encryption key to an external Render destination without explicit approval for that secret-bearing deployment. No alternate route or reduced-guard deployment was attempted. The dedicated database already exists; the web deployment remains pending user approval. No live Stripe key, production credential or database URL was included in the rejected request.

The concrete deployment uses the existing GitHub repository and release branch, auto-deploy off, Node 24, the isolated build/start commands below, and newly generated service-specific security values. It starts without a database URL or Stripe key and exposes only blocked health plus authenticated identity-readiness commands.

### Approved deployment — 2026-10-05 17:00 UTC

The user explicitly approved this secret-bearing Free staging deployment at 16:58:36 UTC. Render created `korlix-2meetu-payment-sandbox`, service `srv-db1tevlg1s2s73bn4s60`, with fresh service-specific security values and no database URL or Stripe key. Deploy `dep-db1tevtg1s2s73bn4t70` of commit `d771d2cc44b0fbb8dcc602406ea9f3fcdeb236ac` became live at 17:00:10 UTC. The Free Ohio Node service has auto-deploy off and no shared environment group. This resolves the deployment-approval blocker above; provider acceptance remains open.

- [Service Dashboard](https://dashboard.render.com/web/srv-db1tevlg1s2s73bn4s60)
- [Environment configuration](https://dashboard.render.com/web/srv-db1tevlg1s2s73bn4s60/env)
- [Dedicated database](https://dashboard.render.com/d/dpg-db1svtm0tbcc73caq380-a)
- [Public health](https://korlix-2meetu-payment-sandbox.onrender.com/health)

Production scheduling, web billing and Directory health each returned HTTP 200 and `checkoutEnabled:false` at 16:59 UTC. The new service's error-log query through 17:00:49 UTC returned no entries. Production services and credentials were not changed.

Nine live HTTPS checks passed at 17:02:06 UTC: health and authenticated private status returned 200; missing authentication returned 401; a browser Origin returned 403; URL-token, webhook, checkout and customer booking routes returned 404; private verification without the database URL returned 503. All responses used `Cache-Control:no-store`. Health reports missing database credential, missing Stripe test key and payment runtime not implemented. Checkout, payment connectivity and webhooks are all false. This verifies deployed staging boundaries, not database bootstrap or Stripe identity. No provider operation ran.

Next, enter the new database's **Internal Database URL** as `KORLIX_HOSTED_ACCEPTANCE_DATABASE_URL`, and a restricted test key from **KORLIX 2MEETU Testing sandbox** as `KORLIX_HOSTED_ACCEPTANCE_STRIPE_KEY`, directly in this service's Environment page. Save and deploy the environment change, then run authenticated readiness verification. Keep secret values out of chat and Git. Identity verification will still leave the payment runtime disabled.

The dedicated Node 24 service uses auto-deploy off and no environment group. Build with `npm ci --prefix backend/test/manual/hosted-runtime --ignore-scripts --no-audit --no-fund && node --check backend/test/manual/hosted_stripe_acceptance.mjs`; start with `node backend/test/manual/hosted_stripe_acceptance.mjs`. `SKIP_INSTALL_DEPS=true` avoids installing the unrelated root app dependencies.

| Environment variable | Configuration |
| --- | --- |
| `KORLIX_HOSTED_ACCEPTANCE_MODE` | `isolated-postgres-sandbox-v1` |
| `KORLIX_HOSTED_ACCEPTANCE_DATABASE_HOST` | Exact internal host above |
| `KORLIX_HOSTED_ACCEPTANCE_DATABASE_URL` | New database's Internal Database URL; enter directly in Render |
| `KORLIX_HOSTED_ACCEPTANCE_STRIPE_KEY` | Dedicated key from KORLIX 2MEETU Testing sandbox; enter directly in Render |
| `KORLIX_HOSTED_ACCEPTANCE_TOKEN_HASH` | SHA-256 of a fresh private 32-byte token |
| `KORLIX_HOSTED_ACCEPTANCE_ENCRYPTION_KEY` | Fresh private 32-byte hexadecimal value |
| `KORLIX_HOSTED_ACCEPTANCE_EXPIRES_AT` | Short test-access expiry, at most seven days |
| `KORLIX_HOSTED_ACCEPTANCE_ORIGIN` | Optional explicit origin; otherwise Render's HTTPS external URL |

Do not copy production environment groups, Supabase credentials, provider keys, the local ledger encryption key, control token, CLI config or keyring. No secret values or private links belong in this document or Git.

Initial identity verification requires read access to the account resources used by `/v1/account` and `/v2/core/accounts/{id}`. Use a dedicated restricted test key with the appropriate Accounts/Core Accounts permissions, including relevant Connect permissions. A restricted key may need its permissions adjusted after a sanitized 403 result; do not switch to a live or production-attached key to pass the check. Checkout/refund write permissions are not required by this staging implementation.

## Remaining acceptance work

Ten focused tests pass in `backend/test/manual/hosted_stripe_acceptance.test.mjs`. They cover isolated configuration, database guard creation/restart and refusal of foreign objects, private HTTP access, absent payment routes, missing credentials, serialized identity reads, mismatched Stripe identity, expiry and sanitized errors. Provider responses and PostgreSQL boundaries are test doubles; this is not verification of the hosted database or a real Stripe key. An additional local PGlite catalog smoke check exercised guard creation and matching restart, with only the database-name identity query substituted for the dedicated fixture name.

After database and credential identity verification, implement and review the durable scheduling ledger, tightly scoped synthetic booking provisioning, Stripe-signed webhook handling, private customer return page and controlled one-run Checkout issuance. Then run one new genuine sandbox checkout to establish the new paid transition and actual HTTPS Stripe redirect. Existing refunded records must not be reset, relabeled unpaid or treated as a new transition. Until that test passes, paid-booking and redirect acceptance remain open. All production checkout flags remain false.
