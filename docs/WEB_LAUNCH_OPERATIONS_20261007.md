# KORLIX web launch: support, privacy and safety operations

Prepared October 7, 2026. This is an internal operating runbook, not a public promise or confirmation that a support team is staffed. Source review and synthetic tests do not establish successful handling of real requests. No customer account, report content, receipt, location, deletion or email was used in this preparation.

## What is implemented, and what remains

| Area | Implemented capability | Launch evidence still required |
| --- | --- | --- |
| Account deletion | Authenticated `/api/account/delete-request`; service-only, deduplicated `account_deletion_requests` queue. | Assigned reviewer, ownership verification, cross-feature fulfillment rehearsal, storage/provider cleanup, documented exceptions and completion notice. There is no complete automated account purger. |
| AI safety reports | New durable `korlix_ai_output_reports` intake; success only after database acceptance; protected `/api/report-output/recent` reads durable records. Notification failure does not lose the queued report. | Apply migration, deploy backend, verify protected review access and staff coverage. New code cannot recover reports already lost from a prior process. |
| Social moderation | Existing moderator-only in-app **Moderation reports** list and confirmed resolve/remove/suspend actions. Server derives identity; SQL checks `korlix_social_moderators`. | Assign a specific verified staff account and backup; rehearse on synthetic content. A developer or enterprise tier alone is not moderator authority. |
| General support / child safety | Public `support@korlixdeveloper.com` routes and in-app report controls. | Verify mailbox access, responsible people, coverage and escalation. An address in a policy does not prove someone monitors it. |
| Aggregate readiness | `backend/ops/support_readiness.mjs`: queue counts and age bands; assigned moderator count; AI notification backlog. | Run in the authorized server environment after migration. Counts do not prove response quality or deletion fulfillment. |

The countdown is a planned launch date. It must not automatically certify these gates, open paid access, or imply that launch approval has occurred.

## Staff and access decisions

Ricardo must confirm the following before declaring public web launch readiness. Names have not been assigned by this change.

| Responsibility | Required decision / evidence |
| --- | --- |
| Support and privacy owner | Named primary and backup, access to the published mailbox, daily review coverage and absence handoff. |
| Social and child-safety reviewer | Named primary and backup, approved account UUIDs, verified moderator role and restricted report access. |
| Technical deletion operator | Named operator with least required database/storage/provider access and a second reviewer for destructive cases. No service key in the browser or support tickets. |
| Billing owner | Person with access to the correct production Stripe account and provider refund/cancellation workflow. |
| Urgent escalation | Private channel/contact for safety, security and payment incidents. Establish realistic response targets; do not invent a 24/7 or guaranteed deadline. |

No staff assignments, invites, messages or report resolution actions are performed by this runbook.

## Read-only readiness inventory

From the backend repository root, the default is an offline source plan with no credential access or network request:

```bash
node backend/ops/support_readiness.mjs --source-plan
```

In an authorized server shell with `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` already supplied securely by the deployment environment:

```bash
node backend/ops/support_readiness.mjs --live-aggregates --expect-project uxtjzjbwtppjvnsoiijv
```

The tool performs only Supabase HEAD/count reads. It outputs open queue counts, counts older than 24 hours / 7 days, assigned moderator count and unresolved AI notification backlog. It requests no report text, user email, account ID, object path, attachment or signed URL. A missing table or failed read is **unverified**, never an empty queue. Exit code 2 means at least one aggregate could not be verified. Do not put a service key in command arguments, a browser, screenshot, committed file or chat transcript.

Review all four intake sources: deletion requests, durable AI reports, Social reports and the older `reports` table. The age bands are triage information, not newly promised processing deadlines. AI rows in `reviewing` are counted separately so claiming a case does not make it disappear from workload review.

## Support triage and moderation workflow

1. Open the assigned mailbox and each authorized queue at the agreed cadence. A report email is an alert; the durable queue is the source for new AI report intake after this deployment.
2. Assign a case owner and case reference in the restricted operational record. Classify support, privacy/deletion, billing, security, AI output, Social or child safety. Do not copy whole reports into general logs or shared spreadsheets.
3. Escalate immediate danger through the appropriate emergency route. For suspected illegal child imagery, record references and follow the published child-safety process without downloading, attaching or redistributing it unnecessarily. Obtain qualified legal guidance for applicable reporting/preservation obligations.
4. Review only the reported material and necessary context. Social's in-app **Moderation reports** shows report snapshots; choose the appropriate action and confirm it. Do not grant moderation based on user-editable profile data. Do not resolve a report merely to clear its counter.
5. For AI reports, the protected `/api/report-output/recent` endpoint requires the existing report administrator token in a header, never the URL. It returns up to 100 recent durable reports, so older/open cases must also be checked in the restricted database queue. There is no newly added public/admin-browser mutation route.
6. Authorized staff may track AI case state `open → reviewing → resolved` using controlled database administration. Record `resolved_at`, a verified `resolved_by` staff UUID where available and a minimal `resolution_note` together. Do not place private report text in the resolution note. Schema constraints reject contradictory resolved timestamps.
7. Explain the outcome through the approved support process when appropriate; retain only justified case material and provide the published appeal route. Record the action and responsible reviewer, not merely a “completed” label.

