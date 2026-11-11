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
- `RESEND_API_KEY` with permission to send and retrieve received emails. A sending-only key cannot retrieve inbound content.
- A configured Resend webhook signing secret, either the dedicated `KORLIX_SUPPORT_WEBHOOK_SECRET` or the explicitly enabled existing-webhook bridge described below.
- `KORLIX_SUPPORT_THREAD_SECRET` (independent secret, at least 32 characters), or the bridge's domain-separated key derivation described below.
- Verified enrolled sender and receiving identities.
- An unpaused profile and an eligible message.

Global readiness does not change a profile's database mode. A profile's automatic mode is enabled separately through the owner-authenticated API. Changing enrolled sender, reply address, ownership-sensitive routing, verification state, or quota changes the profile fingerprint, pauses it, and invalidates pending messages. Removed profiles are inaccessible through the API and cannot be processed by the worker.

Enabling automatic mode records its activation time and excludes older unsent report acknowledgments. Pausing and later re-enabling does not silently send reports received while paused. The owner can review older cases and explicitly compose a reply.

## Reusing the existing Resend connection

Set `KORLIX_SUPPORT_REUSE_AGENT_EMAIL_WEBHOOK=true` to route support `email.received` events through the existing endpoint:

`https://chee-chai-chee-backend.onrender.com/api/agent-email/resend/webhook`

This is opt-in. Without this flag, the existing delivery handler retains its prior behavior and does not dispatch received emails to support. With the flag, it uses the existing raw-body Svix-compatible signature check and unchanged five-minute timestamp window, then dispatches only `email.received` to the support processor without another support-layer signature check. Existing FieldProof middleware and delivery, bounce, complaint, suppression and replay processing stay on their original paths. An enabled bridge with an unavailable support runtime returns HTTP 503 for received events so Resend can retry; it does not silently acknowledge their loss.

The shared endpoint uses `KORLIX_AGENT_EMAIL_RESEND_WEBHOOK_SECRET`, falling back to `RESEND_WEBHOOK_SECRET`, with the same precedence as before. The signing value stays inside the server process. The separate `/api/automated-support/resend/webhook` endpoint still accepts an explicit `KORLIX_SUPPORT_WEBHOOK_SECRET`; when that value is absent, it can use the existing secret only if the reuse flag is true. An explicit support secret never replaces the existing endpoint's verifier key.

An explicit valid `KORLIX_SUPPORT_THREAD_SECRET` always wins. If it is absent and webhook reuse is enabled, the server derives a 32-byte thread key with HMAC-SHA256 over the decoded existing webhook key and the fixed context `korlix/automated-support/reply-address-key/v1`. The existing decoded key must be at least 32 bytes. This separates reply-address signatures from webhook signatures without exposing or copying the existing credential. An invalid explicit thread setting fails closed rather than falling back.

**Key rotation affects existing conversations.** With the derived option, changing the existing webhook secret changes the thread key and invalidates previously issued reply addresses. Switching from a derived key to a different explicit key also invalidates those addresses. Secrets are not part of the enrollment fingerprint, so this change does not automatically pause a profile. Pause sending before a planned key change and plan continuity for existing cases. A stable explicit thread secret must be selected before initial issuance, or a separately reviewed migration with old-key verification is needed. Pausing alone does not preserve old tokens.

The November 11 production rollout selects a fresh, dedicated `KORLIX_SUPPORT_THREAD_SECRET`, generated and stored server-side without printing its value. This explicit setting takes precedence over derivation and keeps production reply tokens independent of future Resend webhook-key rotation. The derived option remains available and tested but is not the selected production configuration.

After the bridge code is live, add `email.received` to the existing webhook's selected events while preserving its existing delivery events and endpoint. No second webhook, root-domain MX change, or credential export is needed. Readiness checks configuration and enrollment flags, not live provider permissions or end-to-end receipt; the controlled test below remains required.

### KORLIX receiving identity and controlled verification

On November 11, the authenticated Resend dashboard confirmed sending verification for `korlixdeveloper.com` and assigned receiving domain `echeufyeno.resend.app`. The intended enrollment is:

