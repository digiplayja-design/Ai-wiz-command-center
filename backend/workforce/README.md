# Workforce autonomous email

Workspace owners on Enterprise can add approved recipients and create rules for
missing work updates, scheduled shifts without a clock-in, and previous-day team
summaries. New rules are paused. Each rule chooses draft review or automatic
sending, weekdays, a same-day local sending window, record scope and a daily cap.
Recipients for team-wide rules must be authorized to receive those team records.

The `workspace_email` channel is separate from existing NOVA Email Center rules.
It uses the existing `RESEND_API_KEY` and `KORLIX_AGENT_EMAIL_FROM`. Reply-to is
obtained from fresh verified Supabase account data, never from a request body.
The existing signed Resend webhook handles delivery, bounce, complaint and
suppression events. Opt-out GET only displays confirmation; POST stops emails.

Rules and events use the existing durable Workforce queue. Draft approval pins
the message, recipient and rule versions. Immediately before dispatch, the
service checks ownership, Enterprise access, recipient permission, sending window,
rule limits and the 100-email rolling 24-hour cap across the owner's workspaces.
The worker re-evaluates the attendance condition; reminders expire after two
hours or at shift end, and summaries have a six-hour catch-up window. Pausing or
revoking cancels queued drafts and messages. Already dispatched email cannot be
recalled.

Each provider attempt uses an immutable payload and `wf-email:<job UUID>`.
Definite transient rejection may retry within the event lifetime. Ambiguous
outcomes and interrupted dispatches become `unknown` and never automatically
resend. Signed provider IDs or server-created tags may reconcile these records.
A bounce/complaint stops future email to that workspace recipient. Stopped
recipients cannot be reactivated through the add-recipient form.

All email tables/RPCs are service-role only with RLS enabled. Message content is
scrubbed after 90 days while event tombstones prevent duplicate generation.
Recipient opt-out tokens expire after one year; consent/suppression records remain.

Migration: `20261004042716_workforce_autonomous_email.sql`.

Validation (no live emails):

```sh
node --test backend/test/workforce*.test.mjs backend/test/fieldproof_email*.test.mjs
```

The frontend Workforce tests cover recipe creation, explicit recipient consent,
exact draft approval and 390px layouts. Test delivery uses a mock provider; release
verification must not create real recipients or enable rules on behalf of users.