The existing AI report mailer sends only after a durable write. Notification delivery is marked `delivered` or `failed`; an interrupted attempt can remain `queued`. Neither `queued` nor `failed` means the report itself is missing. Do not blindly replay emails: the provider may have accepted an email before a timeout. Check delivery evidence before any authorized retry. The new code does not start an automatic email resend worker.

## Verified account deletion workflow

This is a controlled fulfillment checklist, not a bulk-delete command. Never run `delete auth.users` as the first step or mark the intake request complete merely because login was disabled.

1. **Verify the case and identity.** Review the exact request ID and server-derived account UUID. A logged-in request is stronger evidence than an email's display name. For an email request, use the approved ownership verification process; do not request passwords or unnecessary identity documents. Record who verified ownership and when.
2. **Establish authority and scope.** Determine whether the person owns a workspace, is an employee, portal customer or another participant. Identify transfers, shared business records and specific retention obligations. Do not delete another owner's independent records merely because they reference this person.
3. **Offer an export and explain timing.** Identify what will be removed, retained or de-identified and why. Receipt Wiz CSV is extracted metadata, not a copy of original receipts. Establish the applicable deadline and expected completion date for this case. Meet the published YouTube seven-day verified-deletion rule where it applies; do not let that wait behind a general account case.
4. **Prepare a restricted preview.** Produce a per-account manifest for the confirmed UUID: affected tables, relationship paths, storage buckets/object paths, provider connections and running jobs. The aggregate readiness tool is not this manifest. A full deletion preview tool is still to be implemented/rehearsed; do not claim it already exists. Keep the manifest in approved restricted operational storage, never this public repository.
5. **Review before execution.** A second authorized reviewer confirms the exact UUID and case ID, resource ownership, retained exceptions and provider consequences. Use an explicit per-case approval step for irreversible actions. Never use a wildcard or all-account purge.
6. **Stop new activity.** Pause scheduled sends, streams, calls, follow-ups and other account jobs; revoke sessions and provider credentials as appropriate. Account deletion alone does not instantly invalidate all issued JWTs. Verify the app's authorization layer prevents further writes during fulfillment.
7. **Remove physical files before deleting their references.** Use each feature's owner checks and retryable cleanup path. Database cascades do not remove Supabase Storage object bytes. Preserve the restricted manifest until cleanup has been verified. Failed storage/provider operations remain outstanding, with a retry owner and case deadline.
8. **Delete or de-identify approved database records.** Follow the feature dependencies and reviewed retention decisions. Agent “forget” flags and Social Auto Dump are not physical erasure. Account/auth removal is a final dependency step, not the entire deletion process.
9. **Verify and close.** Recheck per-account database references, original/preview storage bytes, derived/queued objects, remaining credentials and provider results. Record limited retained categories, reasons and review/expiry dates. Only then mark the case completed and send the approved completion notice. Retain minimal evidence of fulfillment, not a new plaintext copy of deleted customer data.

### Data and cleanup coverage

| Area | Required verification | Source starting points |
| --- | --- | --- |
| Receipt Wiz / finance | One shared receipt row; original plus preview objects; scan artifacts; Bookkeeping/Tax Prep links; distinct business ledger retention. | `backend/receipt_wiz/routes.mjs`, `backend/bookkeeping/receipt_files.mjs`, `docs/K198_BOOKKEEPING_FOUNDATION.md` |
| FieldProof | Photos, report/PDF delivery copies, attachment cleanup retries, job records and delivery/suppression exceptions. | `backend/fieldproof/`, `docs/FIELDPROOF.md`, `docs/FIELDPROOF_EMAIL.md` |
| Workforce | Photo and GPS evidence versus retained attendance, workspace ownership and employee records; email content/queue. | `backend/workforce/`, migration `20260922000006_enterprise_workforce.sql` |
| Social | Profile, wall/message/group/album/video/voice-note bytes and references, report snapshots, shared recipient records, push bindings. | `backend/social/`, Social migrations |
| Studios / portals / recordings | Uploaded media, generated/derived images, thumbnails, recordings, file-backed learning and queued cleanup; owner/member distinctions. | `backend/virtual_closet/`, `backend/babyblend/`, `backend/k135z_zoom/`, `backend/app_studio/` |
| Memories / vault | Main-chat notes; inactive agent memory text and metadata; approved training; separate vault access controls. | `backend/chat_memory/`, `backend/korlix_live_convo_agents.js`, `backend/k136s_learning/` |
| Providers / billing | Revoke account credentials and jobs; handle Google/Microsoft/YouTube/Zoom/payroll/phone provider data separately; subscriptions and legally retained transaction data require correct handling. | `backend/scheduling/`, `backend/payroll/`, `backend/web_billing/`, provider modules |
| Support / logs / backups | New AI report rows cascade with the account; review justified safety retention before deletion. Inspect pre-migration JSONL, support email copies and backup expiry separately. | `backend/security/ai_report_persistence.mjs`, `security/PRE_APP_STORE_AUDIT_2026-10-07.md` |

