# Auto-Email reviewed delivery and outbox

The private, single-owner/agent companion now implements explicit, on-screen sending through a connected Gmail/Google Workspace or Microsoft 365 mailbox, with an immutable outbox record. It remains **disabled pending provider activation and authorized live testing**. This release does not configure provider apps, change secrets, send email, enable schedules, widen the pilot or change customer subscriptions.

## User flow and API

1. Save a transactional draft for an existing approved recipient.
2. Select Delivery review. Choose the connected sender and inspect From, To, subject and plain-text body. `POST /api/auto-email/outbox/review` is read-only. It returns human-readable blockers or a five-minute proof bound to owner, agent, installation, source content and mailbox generation.
3. Select Send this email. `POST /api/auto-email/outbox/submit` accepts only the review proof and `confirmed:true`. No destination, body or authorization override is accepted in the confirmation request. Voice never receives a sending tool.
4. Inspect the exact reviewed message with `GET /api/auto-email/outbox` or `GET /api/auto-email/outbox/:id`. The list shows the latest 100 confirmations; lookup by ID is not limited by that window.

Closing review before confirmation preserves the draft. Once confirmation starts, closing or disconnecting cannot recall a provider submission. The UI disables repeated clicks and offers no automatic retry. A response timeout directs the user to refresh the outbox before making another copy.

## Durable state and duplicate prevention

Applied migration: `20261028030829_auto_email_outbox.sql` in Supabase project `uxtjzjbwtppjvnsoiijv`. The filename matches the remote ledger; do not reapply it.

The service-only `korlix_auto_email_outbox` table has RLS enabled, no client policies and no anon/authenticated CRUD. Mutation functions are SECURITY INVOKER with a fixed search path and service-only execution. The security advisor adds only the expected informational RLS-without-policies entry for this table.

Claiming locks the mailbox, workspace settings, source draft and recipient. It rechecks sender generation, exact snapshot, active/consented recipient, pause policy, draft eligibility and quota. One source draft can create only one outbox row. Replayed confirmations return the existing row, including after the row leaves the first page of history.

The same transaction retires the legacy source to `cancelled`, stores `metadata.autoEmailOutboxId`, and makes it immutable through a database trigger. This prevents the existing Resend engine or a racing approval/edit from sending that source again. Auto-Email labels it **Moved to outbox** and links its authoritative record. Older KORLIX clients may show the source as Cancelled; they do not yet render the new mailbox-delivery result. A definitive failed send requires a deliberate new draft; this release does not revive or retry its source.

| State | Meaning |
| --- | --- |
| preparing | Checking credentials and policy; no durable provider handoff yet. |
| submitting | The one provider handoff was recorded before the HTTP request. |
| accepted | Gmail returned a message ID or Graph returned 202. This is not proof of delivery/read. |
| not_sent | Preparation stopped or the provider definitively rejected the request. No automatic retry. |
| uncertain | Network failure, ambiguous provider response, or interrupted handoff. Check Sent before creating another copy. No automatic retry. |

The server serializes sends/refresh per mailbox with a two-minute lease and uses generation/status/lease comparisons for credential writes. It refreshes expiring tokens server-side, stores rotated refresh tokens encrypted, verifies the sender at the provider identity endpoint, then rechecks the active owner/agent and SQL policy immediately before handoff. A disconnect during preparation cannot restore credentials. A disconnect after handoff cannot recall an email.

Startup, reads and a best-effort 60-second timer settle stale jobs: preparing becomes not_sent; submitting becomes uncertain after two minutes. Cleanup never sends anything. There is no delivery worker, automatic retry, autonomous sending, delivery webhook/reconciliation, shared mailbox or attachment support in this increment.

## Activation and quotas

Keep `KORLIX_AUTO_EMAIL_SENDING_ENABLED=false` for the current release. Read the mailbox activation document for dedicated provider registrations, exact redirects, permitted scopes, encryption key and consent verification. No provider registration connector was available in the installed tools used for this release; registrations/secrets remain an operator task.

Sending additionally requires configured mailbox OAuth, an active reviewed connection, the existing approved owner/agent with its email tool, `KORLIX_AGENT_EMAIL_ENABLED`, an unpaused environment, and enabled/unpaused workspace settings in approval_required or autopilot mode. Existing sender/recipient consent and schedule settings were not altered. Before an authorized private live trial, review the existing legacy routines and global pause behavior so enabling the workspace does not unintentionally activate an older routine.

`KORLIX_AUTO_EMAIL_DAILY_SEND_CAP` defaults to 5 and is clamped to 1–20 and the workspace's configured cap. This quota counts **every outbox confirmation** over rolling 24 hours, including failed/uncertain attempts. It is a separate pilot counter, not a combined business-wide quota with the legacy Resend engine. Unified quotas/entitlements, organization roles and broader tenant isolation are required before business rollout.

Public capability version 4 reports sending *configuration* readiness, not a successful mailbox test or current per-draft eligibility. Per-draft review enforces the additional connection and policy checks. No credentials, tokens, proof secrets or provider response bodies are logged or returned to the frontend.

## Verification

- 57 backend Node tests passed across Auto-Email, SQL schemas, auth and companion-session regressions; all provider exchanges/submissions use injected mocks.
- Existing draft service checks: 17 passed. Existing delivery service checks: 44 passed.
- 25 frontend tests passed; syntax and whitespace checks passed.
- Desktop and 390 px mobile QA exercised explicit review, close-without-submit, one fake submission, accepted/unknown labels, retired-draft links, no retry after response loss and outbox recovery. Test fixtures use example.test data and are excluded from deployed assets.
- Remote grants, RLS, function execution/search path and trigger were verified after migration. The outbox held zero rows. No live mailbox, customer email, microphone or provider send was used in verification.

## Primary references

- [Gmail messages.send](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/send)
- [Google OAuth refresh](https://developers.google.com/identity/protocols/oauth2/web-server#offline)
- [Microsoft Graph sendMail](https://learn.microsoft.com/en-us/graph/api/user-sendmail)
- [Microsoft token refresh](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow#refresh-the-access-token)
