# TIER-GAS-02: durable test wallet and Google purchase adapter

## Price confirmed by Ricardo, September 29, 2026

The five-hour pack is **USD 124.99 / 12,499 reference cents**, intentionally
selected in Play Console. USD 125.00 and USD 125.99 are not the approved price.
This resolves the discrepancy note in TIER-GAS-01. No existing Play listing,
customer purchase, or production catalog was repriced by this milestone.
The other working reference prices remain 30/55/80 dollars for 1/2/3 hours;
actual store product mappings and localized offers still need direct verification.
Android must display Play Billing ProductDetails pricing, not convert reference
USD cents into a purported local checkout price. Reference price is not verified
payment amount, and purchase verification must not reject legitimate localized
prices or discounts merely because they differ from the USD reference.

## Implemented, not activated

- Additive private `korlix_gas_v2` schema: seven RLS-enabled tables and a
  service-role-only public RPC. Anonymous/authenticated roles cannot call it.
  Even service_role has no direct table access. No customer-facing debit/refund
  endpoint exists. No old GAS table or function is replaced or old balance imported.
- Transactional purchase grant and consume-job enqueue. SHA-256 of the globally
  unique purchase token is the key, not an optional Google order ID. The same token
  cannot credit a second account or a second package. Previously consumed but
  unrecorded purchases are rejected rather than credited speculatively.
- Per-purchase remaining seconds, usage-event idempotency, session binding, wallet
  row locks, per-token advisory locks, FIFO allocation records and overdraft rollback.
- One revocation per token, including revocation-before-grant protection. Refunds
  remove only that purchase's unspent time. Spent refunded time marks the wallet
  for billing review and stops further purchased-GAS debits; unrelated pack balances
  are not silently confiscated. The review resolution UI/process is NOT built here.
- Google ProductPurchaseV2 adapter with a fixed application ID, server OAuth adapter,
  strict account/product checks, single-unit consumables, pending/cancel handling,
  rejection of test purchases by default, and backend products.consume support.
- Stable HMAC-based obfuscated account IDs. The native purchase flow MUST set the
  returned obfuscated account ID. Missing bindings require support/reconciliation;
  do not fall back to trusting the client user ID. Preserve the HMAC secret for the
  account lifetime; an intentional binding-key rotation needs a separate migration.
- AES-256-GCM encrypted retry tokens, random IV, key IDs and associated data binding
  user/product/package/token hash. Retain older decryption keys until pending work
  is reconciled. Never put encryption/HMAC/OAuth keys or tokens in Git or logs.
- Retry worker with expiring job leases, backoff and fresh Google verification
  before consume. It recovers a prior successful consume without crediting again.
  The worker and API routes are NOT mounted or scheduled in the live server.

## Verified in this milestone

118 local Node tests passed, zero failed (Node 22.16.0). Google transport responses
were synthetic fixtures; no real Google purchase or payment was made.

32 checks passed against the actual isolated AI GAS PostgreSQL test branch in one
transaction followed by ROLLBACK. Coverage includes grant/replay, account mismatch,
unknown consumed token, debit/session idempotency, insufficient-balance rollback,
job leases/retry/completion, refund attribution/replay, early revocation, ledger
conservation and privileges. These are not a parallel multi-connection stress test.

The additive migration `20260929203432_tier_gas_v2_wallet.sql` was applied only to
the existing non-default, persistent `build132-ai-gas-test` branch. Its exact SQL
matches the applied migration statement MD5 `eddac8d1e36b9dcba6fe68a055e94c8b`.
After rollback the v2 wallet, purchase and job counts were all zero. All four
catalog mappings remain NULL and disabled. Existing legacy test schema is intact.

Commands (local Node tests do not need credentials or install dependencies):

```sh
node --test backend/ai_gas_v2/wallet.test.mjs
```

The SQL test is only for the isolated zero-customer v2 test schema. Do not run it
against production or an environment containing active consume jobs.

## Integration contract and remaining gates

`createGoogleClient` requires a trusted OAuth access-token provider using the
Android Publisher scope and appropriate Play Console permissions. No service
account credential was requested or configured here. `createWallet` requires the
fixed database RPC adapter, Google verifier and token vault. No provider response
is accepted from a request body. The authenticated route accepts only productId
and purchaseToken; user identity comes from the verified server session.

Before mounting, connect account-status/abuse checks, body-size/rate limits,
verified product mappings, environment isolation and safe secret management.
`allowTestPurchases=true` is only for an explicitly isolated testing environment;
never enable it on the production wallet. The SQL RPC trusts the service backend:
its `isTest`, identity, purchase state and duration facts are NOT independently
verified by PostgreSQL. Do not expose a generic RPC proxy to the client.

The internal `debit_verified_gas` action charges ONLY already-determined purchased
GAS seconds. It is NOT yet integrated with the monthly included quota, session
reservation, authoritative active-time clock, pause/disconnect handling or token
termination. Do not deduct included time in one transaction and GAS in another.
Those checks must be composed atomically before voice metering goes live. Merely
providing a session UUID is not proof that the session exists or owns the time.

Required before public rollout:
1. Exact Console product IDs/offers; native Play Billing checkout and obfuscated
   binding; real test purchases and purchase restoration/reconciliation.
2. Mounted, authenticated backend and durable worker scheduling with failed-job
   alerts. No claim that a worker runs simply because its function exists.
3. Authenticated RTDN delivery or authenticated Voided Purchases reconciliation,
   replay-safe checkpoints, and refund updates after a consume job has completed.
   The refund ledger supports events; no live refund listener/poller is connected.
4. Concurrency/stress and restart tests, including multi-device active-time limits,
   allocation across included/GAS balances, and external provider crash windows.
5. Retention/deletion controls for completed encrypted-token jobs and minimal
   anti-replay records. Account deletion cascades account-linked wallet rows; a
   final lawful retention policy and support recovery still require review.
6. Ordinary-user wallet UI, low-balance/pause states, billing-review UX, all four
   tiers, final policies, certificate/storage/device/AAB checks and staged rollout.

Google references checked September 29, 2026:
- https://developer.android.com/google/play/billing/security
- https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2
- https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2/getproductpurchasev2
- https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.products/consume
- https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.voidedpurchases/list

No production migration, Render deployment, customer balance adjustment, live
tier change, Google Play product mutation, Android build or store submission was
performed by this milestone. The prior signing/storage checks remain separate.