This table is a coverage checklist, not proof every resource has been enumerated. Before launch, use synthetic records across all enabled feature families to rehearse fulfillment without deleting real customer data. Supabase database backups do not by themselves constitute an independent backup of receipt object bytes.

## Deployment and rollback

1. Review and apply `supabase/migrations/20261007214516_durable_ai_report_queue.sql` **before** deploying the new backend. It adds a table and indexes only; it does not rewrite, purge or import existing reports.
2. Verify RLS is enabled, browser roles have no privileges and service-only intake can execute. Focused tests use synthetic PGlite fixtures; live metadata checks must be performed separately.
3. Deploy the backend commit. Old/native app report aliases and the response shape remain compatible (`200` when notified, `202` when queued without notification); database failure now returns a truthful `503` instead of accepting a volatile report. Public health reports version `v4` without private configuration.
4. Verify public health and unauthorized admin rejection without sending a report. Run the aggregate inventory. A synthetic end-to-end email/submission rehearsal needs explicit authorization and an identified test recipient/account; none is performed by these tests.
5. Leave the new queue table in place on rollback. **Never drop it after accepting reports.** A rollback to the old code restores volatile intake, so do not describe that as a fully safe launch fallback. Prefer a forward fix or temporarily disable new intake with a clear error and published support route while preserving all queued records.

## Validation record

Implemented locally: durable database intake, bounded protected reads, sanitized failures, notification status/deadline, aggregate-only inspection, and this runbook. Focused tests cover actual SQL/RLS denial, malformed payloads, account cascade, fresh-client report retrieval, 503/no-email on persistence failure, authenticated identity, rate limits, HEAD-only counts and rejected credential-bearing/mismatched endpoints. Deployment, live queue visibility, staffed support, moderator assignment and complete deletion fulfillment remain separately verifiable gates.

## Production metadata checkpoint — October 7

Migration `20261007214516_durable_ai_report_queue` is applied. RLS is enabled; `anon` and `authenticated` have no table privileges; `service_role` has CRUD. Read-only aggregate inspection found 0 requested deletions, 0 new durable AI reports, 0 open Social reports, 39 legacy reports marked `new`, and 1 assigned Social moderator. No report contents or user identities were accessed. The legacy backlog needs assigned staff review; one database role assignment does not establish coverage. Backend rollout verification is recorded separately.

## Support follow-up checkpoint — October 7, updated after owner confirmation

The owner confirmed that a team handles the support inbox and that its email reaches several team members' phones. **Support coverage is confirmed by the owner.** This updates the earlier statement that the owner would be the primary contact. No specific schedule, named roster, response deadline or 24/7 service is asserted.

The inbox uses Titan. During the earlier mailbox check, Titan routed the secure login through GoDaddy, which blocked this cloud browser as unusual. Mailbox contents, receipt of mail and notification delivery were therefore not independently tested; no alternate path was used around that block and no message was sent. This is a testing limitation, not evidence that the inbox is unavailable or a blocker to accepting the owner's coverage confirmation.

All 39 legacy reports were reviewed with a private ledger. The historical initial review linked 32 duplicates, closed one appropriate safety refusal without action and retained six primary cases open. Two scoped closures using the same user-provided live October 7 retest leave **35 rows resolved** (32 duplicates, one safety refusal and two no-further-action closures after the same retest) and **four primary follow-ups open**. The first closure left five open; the second used the same evidence for a semantically equivalent original question, without a second retest. See `LEGACY_REPORT_REVIEW_20261007.md`. The earlier count of 39 new reports above and the six- and five-open counts are historical checkpoints, not the current queue.

The retest's core factual claims were checked against published sources, and the original freshness/framing failure was not reproduced in that sample. One retest supplied evidence for two semantically equivalent questions; no model-operated signed-in test or runtime deployment was performed for these closures. It does not establish that all answers or the other cases are fixed. The user confirmed that the app displayed the answer once and that the repeated paste was accidental.

Local deletion rehearsal completed with 66 passing checks, covering intake and selected cleanup paths. Full fulfillment remains open because Auth-only deletion leaves independent receipt bytes and immutable Bookkeeping relationships require a reviewed retention/cleanup procedure. See `SUPPORT_DELETION_REHEARSAL_20261007.md`. No real customer deletion was attempted.

The frontend support fix routes saved-history reports to the durable endpoint, adds reason/details and response context, and removes automatic alias retries and false claims of queued delivery. It is tested separately and recorded on the frontend release branch.

**Checklist status: partially complete.** Support coverage is confirmed by the owner, and backlog review is complete. Four unresolved cases and complete real-stack deletion fulfillment remain open. Independent mailbox testing was limited as described above; it is not an outstanding support-coverage requirement.