| Field | Value |
| --- | --- |
| Visible sender | `KORLIX Support <support@korlixdeveloper.com>` |
| Reply-To base | `support@echeufyeno.resend.app` |
| `inboundAddresses` | `["support@echeufyeno.resend.app"]` |
| Existing webhook | `/api/agent-email/resend/webhook` |
| Added event | `email.received`, preserving the existing nine selected delivery events |

Resend receives arbitrary local parts at its assigned receiving domain, so the generated `support+k.<case-token>.<signature>@echeufyeno.resend.app` addresses require no mailbox provisioning. Preserve the token's case. This receiving route leaves the existing `korlixdeveloper.com` root MX and normal support inbox intact. If a branded receiving domain is desired later, verify a dedicated subdomain and copy the exact receiving records from Resend; do not add competing root MX records. See [Resend receiving introduction](https://resend.com/docs/dashboard/receiving/introduction) and [custom receiving domains](https://resend.com/docs/dashboard/receiving/custom-domains).

Keep the profile paused while configuring. After provider verification and final enrollment, use Draft mode for a controlled owner-confirmed message to a separate verified test account. The reporter must differ from the sender and enrolled receiving addresses; sending to the support sender itself is rejected to prevent loops. Reply from the same reporter mailbox to the exact generated address and confirm the inbound message appears once on the original case as Needs review. A generic message to the base address is visible in Resend but does not create an app case. Check a reviewed follow-up for email threading, then enable Automatic and submit a new authorized test report after activation to exercise one acknowledgment.

