# Automated support cases

This increment connects new KORLIX AI reports to an owner-scoped support workspace. Support identities are enrolled by deployment configuration. The implementation does not depend on a particular owner UID, sender address, or the literal address `support@korlixdeveloper.com`.

## Current scope

- New successful `korlix_ai_output_reports` inserts create a durable intake row in the same database transaction. Existing reports are not backfilled.
- A worker resolves the reporter through server-side authenticated account lookup and compares the confirmed account email with the report snapshot. A missing or mismatched verified address produces a review-only case.
- Reviewed acknowledgment templates confirm receipt and ask only for missing context. Report text is never treated as model instructions. Moderation reports remain marked Needs review.
- Profiles start paused. Draft mode displays cases and allows an explicitly confirmed owner reply when global sending is available. Automatic mode sends one acknowledgment for eligible new reports.
- Customer replies are associated with the case by the receiving adapter, stored once by provider message ID, and marked Needs review. This release does not generate open-ended troubleshooting answers or perform account, billing, code, or refund changes.
- The owner can pause automation for a case, send a reviewed reply to its immutable reporter, and change case state. Resolving a case requires a note describing the verified outcome. A later customer reply reopens it for review.

## Configuration

`KORLIX_SUPPORT_PROFILES_JSON` is a JSON array of deployment-owned records:

```json
[
  {
    "id": "korlix-ai",
    "ownerUid": "<verified-owner-uuid>",
    "appKeys": ["korlix_ai"],
    "displayName": "KORLIX Support",
    "fromEmail": "<verified-sending-address>",
    "replyTo": "<verified-receiving-address>",
    "inboundAddresses": ["<verified-receiving-address>"],
    "senderVerified": false,
    "receivingVerified": false,
    "dailyCap": 20
  }
]
```

These placeholders are documentation, not an activation configuration. Set verification booleans only after verifying the sending identity and receiving route, including case-specific plus-address replies. `replyTo` must be one of the enrolled receiving addresses; its local part must be at most 22 characters to leave room for a signed conversation token.

An app key and a receiving address can belong to only one profile. Profile IDs cannot be reassigned to a different owner. Multiple applications or businesses can have different enrolled profiles and identities; this is not self-service business onboarding or a permission to reuse another business's sender domain.

Sending additionally requires:

- `KORLIX_AUTOMATED_SUPPORT_ENABLED=true`
- `KORLIX_AUTOMATED_SUPPORT_PAUSED=false`
- `KORLIX_AGENT_EMAIL_EMERGENCY_PAUSE` must not be explicitly true.
- `RESEND_API_KEY`
- `KORLIX_SUPPORT_WEBHOOK_SECRET` (Resend signing secret)
- `KORLIX_SUPPORT_THREAD_SECRET` (independent secret, at least 32 characters)
- Verified enrolled sender and receiving identities.
- An unpaused profile and an eligible message.

Global readiness does not change a profile's database mode. A profile's automatic mode is enabled separately through the owner-authenticated API. Changing enrolled sender, reply address, ownership-sensitive routing, verification state, or quota changes the profile fingerprint, pauses it, and invalidates pending messages. Removed profiles are inaccessible through the API and cannot be processed by the worker.

Enabling automatic mode records its activation time and excludes older unsent report acknowledgments. Pausing and later re-enabling does not silently send reports received while paused. The owner can review older cases and explicitly compose a reply.

## API

All owner endpoints require a freshly authenticated user and use owner scope in the database query. They accept no sender, recipient, owner, verified-status, or enrollment override.

| Endpoint | Purpose |
| --- | --- |
| `GET /api/automated-support/profiles` | Enrolled profiles owned by the signed-in user, mode and readiness. |
| `PATCH /api/automated-support/profiles/:id` | Change `mode` to paused, draft or automatic. |
| `GET /api/automated-support/cases?profileId=&state=` | Latest 100 matching owned cases. |
| `GET /api/automated-support/cases/:id` | Case and latest 200 messages in chronological order. |
| `PATCH /api/automated-support/cases/:id` | Change state, per-case automation pause, or resolution note. |
| `POST /api/automated-support/cases/:id/replies` | `{text,confirmed:true}` queues the exact reviewed response to the immutable reporter. |
| `POST /api/automated-support/cases/:id/process` | Attempt an eligible pending action; all sending rules still apply. |

Provider receiving uses a separate signed-webhook route. Ordinary authenticated sessions cannot submit an inbound provider event.

## Durable delivery and database rules

Migration: `20261110025449_automated_support_cases.sql`. The repository filename matches the version recorded in the production Supabase migration history; the SQL contents are unchanged from the reviewed migration.

The four support tables have RLS enabled, no anon/authenticated policies or grants, and service-only function execution. Every function is `SECURITY INVOKER` with a fixed search path. The backend derives account identity from authentication; user-editable metadata is never authorization.

The database locks the profile before claiming a message and counting rolling 24-hour handoffs. Accepted, failed and uncertain handoffs count toward the cap. A pending message is claimed once, stores a stable provider idempotency key, and never automatically returns to pending. Unknown network outcomes and interrupted sends become Uncertain and require review. An API acknowledgment means provider acceptance, not delivery or reading.

Manual reply confirmations are deduplicated by case, customer conversation version and exact body. An owner reply supersedes an unsent acknowledgment. A newer customer reply invalidates older pending responses. Claimed messages cannot be recalled; pausing prevents later claims. Profile configuration and message fingerprints must match at claim time.

The reporting intake worker has expiring claims and may retry account lookup or case creation after a transient failure. Case creation, the acknowledgment record, and completion of intake are atomic. Unique report and action constraints prevent duplicate support cases or acknowledgments. Temporary support delivery failures do not erase an accepted report.

## Validation

`node --test backend/test/automated_support.test.mjs` executes the migration in PGlite and tests the production service/store/routes against real SQL. Coverage includes service-only privileges, owner isolation, trusted recipient binding, duplicate intake/sends, rolling quota, uncertain outcomes, stale claims, sender changes, historical-report exclusion, manual replies, case takeover, global pause, inbound replay, HTTP override rejection and reviewed-template behavior. Email delivery is injected; no test sends mail.

Automatic sending remains paused. Activation still requires completing Resend sender and inbound receiving verification, recording the verified identities, and testing with authorized test accounts before enabling automatic mode.


## Deployment record — November 10, 2026

- Supabase recorded the applied migration as version `20261110025449`, name `automated_support_cases`.
- Backend commit `094e7ac9f81c1118a55f46cd9ecf479782a08b6b` deployed successfully in Render deployment `dep-dbp8f3bm8hqs73d5p8o0`.
- Profile `korlix-ai`, owned by the account `support@korlixdeveloper.com`, is paused. No support emails were sent during this rollout.
- Resend sender and inbound receiving verification remain pending.
- Frontend changes are tracked in the isolated [PR #50](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/50).
