# KORLIX web launch readiness

Prepared October 7, 2026. Scheduled launch: **October 15, 2026, 9:00 AM America/New_York** (EDT, `2026-10-15T13:00:00Z`), selected by the owner. A countdown records the intended date; it does not authorize sales or certify operational readiness.

## This release

- Public landing page presents the live countdown, feature groups, free Receipt Wiz, browser guidance, 16+ notice, support and policy links.
- Web app home shows the same deadline. Both timers use the current clock, recover after suspension, never become negative, and stop at expiry without enabling purchases.
- Pricing and subscription terms clearly explain the current paid web checkout pause. Pro/Ultra prices remain unchanged.
- Legal operator and head-office details reflect the owner's October 4 confirmation: Korlix INC, 7965 N High St, STE 350-41, Columbus, OH 43235, United States. This is not a claim that pending Ohio registration or tax setup is complete.
- The release build now gates the countdown alongside account, privacy, billing, sharing and Workforce tests.
- Companion backend release stores AI safety reports durably before acknowledging success. The new table has RLS and service-only access. Report notification failure no longer discards intake.
- Render backend HTTP health checking is configured at `/api/health`.

## Verification before publishing

The complete selected Flutter release gate passed **154 tests**, including 13 new countdown tests. The public JavaScript countdown passed **7 tests**, including deadline, background/resume, delayed timers and completion. The companion backend run passed **30 tests** for persistence, route guards, aggregate readiness and encrypted receipt recovery. Billing-specific checks are documented in the backend launch runbook. Production publication and visual checks are recorded in the rollout evidence after deployment.

## Gates still requiring evidence

| Gate | Current status | Evidence needed |
| --- | --- | --- |
| Paid web subscriptions and paid Directory | Intentionally paused under the owner's earlier instruction. Stripe live configuration checked; no current Tax registration was found. | Owner's registration/tax decision, approval to enable paid sales, and an authorized real hosted checkout/cancellation/renewal rehearsal. The ticker never opens checkout. |
| Receipt recovery | Private receipt buckets; encrypted backup/restore utility and synthetic recovery tests prepared. Independent production backup is **not active**. | Selected independent private destination, separate key custody, retention and schedule, failure alerts, and an isolated end-to-end recovery of original bytes plus metadata. |
| Support, moderation and privacy | Team support coverage confirmed by the owner; Titan support email reaches several team members’ phones. All 39 legacy reports reviewed: 34 rows resolved (32 duplicates, one safety refusal and one scoped closure after a user-provided retest), five follow-ups still open. Local deletion checks passed, with full fulfillment gaps documented. Independent inbox login was blocked by GoDaddy, a verification limitation rather than evidence of unavailable support. | Assess the five follow-ups for launch impact and record their resolution; rehearse moderation and finish controlled deletion fulfillment across database, files and providers. The case count alone does not establish launch-blocking defects. No response schedule or 24/7 service promise has been specified. |
| Native PostgreSQL storage/RPC suites | Not verified in this executor. Its user-namespace restrictions prevent the required non-root native runner. | Supported CI/VM run with the existing nonce-bound local socket isolation, plus resolution of any true source/test failures. Do not point fixtures at production. |

The web app can remain available during preparation. Do not claim commercial launch readiness, guaranteed data recovery, staffed round-the-clock support, or complete vulnerability elimination from these checks.

The initial report-review checkpoint retained six open cases. A later live October 7 retest supplied by the user, with core factual claims independently checked against published sources, supported closing one date-sensitive case without further action. The original freshness/framing failure was not reproduced in that sample. This was not a model-operated signed-in test and does not establish that all responses or the other five cases are fixed. Details and the historical checkpoint are recorded in `docs/SUPPORT_READINESS_FOLLOWUP_20261007.md`.

## Launch runbook

1. Resolve and record the gates above with responsible people and evidence. Keep paid sales disabled until the owner explicitly releases the existing pause.
2. Before October 15, verify current Safari on iPhone/iPad and Chrome on Android/desktop: signup, login, permissions, receipt save/reopen, Workforce clock-in/location timeout/retry, account deletion request and report intake. User-reported earlier successes are useful, but do not replace the final device rehearsal.
3. Recheck database/storage access controls, backend health, job/queue failures and backup freshness. Review support backlog and the on-duty handoff.
4. Confirm the displayed date on both home surfaces; keep the free app link functional. If launch moves, update `website/launch.js`, `website/index.html` and `lib/launch/korlix_launch_countdown.dart` together and rerun their tests.
5. Publish only the reviewed branch/commit and verify the live pages and app startup. Preserve the last known-good frontend release. Keep accepted AI-report rows on any backend rollback; do not drop the queue.
6. At launch, monitor actual errors and incoming reports, and recheck after the first traffic increase. A zeroed timer is not an operational approval or a payment switch.

Render has announced Dashboard/API maintenance October 13, 9–10 PM Eastern (October 14, 01:00–02:00 UTC). Existing services are expected to remain running, but deploys and one-off jobs can be unavailable. Avoid scheduling final release work in that window. Source: https://status.render.com/incidents/bwd9ycdxqps4

Companion backend records: `docs/WEB_LAUNCH_BILLING_20261007.md`, `docs/WEB_LAUNCH_OPERATIONS_20261007.md`, `docs/WEB_LAUNCH_RECEIPT_RECOVERY_20261007.md`, and `docs/WEB_LAUNCH_DATABASE_GATE_20261007.md` on the backend release branch.
