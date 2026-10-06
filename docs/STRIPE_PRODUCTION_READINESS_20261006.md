# 2MEETU production readiness review — 2026-10-06

**Decision: keep production checkout paused.** The isolated USD 1.00 hosted acceptance passed, but the live merchant setup and production payment path are not ready for activation. This review performed read-only Stripe, Render and public-health checks; it changed no production settings, deployed no code and created no payments or merchant accounts.

This checkpoint supersedes older pending statements about the single hosted acceptance sequence in the [Connect rollout history](STRIPE_CONNECT_NO_TRANSACTION_FEE_20261005.md). Full sandbox evidence is in [the hosted acceptance record](STRIPE_HOSTED_SANDBOX_STAGING.md).

## Verified configuration

| Area | Observed result |
| --- | --- |
| Production backend | Render `srv-d8csvkkp3tds73emfikg`; deployed commit `d682b32acde91522b570ac8c6ba9a24ccb8074aa`, deployment `dep-db22qkcs728c73asc5b0`; live since 2026-10-05 23:06:08 UTC; automatic deployment off |
| Production frontend | Render `srv-d8ekf7t7vvec73dpar60`; deployed commit `9ea25c13f42b2ec0fdb1c063db3cdddaa285cf0c`, deployment `dep-db1c6anavr4c73b7l590`; automatic deployment off |
| Scheduling health, 01:07:20 UTC | HTTP 200; configured, `checkoutEnabled:false`, `livePayments:false`, direct charges, `platformFeePercent:0`, Accounts v2 readiness, API `2026-09-30.endive` |
| Web billing health, 01:07:28 UTC | HTTP 200; configured, `checkoutEnabled:false`, `livePayments:true`, connection verified |
| Directory health, 01:08:26 UTC | HTTP 200; configured, `checkoutEnabled:false`, `livePayments:true`, connection verified |
| Live platform overview | Korlix INC, `acct_1UMs8D22E1oIiTRb`; v1 overview reports charges/payouts enabled, details submitted and no currently due, past due or pending verification requirements. This is a platform-status snapshot, not connected-merchant Accounts v2 readiness proof. |
| Live connected accounts | `/v1/accounts`, limit 100: empty list, `has_more:false`. No live merchant was available for this review. |
| Live webhook endpoints | Complete `/v1/webhook_endpoints` list contains web subscription and Directory destinations only. No live endpoint targets `/api/scheduling/payments/webhook`. |

Health URLs: `/api/scheduling/payments/health`, `/api/billing/web/health`, and `/api/directory/health` on `https://chee-chai-chee-backend.onrender.com`. Credential mode and an enabled webhook destination do not imply that checkout is enabled.

## Launch gaps

### 1. Merchant readiness can remain stale after verification

The OAuth callback stores the verified identity snapshot. Owner confirmation retrieves identity again, but `backend/scheduling/connected.mjs` uses that fresh result only to compare account IDs and does not pass the refreshed capability state to the connection persistence operation. The existing SQL `finish` operation copies the earlier callback identity.

The compatibility path intentionally records `charges_enabled:false` until Accounts v2 verification succeeds. Connections reads return saved state; there is no dedicated Stripe readiness refresh or account-capability webhook handler. Paid event save/publish and booking eligibility depend on the saved flag. A merchant who finishes verification later can therefore stay blocked until a fresh OAuth connection is completed. Fresh capability verification before Stripe Checkout still prevents payment creation for an ineligible account; this is an onboarding recovery defect, not evidence of unauthorized charging.

**Next engineering change:** persist fresh owner-confirmed identity and add an owner-bound capability refresh that preserves account identity, mode, fee/loss responsibilities and current Checkout checks. Verify pending-to-active, active-to-inactive and mismatched-account cases before deployment. Do not fix this by trusting legacy capability flags or enabling checkout globally.

### 2. Matching live payment configuration and an authorized merchant are absent

Scheduling still reports test credentials, the live platform lists no connected merchants, and no live scheduling webhook exists. Live preparation needs a matching platform OAuth application/redirect, restricted server key, connected-account webhook and signing secret, followed by an owner-authorized live merchant whose Accounts v2 card-payment and payout capabilities are active. Preserve the scheduling encryption key. Inventory any existing connection/hold/refund state before replacing credential context.

The five payment events remain `checkout.session.completed`, `checkout.session.expired`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, and `charge.refunded`. The expected production endpoint is `https://chee-chai-chee-backend.onrender.com/api/scheduling/payments/webhook`. Pin the reviewed API version and retain `KORLIX_SCHEDULING_STRIPE_ENABLED=false` during preparation. Zero application-fee fields in code and the sandbox fee proof are established; live Platform Pricing Tool rules were not verified in this review.

### 3. New-business onboarding is not implemented

