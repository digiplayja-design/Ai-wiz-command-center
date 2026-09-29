# TIER-GAS-01: commercial-access and voice-budget foundation

Owner-approved direction: September 29, 2026. This is an additive development
milestone, NOT an activated entitlement migration or a completed AI GAS product.

## Included in this milestone

- `policy.mjs`: one versioned catalog for 38 commercial capabilities, exact tier
  normalization, current-plan checks, separate Music add-on checks, exact
  grandfathered paid-benefit checks and scoped employer/employee access decisions.
- A dependency-injected, authenticated **read-only preview** route. It ignores
  client-provided tiers, identities, balances, grants and roles. The route is not
  imported or registered in `server.js` yet.
- `voice_budget.mjs`: pure included-first allocation of server-measured active
  LIVE CONVO seconds; insufficient funds cause no partial debit. Social, music,
  meetings and telephone services are not silently mapped to this voice product.
- `policy.test.mjs`: 272 local Node tests, including all four tiers, failed access
  cases, account/grant/workspace binding, safe preview errors and 10,000
  deterministic allocation-conservation cases inside one test.

Run from repository root:

```sh
node --test backend/commercial_access/policy.test.mjs
```

No new dependency, SQL migration, subscription price, generation quota, voice
allowance, customer record or existing source file is changed. No production
service is redeployed. Local tests do not establish live Android or billing success.

## Approved packaging represented by the catalog

Basic includes core Social, human calls, games and limited everyday/creative AI.
Pro adds personal agents, Brain Vault, App Studio and starter bookkeeping/tax
organization. Ultra adds advanced creator and single-operator business capacity,
including advanced bookkeeping, linked tax preparation, inventory, FieldProof,
Contract Radar and AI Visibility. Enterprise retains CRM, funnels, Meeting
Copilot, autonomous outreach and employer administration. An authorized employee
uses the employer's workspace entitlement, not a mandatory personal Enterprise
subscription. Music Production remains a separate add-on. AI GAS extends only
LIVE CONVO voice time; it does not buy another subscription tier.

An eligible catalog entry does not imply unlimited usage or that all proposed
subfeatures exist. Basic samples and Pro/Ultra capacity still need server-side
quota mapping. Preview/demo offerings are not production access. No new numeric
monthly allowances or store prices are set by this catalog.

## Security and integration contract

`evaluateAccess` is a COMMERCIAL eligibility calculation, not authentication,
resource ownership authorization, consent, moderation, quota reservation, purchase
verification or a payment ledger. Its positive result explicitly requires the
remaining resource/usage checks. Never turn `eligible` alone into permission to
read another user's records, send outreach or start an unmetered AI session.

`registerAccessPreview` requires server-owned `requireUser`, `loadFacts` and
`loadAvailability` adapters. `requireUser` must validate the authenticated
identity. `loadFacts(userId)` must independently resolve verified current billing
or authorized contractual entitlements. Do not use editable profile fields,
JWT user_metadata, request bodies or client-supplied `verified` booleans as evidence.
Provider-specific grace periods must be verified by the billing adapter and
normalized into an explicit active entitlement with a bounded expiration.

Facts shape (synthetic field description, not a database schema):

```text
userId, accountStatus
plan: tier, verified, status, expiresAt, nonExpiring (only for explicit grants)
addons[]: userId, workspaceId, featureKey, verified, status, expiresAt
legacyGrants[]: the same bindings, source=legacy_paid_offer, offerId
workspace: id, memberUserId, membership, plan, permissions[]
```

Records are current only when verified=true, status=active and an explicit
expiration is in the future, or expiresAt=null AND nonExpiring=true. All facts
must be produced by a trusted resolver. Missing availability fails closed;
account controls remain commercially unpaywalled but still require authentication
and resource ownership. Workspace permissions and memberships are exact and do
not confer access to personal Social, memories or files.

Before enforcing this policy on existing routes, audit actual historical offers,
create authoritative paid-benefit grants, and test them. The code SUPPORTS such
grants but does not create them or prove that existing buyers have been migrated.
Do not silently remove existing benefits. Do not retrofit this policy by merging
the entire frontend branch into the backend branch.

`allocateVoiceSeconds` requires server-verified incremental active seconds.
It is NOT a clock, session state machine or idempotency mechanism. A subsequent
transactional ledger must perform row locking, unique-event handling, atomic
writes and refund reconciliation. The existing voice-session lifecycle must
provide trustworthy active time and stop billing on pause/disconnection. Replaying
a pure calculation cannot replace database idempotency. The developer exemption
is voice-only and must come from the server's protected entitlement authority.

## Read-only baseline checked September 29, 2026

- Backend source and Render live commit:
  `67cc713723cd206f202928345b4568e16baf1a5b` on
  `release/k135z-backend-render-20260919`.
- Frontend release source:
  `4c687df0f8e4ed74243e12004e102411624257eb` on
  `release/k135z-frontend-20260919`.
- The current backend tree lacks `backend/korlix_ai_gas.mjs`. Its production
  database catalog inspection returned no public AI GAS tables or RPCs.
- The older recoverable module exists on the frontend source commit above, blob
  `91a49f27bfcaf229b4c1e9d5b767220906c7b058`. Its adapters are dependencies, not
  proof of a real Google purchase integration.
- The old module's five-hour catalog is **12499 USD cents**, whereas the earlier
  proposal/handoff used $125. Reconcile that difference with actual store products
  and the accepted offer before activation; do not change existing purchases.
- This milestone has not verified Play Console product IDs, actual prices,
  highest-used Android version code, or a signed release bundle.

## Next release gates

1. Recover the historical GAS schema/module into an isolated test context and
   reconcile dependencies against the CURRENT backend, without losing later work.
2. Build verified Google Play subscription/consumable adapters and bind purchases
   to the authenticated KORLIX account. Grant only PURCHASED transactions. Commit
   once in a durable ledger, then consume/acknowledge with durable retry recovery.
3. Add wallet/balance UI, server-active-time metering, pause/disconnect/restart
   reconciliation, concurrency protection, refund handling and low-balance prompts.
4. Resolve current offers and grandfathering, connect the preview to verified
   facts, compare decisions, then enforce both UI and backend/DB boundaries.
5. Test on ordinary Basic/Pro/Ultra/Enterprise accounts and employer/employee
   memberships. Test actual Android purchase success/pending/cancel/refund paths.
6. Reconcile final terms/checkout, check supported Play Billing SDK, native Android
   behavior and signing, then prepare an internal AAB and final release candidate.

Official billing references checked during this milestone:
- https://developer.android.com/google/play/billing/security
- https://developer.android.com/google/play/billing/deprecation-faq.html

Working estimate remains 3-7 focused engineering days for tier/GAS work, contingent
on reusable foundations, store access/configuration and device tests. This is not
a verified countdown or a promise of approval. Google review is excluded.