Incoming sender validation is unchanged: explicit DMARC failure or combined SPF/DKIM failure is ignored. Unknown provider authentication is retained only for manual review with `senderAuthenticated=false`; message headers cannot elevate trust. Case routing still requires a valid signed token and the immutable reporter address. See [Resend's provider-computed authentication field](https://resend.com/docs/api-reference/emails/retrieve-received-email).

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

Provider receiving uses the dedicated signed-webhook route or the opted-in existing webhook bridge. Ordinary authenticated sessions cannot submit an inbound provider event.

## Durable delivery and database rules

Migration: `20261110025449_automated_support_cases.sql`. The repository filename matches the version recorded in the production Supabase migration history; the SQL contents are unchanged from the reviewed migration.

The four support tables have RLS enabled, no anon/authenticated policies or grants, and service-only function execution. Every function is `SECURITY INVOKER` with a fixed search path. The backend derives account identity from authentication; user-editable metadata is never authorization.

The database locks the profile before claiming a message and counting rolling 24-hour handoffs. Accepted, failed and uncertain handoffs count toward the cap. A pending message is claimed once, stores a stable provider idempotency key, and never automatically returns to pending. Unknown network outcomes and interrupted sends become Uncertain and require review. An API acknowledgment means provider acceptance, not delivery or reading.

Manual reply confirmations are deduplicated by case, customer conversation version and exact body. An owner reply supersedes an unsent acknowledgment. A newer customer reply invalidates older pending responses. Claimed messages cannot be recalled; pausing prevents later claims. Profile configuration and message fingerprints must match at claim time.

The reporting intake worker has expiring claims and may retry account lookup or case creation after a transient failure. Case creation, the acknowledgment record, and completion of intake are atomic. Unique report and action constraints prevent duplicate support cases or acknowledgments. Temporary support delivery failures do not erase an accepted report.

## Validation

`node --test backend/test/automated_support.test.mjs` executes the migration in PGlite and tests the production service/store/routes against real SQL. Coverage includes service-only privileges, owner isolation, trusted recipient binding, duplicate intake/sends, rolling quota, uncertain outcomes, stale claims, sender changes, historical-report exclusion, manual replies, case takeover, global pause, inbound replay, HTTP override rejection and reviewed-template behavior. Email delivery is injected; no test sends mail.

Automatic sending remains paused. The sender is verified; activation still requires completing inbound receiving verification and an authorized email round trip before enabling automatic mode.

The bridge regression suite is `node --test backend/test/automated_support_bridge.test.mjs`. It exercises the real HTTP delivery installer and support processor with synthetic provider data: valid and invalid signatures, altered raw bytes, stale/future timestamps, opt-in isolation, unavailable runtime retries, existing delivery/replay/suppression, signed case routing, sender authentication, secret precedence, key derivation and rotation. `node backend/test_korlix_agent_email_delivery.mjs` also retains the complete legacy delivery regression suite. Neither command sends email or contacts Resend.


## Deployment record — November 10, 2026

- Supabase recorded the applied migration as version `20261110025449`, name `automated_support_cases`.
- Backend commit `094e7ac9f81c1118a55f46cd9ecf479782a08b6b` deployed successfully in Render deployment `dep-dbp8f3bm8hqs73d5p8o0`.
- Profile `korlix-ai`, owned by the account `support@korlixdeveloper.com`, is paused. No support emails were sent during this rollout.
- Resend sender and inbound receiving verification remain pending.
- Frontend changes are tracked in the isolated [PR #50](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/50).

## Deployment record — November 11, 2026

- Website [PR #51](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/51) merged as `594d00a107aede0132b6c34e19f021dd7866cec9` and went live in Render deployment `dep-dbpuho0u01pc7399inhg`.
- Website validation: 13 Node tests passed; Flutter reported 652 passed and 1 skipped; public `/nova-email` and its script/style assets returned HTTP 200.
- The existing Resend full-access API key was confirmed through provider metadata, and its original report log showed `KORLIX AI <support@korlixdeveloper.com>` as the production sender. No credential value was exported.
- At the initial provider discovery checkpoint, the existing webhook and assigned receiving domain were found, `email.received` was not yet enabled, and no receiving test had been performed.
- Backend bridge [PR #52](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/52) subsequently merged as `a4be45934011da2e54b445a345e773e1be699ec9` and went live in Render deployment `dep-dbpuq53rjlhs73b663gg`. The health endpoint returned HTTP 200 and an unauthenticated support-profiles request returned HTTP 401.
- Existing Resend webhook `b50f161b-1aa8-4c0c-a33c-5589a7b81389` was saved with `email.received` added. All nine previously selected delivery events were retained, for ten selected events total.
- `KORLIX_SUPPORT_REUSE_AGENT_EMAIL_WEBHOOK=true` is configured. A dedicated `KORLIX_SUPPORT_THREAD_SECRET` was securely generated and stored without printing its value; production does not use the derived-key fallback.
- The enrolled From address is `support@korlixdeveloper.com`; the Reply-To base and receiving address are `support@echeufyeno.resend.app`. `senderVerified=true`, while `receivingVerified=false` remains deliberate until the real receiving test is complete. Root MX was preserved.
- Global sending remains disabled with `KORLIX_AUTOMATED_SUPPORT_ENABLED=false` and `KORLIX_AUTOMATED_SUPPORT_PAUSED=true`. Profile `korlix-ai` remains in Paused mode.
- A synthetic report traversed the normal authenticated, email-confirmed intake path and created case `0493c4ad-bb21-41b5-bfdd-8ad1db576d79`. Its initial acknowledgment stayed pending while paused. The synthetic case and report were then closed with an explicit no-send note after the owner clarified the intended address. This verifies intake and case creation, not outbound or inbound email delivery. Final database counts were zero Sent, zero Sending and zero Uncertain messages.
- The proposed real-email test was held after the owner clarified the intended support address. No support emails have been sent. A separate, explicitly agreed verified test inbox is still needed for the real round trip, because the support sender cannot also be its own acknowledgment recipient. Automatic support remains off until that verification is complete.

## Controlled outbound test — November 11, 2026, 04:56 UTC

After the no-send checkpoint above, the owner explicitly approved one bounded manual connection test from `support@korlixdeveloper.com` to `korlix@korlixdeveloper.com`. Automatic mode was never enabled. The profile was temporarily in Draft mode, the test case had `automation_paused=true`, the test cap allowed one message, and its pending automatic acknowledgment was cancelled before the approved reply was sent.

| Record | Verified value |
| --- | --- |
| Case ID | `304b40a5-48e7-49a7-99e1-13222a7b7231` |
| Support message ID | `28d1163a-b3ea-42d4-b1ff-29a231f160fe` |
| Resend message ID | `01a1c8f6-edb3-7eec-8f45-3f1c5a110d6b` |
| Sent timestamp | `2026-11-11T04:56:28.374Z` |
| Provider observation | Resend UI marked the message **Delivered**, shown as November 10 at 11:56 PM EST. |

The exact approved message body was:

> This is a controlled KORLIX Support connection test. Please reply to this email from korlix@korlixdeveloper.com with “KORLIX support test received” so we can verify that your reply returns to the correct support case.

Immediately after the one send, the profile returned to Paused, `KORLIX_AUTOMATED_SUPPORT_ENABLED=false`, `KORLIX_AUTOMATED_SUPPORT_PAUSED=true`, `receivingVerified=false`, and the normal `dailyCap=20`. No thread secret was regenerated. The restored enrollment fingerprint was `0268e321d4de41a732462797d63e7a9126f397b6af23545cfd855690c4b670e4`.

The pause-restoration deployment `dep-dbpvb80n74is7397e910` used commit `b8d982196e90558a21ae1e9b655ca7566b3f82c3`, was created at `2026-11-11T04:57:04Z`, and became live at `2026-11-11T04:57:39.928Z`. The temporary test-enabled deployment `dep-dbpv93on74is739774m0` was deactivated. No duplicate deployment was triggered.

An independent database check at 04:59:46 UTC confirmed one Sent message, zero Pending, zero Sending, zero Uncertain, and `automatic_since=null`. A further check at 05:00:42 UTC confirmed those same outbound counts, zero inbound replies, the case in `waiting_for_customer`, and the profile still Paused. The earlier proposed Gmail test remains cancelled and was never sent.

Outbound provider delivery is verified. The actual inbound return to the support case is still unverified. The next step is for the owner to reply to the delivered message from the same `korlix@korlixdeveloper.com` mailbox with the requested test phrase, preserving its signed Reply-To address. The restored `receivingVerified=false` flag means the app will initially ignore case ingestion, even if Resend receives that reply.

After the actual incoming message is verified in Resend, enroll `receivingVerified=true` while keeping `KORLIX_AUTOMATED_SUPPORT_ENABLED=false`, `KORLIX_AUTOMATED_SUPPORT_PAUSED=true`, and the profile Paused. Once that configuration deployment is stable, replay only the exact authenticated `email.received` event through Resend's existing retry control. Confirm that it attaches to case `304b40a5-48e7-49a7-99e1-13222a7b7231` and that a repeated delivery is deduplicated. This pending verification sends no further outbound email. Receipt in Resend and attachment to the original case must both be checked before declaring the round trip complete. Automatic support remains off.

## Receiving verification and recipient-casing fix — November 11, 2026

The owner replied from `korlix@korlixdeveloper.com` with the requested phrase, “KORLIX support test received”. Resend received that message as `cd6d8194-051b-4ced-924b-c0a940f7c4a9` at `2026-11-11T04:57:48.145851Z`. The associated provider event is `msg_3LwlZpDQgPnmKbsQER0xpKeuanH`. Its original webhook attempt returned HTTP 200 with `matched=false`; provider receipt alone did not prove attachment to the support case.

Investigation found that Resend lowercased its canonical recipient value while the original To header preserved the mixed-case signed case address. The existing HMAC verifier correctly rejected the altered token. [PR #53](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/53), merged as `35e4fe9f47be214e9b6d61e05eac46c1410d1d3f`, adds bounded recovery of original casing from To/Cc only when the entire normalized mailbox already matches a canonical receiving recipient. The recovered address must still pass exact HMAC verification, single-case ambiguity checking, enrolled profile ownership and immutable reporter matching. Header values cannot establish sender authentication. No secret or token format changed.

The fix passed all 51 automated-support tests, including synthetic regressions for the observed recipient shape, unrelated header-only tokens, multiple cases, forged casing, malformed headers and unchanged sender authentication. No actual receiving address or real message payload was embedded in those regression fixtures.

The receiving-only environment update set `receivingVerified=true` and retained `dailyCap=20`, `KORLIX_AUTOMATED_SUPPORT_ENABLED=false`, `KORLIX_AUTOMATED_SUPPORT_PAUSED=true`, and profile Paused. Render deployment `dep-dbpvia95efls7396vcmg` became live at `2026-11-11T05:12:47.174Z` on the merged fix commit. The prior deployment `dep-dbpvb80n74is7397e910` was deactivated.

The deployed enrollment fingerprint was `ba071cffbff66b39f202a217c3fca81052f4a0bb2f102556ededcb5f407fa35f`, with `updated_at=2026-11-11T05:13:39.025Z`. Independent checks at 05:14:03 and 05:14:48 UTC confirmed that configuration was stable before replay.

The exact existing event `msg_3LwlZpDQgPnmKbsQER0xpKeuanH` was replayed once using Resend's existing provider control. The refreshed provider UI showed two attempts in total: the original attempt and this one replay. The replay returned HTTP 200 with `matched=true`. No additional outbound message was sent or needed.

An independent database check at `2026-11-11T05:15:58Z` confirmed the reply was attached to the original support case:

| Record | Verified value |
| --- | --- |
| Support case | `304b40a5-48e7-49a7-99e1-13222a7b7231` |
| Inbound support message | `03df7612-0ae1-4749-91ce-e10ebe2e9ac4` |
| Incoming Resend message | `cd6d8194-051b-4ced-924b-c0a940f7c4a9` |
| Message type / status | `customer_reply` / `received` |
| Sender authentication | `verified` |
| Stored timestamp | `2026-11-11T05:15:15.511Z` |
| Case state / conversation version | `needs_review` / `1` |
| Case automation pause | `true` |

Exactly one inbound customer-reply record existed. The immutable, verified reporter remained `korlix@korlixdeveloper.com`. The profile remained Paused with `automatic_since=null`. Global outbound totals were Claimed 1, Sent 1, Pending 0, Sending 0 and Uncertain 0: there was no duplicate inbound record and no additional outbound message.

**The controlled email round trip is complete:** the one approved support message was delivered, the owner's actual reply was received by Resend, and that reply reached the same support case for human review. Automatic sending remains disabled and paused; Automatic mode was never enabled during this verification.

## Production acknowledgment activation — November 11, 2026

After the successful controlled round trip, the owner explicitly approved production acknowledgments for new KORLIX AI reports from verified users. The authorized scope is one reviewed-template acknowledgment per eligible new report, sent from `support@korlixdeveloper.com`, with a cap of 20 handoffs per rolling 24 hours. Incoming customer replies continue to enter Needs review; activation does not authorize automatic issue resolution or open-ended troubleshooting responses.

Only `KORLIX_AUTOMATED_SUPPORT_ENABLED=true` and `KORLIX_AUTOMATED_SUPPORT_PAUSED=false` were changed for activation. The receiving-ready profile, dedicated thread secret and `dailyCap=20` were retained. Render deployment `dep-dbpvml8ae00c73crru3g` became live at `2026-11-11T05:22:01.160833Z` on release commit `b873e7aa6a534fc5da11b41bfa28e26664425299`. The prior deployment `dep-dbpvia95efls7396vcmg` was deactivated before the mode transition.

The existing mode-setting RPC ran in a guarded transaction and set profile `korlix-ai` to Automatic at `2026-11-11T05:23:17.090716Z` (November 11 at 12:23 AM EST), recording that value as `automatic_since`. The guards confirmed the owner's account was email-confirmed and unbanned, there were no pending owner replies or Sending/Uncertain messages, and both completed synthetic cases retained their automation pause. The enrollment fingerprint remained `ba071cffbff66b39f202a217c3fca81052f4a0bb2f102556ededcb5f407fa35f`; sender and receiving verification remained true.

An independent audit at `2026-11-11T05:24:16Z`, approximately 59 seconds after activation and after a worker interval, confirmed:

- Profile mode remained Automatic. Both `automatic_since` and `updated_at` remained `2026-11-11T05:23:17.090716Z`, and the enrollment fingerprint still matched.
- Both completed synthetic cases remained `automation_paused=true`, predated activation, and each had zero acknowledgment claims.
- There were no post-activation message claims and no historical or test-message sends. Global outbound totals remained Claimed 1 and Sent 1, with Pending 0, Sending 0 and Uncertain 0; the one sent message was the previously approved connection test.
- The report-intake backlog was zero. No new test report or email was generated for activation.

**Production acknowledgments are active for eligible new KORLIX AI reports.** The activation timestamp excludes older report acknowledgments, the rolling 24-hour cap remains 20, and incoming customer replies continue to require human review. The completed synthetic cases remain paused. This documentation-only record does not deploy code or change any runtime setting.
