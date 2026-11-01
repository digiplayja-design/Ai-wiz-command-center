# Brain+Voice store billing

Dedicated bundle/package: `com.korlix.brain`; Apple app `6829319523`. The monthly product is $34.99 for 3,600 Live seconds per verified store billing period. Exactly three consumable AI GAS packs grant 3,600 / 7,200 / 10,800 seconds for $30 / $55 / $80. `catalog.mjs` is the server catalog; native checkout displays store-localized prices. No trial, fourth pack or unlimited Deep Think entitlement is introduced.

Apply `supabase/migrations/20261101113614_brain_voice_store_billing.sql`. The four new tables and command function are service-role only, with RLS enabled. Raw provider tokens stay in the private purchase table and never appear in API responses. Native clients receive only balances and scoped purchase preparation data.

Activation is off by default. After store configuration and device purchase tests are verified, set `KORLIX_BRAIN_BILLING_ENABLED=true` and the independently verified store flags `KORLIX_BRAIN_APPLE_PRODUCTS_READY=true` / `KORLIX_BRAIN_GOOGLE_PRODUCTS_READY=true`. Existing `KORLIX_APPLE_*` and `KORLIX_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` secrets are reused server-side; neither secret values nor unrelated billing configuration should change. Sandbox/test access requires the existing server-maintained tester allowlist.

Apple notification URL: `/api/brain/billing/apple/notifications`. Signed notifications cause a fresh App Store lookup. Purchases are also rechecked every ten minutes, including Google renewals/refunds; a worker retries failed consumption/acknowledgement after durable credit. Requests bind the authenticated KORLIX user to the exact Apple appAccountToken or Google obfuscated account ID. Each verified transaction/order grants once. Pending payments cannot grant or complete.

Only `rici-live-v1` sessions use this minute ledger when enabled. Deep Think retains existing account limits. The ledger locks one account, reserves included seconds before GAS, refuses a second simultaneous conversation, charges server time, and returns unused seconds. GAS has no expiration. Client usage counters cannot mint minutes or reduce the elapsed time charge. A five-second worker terminates expired or heartbeat-stale calls through their stored provider IDs. Failed termination remains retryable after process restart, even after a refund ended the ledger session.

Validation: `node --test test/brain_billing.test.mjs test/brain_live.test.mjs test/brain_voice.test.mjs`. Production purchase verification and signed mobile sandbox purchases are still required; unit tests do not prove that store products exist.