The existing-account OAuth connection flow is implemented and passed user sandbox connection earlier. Accounts v2 merchant creation, embedded onboarding, requirements notifications and account-management components remain planned. A deliberately limited pilot for already verified, compatible existing Stripe merchants can use OAuth; a launch promising onboarding for businesses without a Stripe account requires the new-business path first.

### 4. Remaining acceptance is separate from the completed USD 1.00 sequence

The completed hosted test proves payment, signed completion/refund delivery, the actual iPad return, zero KORLIX application fee, restart persistence, full refund and duplicate preservation for its exact isolated booking. Preserve that refunded record and its two receipts.

Actual provider declines, delayed success/failure and late-payment automatic-refund behavior remain unverified by that sequence. The production Express routes, database role separation and any promised email/calendar side effects were not certified by the isolated harness. It seeded a synthetic merchant connection and used private controls rather than the complete authenticated-host/public-booking journey; production automatic settlement/refund-worker operation remains unverified. Production return-page fixture checks passed earlier, but the hosted acceptance used its dedicated return UI. These are evidence limits, not observed failures.

## Rollout order

1. Correct and verify merchant readiness refresh while production checkout remains paused.
2. Complete the outstanding isolated failure-path acceptance, preserving the completed test record. Decide whether the initial launch covers existing Stripe merchants only or also new-business onboarding.
3. Stage matching live configuration and connect the intended merchant; independently verify current Accounts v2 eligibility and the zero-platform-fee configuration. Review deployed routing, ledger permissions and the features promised to that pilot.
4. Obtain explicit go-live authorization for the concrete scope, then enable only the relevant scheduling flow and perform its approved live verification. Web subscription and Directory checkout have independent launch gates.

The source review compared deployed `d682b32` with `bfeb4172`. Production scheduling differences only thread an optional request-timeout parameter whose production default remains 15 seconds. Deploying the current branch alone does not add merchant onboarding or resolve the readiness-refresh gap.

Reference reviewed: [Stripe go-live checklist](https://docs.stripe.com/get-started/checklist/go-live), including separate live configuration, registered production webhooks and delayed/duplicate/out-of-order event handling. No live readiness decision in this report relies solely on deprecated v1 capability projections.

## Merchant readiness refresh implementation — 2026-10-06

The backend now rechecks the signed-in owner's active Stripe merchant when Connections reloads, and persists the fresh identity at OAuth confirmation. Capability approval and withdrawal update the saved readiness without reconnecting. Account ID, mode, configuration fingerprint, owner and revision checks reject stale or mismatched responses, including a disconnect during the provider request. Unchanged results do not advance the revision. Provider failures return an error rather than reporting stale status as refreshed.

Migration `20261006022449_scheduling_stripe_readiness_refresh.sql` must precede the backend release. It replaces only the existing service-only, security-invoker connection RPC and remains compatible with older callers. It does not change checkout switches, credentials, grants, or merchant account bindings.

Validation: 68 focused scheduling, connected-account, voice, Stripe-provider and return-page tests passed. Coverage includes confirmation with fresh readiness, approval/withdrawal, wrong owner/account/mode/configuration, provider failures, stale revisions and disconnect races. These are local provider fixtures and SQL tests; an authenticated owner must still check their actual merchant through Connections. All other production readiness gates above remain applicable.

### Visible Refresh connections action — correction at 2026-10-06 02:55 UTC

The first readiness patch was deployed as `e03c01f71955cae2a4f1ee0a4011d14bde38b7b9` (`dep-db25qurbc2fs73fbtmqg`, live 02:32:06 UTC), after the compatible migration was applied and its function hash and service-only permissions verified. All three checkout health checks remained disabled.

User acceptance exposed a missed route: the deployed Flutter Refresh connections action calls `_load(quiet:true)` and GET `/api/scheduling/`, rather than GET `/api/scheduling/connections`. The original test covered only the latter. Render request logs confirmed the actual phone requests. The follow-up shares the same merchant refresh helper between the scheduling dashboard and connections endpoint and marks both successful responses `Cache-Control: no-store`. It requires no frontend release or additional migration.

The full confirmation/readiness/ownership/provider-error/disconnect-race test now runs through both HTTP routes. All 69 focused scheduling tests pass. The saved main-user sandbox merchant remains a legacy identity-only connection; a read-only Stripe account lookup reports details not submitted, no active capabilities and pending verification. KORLIX enterprise/developer access does not supply merchant payment readiness. No connection, Stripe account, credential, or checkout switch was changed during this investigation. Actual merchant setup and Accounts v2 compatibility remain outstanding independently of the route correction.

Dashboard resilience: automatic polling also uses this route. A failed Stripe check therefore leaves the workspace and reconnect/disconnect controls available, returns payment readiness as unverified with a fixed visible warning, and does not overwrite the saved merchant record. A fresh database read after provider I/O preserves concurrent disconnections. The explicit connections endpoint retains its error response. Tests cover outages, configuration mismatch, recovery and unchanged saved state. The existing frontend's generic onboarding label is clarified by this warning when verification is unavailable.
