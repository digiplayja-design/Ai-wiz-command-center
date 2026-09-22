# Workforce: NOVA follow-ups

This release adds an owner-only Automations tab to Enterprise Workforce. The existing attendance, photo, location and hourly-update policies are unchanged.

## Available recipes

- **Work update reminders:** one event per overdue work-update cycle. The shift's interval and grace period apply first, followed by the automation's extra delay. Breaks pause the condition. A new work update resolves it.
- **Shift check-ins:** one event per scheduled shift/version with no overlapping clock-in, after the chosen delay and before the scheduled shift ends. This indicates a missing record, not a finding of absence.
- **Morning team summary:** the previous calendar day's recorded work, sent at the chosen time in the workspace timezone. It catches up for six hours, uses one event key per local date (including repeated DST hours), and never estimates employee productivity. Hours are full shifts overlapping the report date, not a payroll calculation. Long reports are truncated with an explicit notice.

Email recipients are selected from the owner's already-approved NOVA Email Center recipients. Alerts may cover one selected employee or all active members, and always go to the selected fixed recipient. Daily reports cover all team records. New rules are saved paused; enabling requires review of the recipient, scope, weekdays, timing, daily maximum and message preview.

Call escalation creates an **owner review item only**. No outbound calls are placed. The existing NOVA outbound calling capability is disabled; this release does not activate a calling provider. Marking an item reviewed is not recorded as a completed call.

## Runtime and authorization

- Apply `workforce_automations` after `enterprise_workforce`, then deploy the backend and frontend release branches.
- No new Render service, environment secret or paid resource is required. A one-minute timer in the existing always-on backend performs evaluations. Queue state is in Postgres and survives browser closure and backend restarts. There is no browser-dependent timer for delivery.
- Both new tables have RLS enabled, with browser-role privileges revoked. The SECURITY INVOKER RPC is executable only by service_role. API calls use the verified signed-in identity; each owner operation checks current membership and the owner's current Enterprise tier.
- Email continues to require the exact existing NOVA owner/agent binding, approved `agent_email` tool, provider setup, enabled Email Center and enabled Autopilot. Those controls are not modified or bypassed. Owners without that configured binding can use the review queue, but cannot activate email rules.
- All provider sends go through the existing NOVA email delivery service. The workforce worker pins the recipient, template and approval version and targets one specific rule; it cannot expand recipients based on employee text. Existing recipient suppression, daily caps, sending windows, atomic claims and provider idempotency remain enforced.
- Jobs have stable event keys, atomic leases, bounded retries, expiry and a fresh condition check before delivery. Pausing cancels queued jobs. An email already handed to the provider cannot be recalled. Expired/cancelled event keys are retained so resuming cannot replay old reminders. Worker scheduling and NOVA's sending window use their respective configured timezones.
- The UI distinguishes provider acceptance from delivery. Actual delivery/bounce status remains in NOVA Email Center. Ambiguous outcomes are blocked for review rather than sent with a new identity.
- Worker evaluation scans at most 50 rules per pass, five jobs per rule, round-robin by last check. Each workspace can store 25 rules. History shows the latest 100 jobs. Existing global NOVA sending limits may be lower than per-rule limits.

## Validation

Run `npm --prefix backend run test:workforce`, `node backend/test_korlix_agent_email_delivery.mjs`, and the frontend's `flutter test test/workforce` and `flutter analyze lib/workforce`.

The automated checks use an in-memory Postgres database and mocked delivery providers. They exercise private-table/RPC access, tenant and Enterprise boundaries, exact approvals, stable duplicate keys, lease recovery, concurrent caps, pause, clock-out cancellation, quiet-window retries, DST and mobile/desktop interactions. No real employee invitation, email or call is sent by these tests.

After deployment, the owner can configure a rule, save it paused, review its recipient and enable it when ready. Deploying this release creates no rules and enables no existing rule. A live delivery acceptance test requires the owner's explicitly chosen destination and an enabled rule; it is not performed automatically by deployment.

Rollback: pause Workforce rules in the UI, then redeploy the previous backend/frontend commits. Preserve the additive database tables and their job history. Existing NOVA Email Center emergency pause also stops email delivery.
