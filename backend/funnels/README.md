# K139 · Enterprise NOVA Funnel Studio

First release: three editable landing-page templates, NOVA copy generation through the existing Astra provider, saved drafts, deliberate publication, a public inquiry form, transactional CRM capture, campaign links and lead-source reporting. The Flutter editor is under Utility → Funnel Studio for Enterprise users.

## Deployment and rollback

Apply `enterprise_funnel_studio` before deploying the backend. It adds three private RLS tables, one service-only RPC, and the `funnel` CRM source. The frontend uses `/api/funnels` with the current Supabase access token. Anonymous visitors only use `/f/:slug` and its form endpoint.

Deploy the backend release before the frontend release. Both use the existing Render services and require no new paid infrastructure. `OPENAI_API_KEY` is reused. Optional `KORLIX_FUNNEL_PUBLIC_BASE_URL` overrides the existing backend origin. Optional `KORLIX_FUNNEL_FORM_SECRET` supplies a stable random HMAC secret across restarts/instances; otherwise the single-instance service generates an ephemeral secret. Open forms must be reloaded after a restart in that mode. Configure a shared secret before scaling to multiple instances.

Rollback by deploying the previous frontend/backend commits. Keep the additive migration and captured leads. Do not drop tables to roll back UI. Pausing a page disables public capture; drafts and historical leads remain. Saved drafts never change the published snapshot until the owner confirms publication again.

## Access and data handling

- Every owner command checks current `user_profiles.tier` and owner identity in PostgreSQL. Browser roles have no table or RPC grants.
- Public access checks both publication and the owner's current Enterprise tier. Only the published document is returned.
- Form submission needs a signed, cookie-bound, page-version-bound nonce, a 1.5-second minimum form age and a 30-minute maximum. Replay is idempotent. Hidden honeypot, body/text limits, rate limits and a 2,000 submissions/funnel/day cap reduce basic abuse. These do not constitute identity verification or comprehensive bot protection.
- New contacts are marked `source=funnel`, `category=lead`, with inquiry-only transactional email consent. Calling permission remains `none`; marketing is not opted in. Phone identifiers are unverified and not normalized into the calling match key.
- Existing contacts and their suppression/permissions are never modified by anonymous submissions. Submission can create private follow-up tasks when the owner enabled a workflow; it never creates email recipients, sends messages, places calls, or launches ads.
- Form messages and UTM tags live in the private lead inbox. Identities and tags are visitor-supplied. Do not use them as verified facts. No cookies for advertising, third-party pixels, or tracking scripts are added.
- Counts are page requests (including bots and repeats) and submissions, not unique visitors, verified customers, revenue or multi-touch attribution.
- Owner data follows the existing account lifecycle: funnel deletion cascades lead rows, account deletion cascades funnels. Archiving a CRM contact does not delete its funnel inquiry. Dedicated lead deletion/retention controls remain a follow-up before broad rollout.
- Up to 50 funnels per owner. The legacy leads endpoint returns the latest 100 leads; the K146 inbox pages through all matching inquiries and reports the top eight matching source/campaign pairs. NOVA allows 10 attempts per owner per UTC day; failed generation attempts count. No streaming or automatic publication.

## Verification

`node --test test/funnels.test.mjs test/funnel_followups.test.mjs test/contacts_crm.test.mjs`

Tests execute both actual migrations in PGlite and the Express routes through HTTP. They cover role grants, ownership, downgrade and pause, snapshot isolation, version conflicts, publication consent, CRM permission preservation, nonce and cookie validation, expiration, retry deduplication, UTM capture, HTML escaping, unsafe URL rejection, and AI entitlement/budget enforcement. No external AI requests or real outreach occur.

Flutter: `flutter test test/funnel_studio_test.dart test/contacts_crm/contacts_screen_test.dart`; `flutter analyze lib/funnel_studio test/funnel_studio_test.dart`; `flutter build web --release --base-href=/app/`.

## Next stages (not implemented in this release)

1. Multi-step journeys, media uploads, domain mapping, lead retention/deletion UI, exports, stronger bot protection and verified contact ownership.
2. Fully autonomous lead sequences, verified-recipient enrollment, live outbound calling, booking and Workforce-aware routing. K140 below provides the initial reviewed follow-up workflow.
3. Integrated Ads Manager: Meta first, then Google. OAuth, platform approvals, account isolation, budget caps, explicit campaign review, pausing, spend retrieval and attribution reconciliation. Tracking links already work with ads created externally; this release does not launch ads or spend money.
4. A/B experiments, source-backed recommendations, Zoom-to-campaign drafts, approved agent-memory context, rehearsal, profit/cost reporting and agency roles.

Planning estimate remains 3–4 weeks for the broader private beta and 8–12 weeks for the advanced release with three engineers and shared design/QA. Ads integrations add approximately 4–8 engineering weeks; platform approval time is external.

## K140 · Reviewed follow-up workflows

Apply `funnel_followups` before the K140 backend. This additive migration adds two private RLS tables and service-only functions. An insert trigger queues tasks in the same transaction as inquiry capture, including when the browser is closed. Nothing is enabled or backfilled by deployment. Configure a workflow, review it, then enable it. Queue an older inquiry individually from Leads; duplicate task creation is idempotent.

The Follow-ups tab includes an editable email template, email/call-review channel selection, a due delay (immediate, 1 hour, 4 hours, 1 day), pause/resume, paginated task/activity lists, exact-message review, send confirmation, and dismiss/review outcomes. Delays control when tasks become due; they do not schedule automatic sending. Settings changes affect new tasks; each existing task preserves its content snapshot. Pausing the page/workflow or disabling email stops new send authorizations.

Email uses the existing server-bound NOVA identity, current Email Center settings, recipient permissions, approval and provider delivery service. It is available only to the owner of that configured NOVA profile, matching the existing email integration. Other Enterprise owners can manage tasks but must connect their approved NOVA integration before sending. The response is transactional, never a marketing subscription. New eligible recipients are linked only after explicit owner approval; inactive, suppressed and unsubscribed recipients are never reactivated here. Current contact address, archival, consent, Enterprise tier, page and workflow state are checked before sending. Existing provider quiet hours and sending limits still apply.

An atomic task claim and a stable per-task NOVA message idempotency key prevent concurrent sends. The exact recipient/content is checked before and after NOVA approval. Provider acceptance is labeled separately from delivery. A timeout or server crash moves the task to delivery review; there is no blind automatic retry. “Check delivery” is read/reconcile only. It returns an untouched draft to review only when no provider attempt is recorded. Attempted/uncertain/edited messages remain in NOVA Email Center for reconciliation. Processing tasks older than five minutes are marked uncertain when refreshed. Completed/dismissed tasks preserve an activity note; provider events remain in Email Center.

Call tasks show recorded phone/permission/inquiry/brief and can be marked reviewed. They do not place calls, and “reviewed” never means “called.” Real outbound calling is disabled on the current server. Leads are unverified; the owner reviews the address and inquiry before outreach. No real emails/calls are made by tests or deployment. Roll back the app commits while keeping the additive schema and data. If reverting the feature, pause configured workflows first to stop future task creation.

K140 verification: PGlite tests execute all three migrations and cover role denial, owner/tier checks, trigger queueing, replay, delays, versions, contact changes/archival, pause, channel disable, exact-message changes, double-click sends, uncertain provider outcomes, crash recovery, call-review semantics, pagination and HTTP auth. Provider calls are mocked. Flutter tests cover desktop/mobile layout, confirmation gating, paused/suppressed send controls, and call-review actions. The existing email service tests validate its provider contract separately.

## K141 · Owner-approved scheduled replies

**Schedule reply** reviews the exact recipient/content, selects a device-local date/time (stored as UTC), and explicitly approves one future email. Only unprepared emails qualify; choose at least two minutes ahead, after the task due time, within 30 days. Changing content requires cancellation and fresh approval. Deployment creates no schedules, recipients, drafts, emails, calls or ads.

Apply `funnel_scheduled_followups` before the backend. This extends the private task table with approved time, approval timestamp and bound agent, replaces the service-only command, and adds a service-only due scan and page-pause trigger. Browser RPC execution remains revoked; owner actions enforce current Enterprise membership and ownership.

The existing backend scans every 60 seconds, at most five due tasks for the server-bound NOVA owner per pass. Durable state survives browser closure and server restart. Task versions prevent duplicate claims across workers, alongside NOVA's provider idempotency. Schedules over 24 hours overdue return to review. Interrupted or uncertain attempts require delivery reconciliation, never automatic retries. Exact-minute delivery is not guaranteed.

Existing NOVA Email Autopilot readiness is required. Runtime permissions, emergency pause, quiet hours and caps are rechecked before and after claiming a message. The final callback checks current funnel, plan and contact permission immediately before provider access. These settings are not enabled by this release. NOVA retains the exact-message one-time approval nonce and audits source `owner_approved_funnel_schedule`. Blocked sends need review; they are not automatically moved to another sending window.

Cancel works until sending starts. Workflow pause, email-channel disable and funnel pause cancel pending schedules atomically; resuming requires fresh approval. Sending already underway may finish. Changed consent, addresses, archival, downgrade, expired timing or changed agent binding block execution. New inquiries still create private review tasks; this is not automatic enrollment into multi-step sequences.

Optional `KORLIX_FUNNEL_SCHEDULER_ENABLED=false` disables creation and scanning. This pauses execution, not approval: cancel pending schedules or pause workflows before re-enabling if approvals must be revoked. Rollback: pause workflows first, deploy previous app commits and preserve the additive schema. The old interface cannot cancel scheduled rows. Ads Manager and fully autonomous multi-step sequences remain subsequent milestones.

Validation: real migration tests cover approval/timing, cancellation, pause, restart, concurrent runners, suppression, address changes, archival, downgrade, overdue expiry, uncertain delivery and browser execution denial. Delivery regressions verify Autopilot before/after claims and final callback aborts. Mobile/desktop widget tests verify approval, UTC payloads, cancellation and permission gating. No real outreach is used in tests.

## K142 · Reviewed inquiry sequences

Use **Build sequence** on an unprepared email task to review 2–5 exact inquiry responses and their send times. One approval enrolls that inquiry only; new leads are never automatically enrolled. Each inquiry has one sequence, preserving its original queue task and history. These are transactional responses to a specific inquiry, not promotional marketing campaigns. A connected server-bound NOVA Email profile with Autopilot readiness is required.

The private `korlix_funnel_sequences` table and service-only command store the approval and progress. Sequence steps reuse the durable follow-up queue and NOVA delivery service. The next step is eligible only after its scheduled time AND at least one hour after the preceding provider acceptance. Provider acceptance is not confirmation of inbox delivery. Existing daily caps, quiet hours, contact permissions and suppression remain enforced.

**View sequence** shows the full timeline. **Pause sequence** revokes all pending approvals. **Review & resume** shows the exact remaining messages and requires fresh times and approval; accepted emails are excluded. Prepared, in-progress or uncertain attempts must be reconciled in Email Center and are not retried by sequence resume. **Mark replied** and **Cancel sequence** stop remaining unprepared messages. Mark replied is explicitly manual; automatic inbound-reply detection is not implemented. A send already underway may finish.

Page/workflow pause, overdue expiry, permission changes or uncertain outcomes pause all remaining steps atomically. Task and sequence versions prevent duplicate enrollment, stale approval and overlapping claims. Browser table/RPC grants remain revoked; authenticated owner actions check current Enterprise status.

Migration `funnel_sequences` must precede the backend and frontend. No existing inquiry is enrolled and no email/call/ad is sent by deployment or tests. Rollback: pause workflows or disable `KORLIX_FUNNEL_SCHEDULER_ENABLED`, preserve the additive schema and stored history, and redeploy the prior app. Existing schedules should be reviewed before re-enabling.


## K143 · Campaign planning and manual results

Enterprise owners now have **Ads workspace** inside each funnel. Save up to 50 campaign plans per funnel, choose Meta/Google/Other, draft text with NOVA, plan a USD daily budget and 1–90 day duration, review the plan against the current published page, and copy its brief and stable tagged destination URL. The channel is fixed after creation to preserve historical source matching. Editing resets review; republishing the landing page makes a prior review stale. Archiving preserves history and does not pause an external ad.

This release does not connect ad accounts, upload creative, launch ads, synchronize platform statistics, authorize spending, or enforce platform budgets. NOVA copy uses the existing Astra text provider and shares the existing 10 daily draft-attempt budget with funnel generation. Generated copy remains editable and requires human review.

Results are explicitly owner-entered USD totals for UTC calendar dates. One row per campaign/date is replaced on correction, with campaign-version concurrency checks; removal is confirmed. Reporting dates are within the last 730 days; at most 731 daily rows per campaign. All-time tagged inquiry counts require this campaign's immutable key and source. Cost per tagged inquiry uses only submissions on dates with a manual report. Visitor-supplied tags are unverified, and these figures are not platform attribution, verified revenue, or ROAS. Source data remains visible in the existing Leads tab and CRM. No outreach or real paid ad is created by this release.

Storage is additive and private: RLS enabled, client table and RPC grants revoked, SECURITY INVOKER service commands pinned to public/pg_temp, current Enterprise and funnel ownership checked on every call. HTTP responses are no-store. Rollback by redeploying the previous frontend/backend; keep the campaign data/schema. Existing inquiry follow-up and sequence execution are unchanged.

Next integration: owner-scoped Meta OAuth, app permissions, account/page selection, secure token storage, reviewed campaign creation with platform budget controls, and authoritative spend synchronization. Google follows. Platform approvals and user account authorization are separate dependencies; reviewed local plans do not become launch authorization automatically.

## K144 · Meta ad-account connection

Enterprise owners can prepare a Meta sign-in, continue to Meta from a direct tap, return to the original KORLIX window and **Finish connection**. Choose **Use this account** after the account list loads. Connections belong to the signed-in owner and are shared across that owner's funnel workspaces. Cached names, account IDs, currency, timezone and provider status can be refreshed or searched. This milestone reads account details only: it does not publish ads, select Facebook Pages, upload creative, retrieve spend or authorize budget expenditure.

Apply `funnel_meta_connection` before deploying the backend, then deploy the frontend. Two private RLS tables and one service-only SECURITY INVOKER command are added. Client table, sequence and RPC grants are revoked. Current Enterprise membership is checked for every owner command. Disconnect deletes the encrypted token, cached account details and pending authorization; manually entered plans/results remain. It does not stop externally running ads or itself revoke Meta permissions. Account deletion cascades both private tables.

The backend requires all of these settings before Connect Meta is enabled:

| Setting | Value |
| --- | --- |
| `KORLIX_META_ENABLED` | `true` after setup |
| `KORLIX_META_APP_ID` | Numeric Meta app ID |
| `KORLIX_META_APP_SECRET` | App secret, stored only in Render environment |
| `KORLIX_META_LOGIN_CONFIG_ID` | Facebook Login for Business configuration ID |
| `KORLIX_META_TOKEN_KEY` | Independent 32 random bytes encoded as standard base64 |
| `KORLIX_META_REDIRECT_URI` | `https://chee-chai-chee-backend.onrender.com/api/funnels/meta/callback` |
| `KORLIX_META_API_VERSION` | Optional; defaults to `v26.0` |

Configure Facebook Login for Business with **User access tokens** and `ads_read`, allowing the owner to choose available assets. This implementation does not support system-user login. Register the exact redirect URI above. Set the deauthorization callback to `https://chee-chai-chee-backend.onrender.com/api/funnels/meta/deauthorize`. For Meta's User Data Deletion field, choose the **instructions URL** option and enter `https://chee-chai-chee-backend.onrender.com/api/funnels/meta/data-deletion`; that page is not a data-deletion callback. Configure the published KORLIX privacy-policy URL in the Meta app. Meta business verification, permission access level, app review and Live mode may be necessary for accounts outside the app's test roles. Verify those requirements in the app dashboard before opening access to customers.

Use Meta's manual authorization-code flow with a single-use hashed state, ten-minute attempt and a separate private finish proof retained only by the initiating KORLIX window. The server exchanges for a long-lived user token and checks its app, type, `ads_read`, user ID and expiry. The token is encrypted using AES-256-GCM bound to the KORLIX owner and attempt. The browser never receives it. Pending candidates are encrypted and expire; expired attempts are removed on subsequent successful owner commands. Graph reads include `appsecret_proof`, fixed Graph hosts, bounded pagination and timeouts. API errors are redacted. Reconnect retains the previous connection until successfully finished; globally increasing versions reject late responses even across disconnect/reconnect. Verified Meta deauthorization deletes matching connections, with timestamps protecting newer authorizations.

Changing the app, login configuration, encryption key, API version or redirect invalidates existing access and requires reconnecting. There is no refresh-token flow. The interface displays access expiry and reconnect guidance; provider revocation marks the connection unavailable. Keep the encryption key backed up in the platform's secret-management system. Do not include tokens, secrets or callback codes in support messages. `/api/funnels/meta/readiness` returns only configuration readiness and `ad_publishing_ready:false`.

Validation uses mocked Meta HTTP responses, real PostgreSQL-compatible migration execution, private-role and owner/tier checks, single-use state, private finish proof, cancellation, expiry, account selection, stale response rejection, token encryption, signed deauthorization, and phone/desktop widget tests. These do not prove real Meta app approval or a successful live account connection. Complete one owner-controlled live sign-in and account selection after configuring the app; no ad spend is required.

Rollback: disable `KORLIX_META_ENABLED`, deploy previous app commits, preserve the additive schema and encrypted records, and review stored connections before re-enabling. No campaign, outreach recipient, email, call or paid ad is created by this migration or deployment.

Provider references: [manual login](https://developers.facebook.com/docs/facebook-login/guides/advanced/manual-flow/), [Login for Business](https://developers.facebook.com/docs/facebook-login/facebook-login-for-business/), [long-lived tokens](https://developers.facebook.com/docs/facebook-login/guides/access-tokens/get-long-lived/), [deletion options](https://developers.facebook.com/docs/development/create-an-app/app-dashboard/data-deletion-callback/), [current official SDK API version](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/apiconfig.py).


## K146: Lead inbox and filtered export

Enterprise owners can search name, email, phone and message text, filter by exact source and inclusive UTC dates, and browse every matching inquiry 25 at a time. The inbox reports total and matching inquiry counts plus the top eight source/campaign pairs. It uses receipt-time and ID cursors with a server snapshot so newly received inquiries appear on refresh. This is a receipt-time cutoff, not a durable database snapshot: deletions still take effect. Source tags and submitted identities remain unverified.

`GET /api/funnels/:id/inbox` accepts `search`, `source`, `from`, `to`, `snapshot`, and `cursor`. `GET /api/funnels/:id/inbox/export` accepts the same filters without a cursor and returns a UTF-8 CSV payload covering all matches at the requested cutoff. Exports above 5,000 matches fail without a partial file; narrow the dates or filters. Cells are quoted and formula-like input is prefixed as text. Browser downloads and native file sharing are supported. The service-only `korlix_funnel_inbox_v1` RPC rechecks current Enterprise entitlement and funnel ownership for each read/export. There are no contact, permission, email, call or ad mutations in this feature.

Deploy the additive `20260922145937_funnel_lead_inbox.sql` migration before the backend, then deploy the frontend. Older frontend versions can keep using `/leads`. Meta activation is still deferred.

Validation: `node --test backend/test/funnel_inbox.test.mjs` exercises the real migrations and HTTP handlers, including more than 100 tied-timestamp inquiries, snapshot paging, tenant boundaries, tier revocation, malformed filters, CSV injection and oversized exports. Flutter inbox tests cover server filters, pagination, export failures, access loss, navigation races and narrow layouts.

## K147 · Read-only inquiry rehearsal

`POST /api/funnels/:id/rehearsal` validates an owner-selected sample and previews
its path using the actual public page/form validators and saved workflow.
The body specifies `version`, `source` (`draft` or `published`) and `scenario`
(`valid`, `missing_consent`, `invalid_email`). Draft mode additionally receives
`name` and `document` from the current editor, including unsaved edits. It is
explicitly hypothetical until reviewed publication. Published mode uses only
the published snapshot and blocks capture predictions for paused/draft pages.

Apply `20260922163931_funnel_rehearsal_readonly.sql` before the backend and then
the frontend. Its sole new function is STABLE and SECURITY INVOKER, with a
pinned search path and execution granted only to service_role. It checks the
current Enterprise tier and funnel owner on every request, reads the page and
optional workflow, and writes no rows. No tables or browser grants are added.
The existing follow-up state command is deliberately not used: that command
initializes settings and reconciles stale processing tasks.

Rehearsal uses fictitious sample data. It never invokes capture, queueing,
contact mutation, email services, calls, ads, schedulers, or NOVA generation.
Preview template interpolation matches the SQL replacement order and character
limits. Times represent task due delays, never automatic send times. No new
inquiry is automatically enrolled in a sequence. Every response is no-store.
Live form cookies, rate limits, existing contact permissions, provider readiness,
delivery, real inquiry capture and CSV export remain separate checks.

Verification: `node --test backend/test/funnel_rehearsal.test.mjs`. The tests
execute the actual migrations, use read-only transactions for the new RPC,
check role/owner/tier denial, compare table contents before/after requests,
preserve an intentionally stale processing task, check unconfigured workflows,
draft/published separation, invalid samples and stale page versions.
Rollback by deploying the prior app commits; retain the additive function.

## K148 · Owner-managed lead stages and private notes

Enterprise owners can assign **New**, **In review**, **Qualified**, **Won** or
**Lost** and a private note of up to 4,000 characters from **Manage lead** in the
inbox. The new `GET/PATCH /api/funnels/:id/inbox/:leadId` routes use the
service-only `korlix_funnel_lead_manage_v1` RPC. Every request checks current
Enterprise membership and funnel/lead ownership. PATCH accepts only `version`,
`status` and `private_note`; row locking plus `inbox_version` prevents lost
updates. No-op saves preserve the version and timestamp. Visitor-submitted
identity/message/consent, contact permissions and delivery state are untouched.

The editor reads the existing scheduled and delivery-review task counts without
initializing settings or reconciling tasks. Changing an inbox stage does not
stop an approved follow-up, grant outreach permission or record revenue. The
interface says so and directs scheduling decisions to Follow-ups. New public
submissions cannot choose these owner fields; their defaults are New/empty.

Inbox and CSV routes accept the same optional `status` filter. Keyset cursors
bind it along with existing filters. `status_totals` counts each stage over the
applied search/source/date subset before applying the status filter. CSV appends
owner-set status, private note and metadata-update time; spreadsheet-injection
escaping and complete-export limits remain in force. Receipt-time cutoffs do
not freeze later metadata edits. Older inbox/lead readers remain compatible.

Deploy `20260922172151_funnel_lead_management.sql`, backend, then frontend.
The migration adds only private lead metadata and service functions; existing
browser table/RPC grants stay revoked. The inbox function remains STABLE and
both functions use SECURITY INVOKER with a fixed search path. No real inquiry
is edited and no workflow/email/call/ad is created by the release process.

Verification uses real migration execution, tenant/tier/browser isolation,
optimistic-conflict checks, preservation of other tables and original inquiry
fields, filtered pagination/exports, and public capture isolation. Widget
checks cover fresh-version edits, discard/reload, access loss, pending saves,
late responses and desktop/phone layouts. User acceptance is deferred.
Rollback by reverting app commits while retaining the additive schema and
saved status/note data. Dedicated deletion/retention controls remain separate.

## K149 · Reviewed inquiry cleanup

`POST /api/funnels/:id/inbox/cleanup/preview` accepts a single `lead_id`, or
`mode: retention` with an exclusive UTC `before` date and `statuses` containing
Won/Lost (lowercase API values). Retention selection is independent of inbox
filters. It is manual, with no recurring deletion job. The database returns
counts, up to five protected examples and the oldest 100 eligible inquiries,
including the local resolved-task/stopped-sequence counts removed with each.
The preview RPC is STABLE and works in a read-only transaction.

Open tasks (review/scheduled/processing/needs_review), active/paused sequences,
any recorded message ID or sent task, and mismatched child funnel associations
protect an inquiry from removal. A completed task with a message ID remains
protected. CRM contacts, permissions, suppressions and Email Center records
are retained. This feature is inbox cleanup, not whole-account data erasure.
Inquiry, stage and campaign totals reflect the remaining records after removal.

The server signs a ten-minute review using the form secret, a separate HMAC
domain, actor/funnel IDs, a random review ID, and exact inquiry IDs/fingerprints.
No fingerprint is exposed as an editable API field. Deletion accepts only this
review token and the exact `confirmation: DELETE`. A restart can invalidate
reviews when no stable form secret is configured; a fresh preview is safe.
The service-only delete RPC rechecks current Enterprise ownership, locks the
funnel/inquiries/tasks/sequences, compares fingerprints and eligibility, and
deletes all selected local records atomically. Newly changed records reject the
whole selection. A short receipt containing no inquiry contents makes identical
retries idempotent. Receipts older than 30 days are purged during owner cleanup.

Recent deletions retain only a request UUID and expiry until 31 minutes after
capture. Public capture checks this marker, so a still-valid 30-minute form
token cannot recreate the deleted inquiry or enqueue its follow-ups. Expired
markers are purged on subsequent funnel capture/cleanup. Neither expiry is a
scheduled erasure promise. Existing account/funnel foreign-key cascades apply.

Deploy `20260922180817_funnel_inquiry_cleanup.sql`, backend, then frontend.
All new tables and functions remain service-only, with RLS on tables and
SECURITY INVOKER/fixed search paths on functions. The migration only installs
schema/functions: release work does not delete production inquiries.

Verification: `node --test backend/test/funnel*.test.mjs`. The cleanup suite
executes actual migrations against local Postgres-compatible PGlite fixtures,
checking role/tier/owner denial, UTC boundaries, batch limits, blocked activity,
signed review/confirmation, stale state, all-or-nothing failures, concurrent HTTP
review outcomes, receipt retries, retained CRM/email records and public replay
protection. PGlite serializes database work; this is not a claim of a production
multi-connection load test. Base public capture and lead-management regressions
also run with the new migration installed. User acceptance remains deferred.

Rollback app commits to K148 if needed, retaining this schema and the updated
public capture function. Do not restore the older capture function or remove
replay markers while recent form tokens may still be valid. Reverting code does
not recover permanently deleted inquiry data.

## K150 · Guided inquiry forms

Page documents now accept `form_mode: single | guided`, defaulting to `single`
when absent. Existing live pages keep their current form until an owner saves
and publishes a guided choice. Draft/public snapshots and optimistic versions
remain unchanged. NOVA copy replacement and page duplication preserve the form
choice. No database migration, new service, paid integration or credential is
needed; deploy backend before frontend.

Guided mode presents contact details, request/consent, then an explicit review
and send step. Native HTML POST forms work without JavaScript. The intermediate
`POST /f/:slug/step` endpoint validates the existing cookie-bound, version-bound
form nonce and fresh published-page/Enterprise availability. It reuses the
public read command with counting disabled and never calls capture, CRM,
queueing, AI or delivery. Visitor fields are posted in bodies, not URL query
strings. Responses are no-store, noindex, and retain the restrictive CSP.

Validation errors redisplay bounded, escaped values. Back/edit retains details
and clears consent from the editable request step. The review shows submitted
identity, phone, message and inquiry-only consent. A domain-separated HMAC
binds the normalized fields, all attribution tags and original form nonce.
Guided final submission rejects a missing or changed review. No intermediate
step extends the original 30-minute expiry or changes the nonce/cookie.

The final capture endpoint uses the same database transaction and request ID
as a single-page form. Existing CRM permissions, suppression checks and reviewed
follow-up behavior remain. An uncertain storage response offers the same signed
review/nonce for a safe retry without claiming success. K149 replay markers still
prevent a recent deleted inquiry from being recreated. Progress steps are not
partial leads, conversion events, completed bookings or message delivery.

The Flutter preview offers all three steps using labeled sample details;
preview interaction creates no edits or network activity. Rehearsal describes
the selected journey while explicitly distinguishing the simulation from actual
browser navigation. A long dashboard badge now wraps at narrow widths and
enlarged text instead of overflowing.

Verification uses actual migration-backed capture, public Express HTTP routes,
role/tier and stale-page denial, field/UTM preservation, no-write intermediate
snapshots, fresh consent, signed-review tampering, repeated final submissions,
uncertain-response retry, XSS escaping and disabled previews. Flutter checks
cover old-document defaults, save without publish, preserved copy/duplication,
preview-only interaction, mode reset and 1440/390/320 px layouts (1.3x text at
320). User live acceptance and Meta activation remain deferred.

Rollback both app releases to K149 to restore single-page forms. Retain all
database content and K149 replay protection. Open guided forms should be
reloaded. Older editors ignore/drop the new form choice on subsequent saves;
rollback does not remove existing inquiries. Arbitrary multi-page builders,
branching questions, custom fields and partial-lead tracking are separate scope.

## K151 · Private logo and main-image library

Page documents optionally contain `logo` and `hero_image`, each `{id, alt}`.
The page editor uploads or reuses an owner image, edits its description, and
removes the reference without deleting the original. Selection is an unsaved
edit until **Save draft**. Only reviewed publication changes the live images.
NOVA copy replacement and draft duplication preserve these fields. Descriptions
are required at publication. Public images use the same origin and CSP as the
page; no external image URLs, embeds, scripts or image-fetch proxy are accepted.

`GET/POST /api/funnels/images` lists/uploads images; authenticated
`GET /api/funnels/images/:id` retrieves private bytes. `DELETE` requires
`confirmed:true` and refuses any asset used by a saved draft or published
snapshot, including paused pages. Unsaved editor selections are protected in
the current picker, but are not durable references until saved. If another
tab deletes an unused asset, saving a stale reference fails with a conflict.

Uploads accept one still JPG, PNG or WebP, at most 5 MiB and 16 megapixels.
Sharp verifies format, decodes, applies orientation, strips metadata and
re-encodes WebP at at most 1600 × 1600 pixels and 512 KiB. Detailed images may
be reduced further; review the optimized result. SVG, GIF, animation and video
are excluded. Decode concurrency is capped at two per backend instance;
uploads at ten per owner per minute. Owner image requests have a separate
120/minute budget so thumbnails do not consume the general editing budget.

The additive `funnel_images` migration stores these small optimized assets in
a separate private table, capped at 50 assets / 20 MiB per owner. Bytes are
never included in page documents or library list responses. This bounded brand
image library uses the existing database, not a general-purpose media store.
Account deletion cascades bytes and metadata together. Identical optimized
bytes deduplicate per owner, so retrying an uncertain upload does not consume
another slot. Failed/unconfirmed uploads should be reconciled with **Refresh
library**. Uploaded assets are retained until the owner deletes them or deletes
the account; there is no timed purge of unused images.

The service-only RPC and document trigger use SECURITY INVOKER, pinned search
paths and revoked browser grants; RLS is enabled. Document writes lock referenced
image rows while checking ownership. Deletion locks the image and checks all
saved references; quota checks serialize uploads per owner. Immutable asset IDs
allow reuse across that owner's funnels and never grant another owner access.
`GET /f/:slug/media/:id` serves only an image referenced by that currently
published page, with a fresh Enterprise check and no-store headers. It does not
increment page counts. Pause, downgrade, removal and republishing stop future
reads. Images already downloaded by a visitor cannot be recalled.

Deploy the migration, backend, then frontend. Rollback app code while retaining
the image table and reference trigger. Older editors may drop image fields on
save, so avoid editing image-bearing pages with the old frontend. No production
image, draft or page is uploaded/edited/published by deployment. Tests use local
fixtures; browser picking on the user's iPad/phone stays in the deferred pass.

Verification: `node --test backend/test/funnel_images.test.mjs` uses actual
migration execution, Sharp decoding and multipart HTTP, including privacy,
metadata stripping, limits, snapshots, role/owner/tier denial, in-use deletion,
stale refs and retry deduplication. PGlite serializes database calls; this is
not a production concurrent-load test. Flutter coverage exercises upload,
reuse, cancellation, pending work, access loss, deletion conflicts and narrow
layouts. See the frontend `IMAGES.md` for the owner workflow.

Implementation references: [Sharp input limits](https://sharp.pixelplumbing.com/api-constructor/),
[Sharp output and metadata defaults](https://sharp.pixelplumbing.com/api-output/).

## K152 · Configurable page sections

An optional `sections` array controls content below the fixed hero. It contains
exactly one `main_image`, `benefits`, `inquiry` and `faq`, plus zero to four `text`
entries. Each text entry has a unique `text-1` through `text-4` ID, heading (120
characters), body (1,000) and `visible:true`. Only benefits and FAQs may be hidden.
The inquiry section always appears once; remove an unwanted image through its
existing reference. Legacy documents without `sections` use the previous order.

The owner editor uses arrows to reorder, switches for optional visibility, and
plain-text fields. Hidden section copy remains in the document. Save updates the
draft; explicit publication updates the live snapshot. Added text can be saved
unfinished but publication and a publish-ready rehearsal reject missing heading
or body. NOVA-generated copy and duplication retain the owner's section choices.
All public text is escaped; no arbitrary HTML, URLs, scripts or image references
are accepted through section definitions. The preview follows the same order.

The existing JSONB draft/published columns carry the array. No migration is
needed. Normalization limits explicit-section documents to 17,200 UTF-8 JSON
bytes, leaving whitespace headroom under the existing 18,000-byte JSONB limit.
The total budget may be reached before all individual text limits, especially
with multilingual copy. A clear 400 asks the owner to shorten the page.

Verification adds normalization/rendering tests and HTTP save/publish tests for
legacy defaults, malformed/duplicate sections, mandatory form retention, XSS,
guided forms, draft/live isolation, ownership, stale versions, duplication and
unfinished copy. Flutter checks cover reordered text identity, visibility,
save/reload, four-section limits, generation/clone preservation and layouts at
1440/390/320 pixels (1.3x text at 320). Live owner acceptance remains deferred.

Deploy backend then frontend. Roll back both to K151 if required; retain the
existing database and replay/image protections. Old code renders the legacy
order and may drop the new sections on a subsequent save, so avoid editing pages
with custom sections until the updated editor is restored. This release does
not introduce multi-page branching, custom form fields or automatic publication.

## K153 · Custom inquiry questions

The document's optional `questions` list contains up to four stable IDs (`q-1`
through `q-4`), each with `type` (`text` or `choice`), label (120 characters),
required flag and options. Text answers allow 500 characters. Choice questions
require 2–8 distinct nonempty choices, each at most 80 characters. Drafts may
have incomplete labels/choices; publication requires complete definitions.
NOVA generation and duplication retain the owner's questions and choices.

Single-page forms show questions with the request. Guided forms show them in
step two and in the signed final review. Back/edit navigation carries answers
without storing a partial inquiry. Required and choice-membership validation uses
the published snapshot. Changed answers invalidate the review signature. The
URL-encoded request ceiling is 64 KiB to accommodate maximum multilingual inputs;
all individual limits, rate limits, cookie/nonce and published-version checks
remain enforced. Public labels/values are escaped, including selects and review.

The additive `funnel_inquiry_questions` migration adds a bounded private JSONB
`answers` array to each lead. Capture saves `{id,label,type,value}` using labels
and types from the locked published document, never supplied visitor metadata.
The answer snapshot is inserted in the existing capture transaction. Failed
capture rolls back the contact, inquiry and usage changes; repeated or deleted
requests retain K149 idempotency. Existing inquiries have `[]`. Owner/tier guards
and browser-role revocations continue to protect answers. The new validation
helper is SECURITY INVOKER with pinned search path and service-only execution.

Leads displays the original questions/answers in an expandable card. CSV adds a
final **Question answers** column, preserving existing column positions, quoting,
line breaks and formula protection. Existing inbox search continues to match
name, email, phone and message. Answers do not update CRM contact attributes,
owner notes/statuses, email permissions or calling permissions. Existing cleanup
removes them with their lead; no separate retention store is created. Rehearsal
uses clearly synthetic question answers and still performs no live actions.

Deploy the additive migration, then backend, then frontend. Legacy pages work
while the migration is ahead of app code. Preserve the migration and stored
answers on rollback. K152 code does not understand custom questions: capture for
pages with published questions will fail validation rather than silently drop
answers. Restore K153 backend, or deliberately remove questions and republish
those pages before reverting app code. Do not alter owner content automatically.

Verification uses migration-backed HTTP capture, malformed/duplicate answers,
required/choice validation, original-label snapshots, transactional rollback,
owner/browser-role denial, guided tamper detection, uncertain-response retries,
deleted-request replay suppression and maximum multilingual inputs. Flutter
checks cover creation/types/options, required flags, reordering, max count,
save/reload, copy preservation, preview/review and Leads answer display at
1440/390/320 px with 1.3x text at 320. Real-device acceptance stays deferred.

This release adds qualification questions within the current inquiry journey.
Conditional branching, booking rules, custom CRM fields and automatic outreach
based on answers remain separate work.

Implementation reference: [Supabase database functions and privileges](https://supabase.com/docs/guides/database/functions).

## K154 · Conditional inquiry questions

An inquiry question can use `show_when: {question_id, equals}` to appear only
when an earlier multiple-choice question has the selected answer. Dependencies
may chain, but must point backward to an existing choice; publication rejects
cycles, missing sources, changed types, and removed choices. Drafts may retain
unfinished conditions. There are still at most four questions in total.

Both public form styles reveal matching questions as choices change. Inactive
controls are hidden, disabled, no longer required, and cleared. A fixed browser
script is permitted by its exact SHA-256 CSP hash; user content remains escaped
HTML attributes/text. There are no external scripts, requests or analytics.
If the enhancement cannot run, **Update questions** posts to the cookie-bound
step route without capture. It preserves contact/request fields, clears hidden
answers and requests consent again. Native submission also redisplays missing
required visible questions without losing the form. Refreshing does not extend
the nonce lifetime, count an inquiry, or create a contact/task.

Final validation resolves active questions in order on the server. Unknown
answer fields are rejected; answers for known but inactive branches are omitted.
The database validator independently resolves the same published graph, enforces
visible required/choice answers, and stores only those answer snapshots. Existing
inquiry wording, CSV behavior, cleanup, nonce replay, consent and the atomic
capture transaction stay intact. Guided review binds the active answers and
branch-driving choices; a changed path requires a new review.

Rehearsal covers one synthetic path using first choices, explicitly not every
branch. The Flutter preview lets owners try paths without changing drafts or
saving preview answers. Source removal clears dependent rule values so reusing
a question ID does not silently reconnect the condition. Owners repair invalid
conditions before publication. NOVA generation and draft copies preserve rules.

Release order: apply `20260922215214_funnel_conditional_questions.sql`, then
backend, then frontend. The migration replaces only the service-only immutable
answer helper, guarded against intervening K153 changes. No table, browser grant,
external integration, owner funnel publication or outreach is added. The database migration was applied after explicit production approval on 22 September 2026; its committed filename matches the applied version.

Rollback: retain the helper and submitted snapshots. K153 app code is compatible
with existing unconditional pages but does not understand conditional definitions;
its editor can strip rules on save and public forms show all questions. Once an
owner publishes conditions, prefer restoring K154 or have the owner deliberately
remove conditions and republish before reverting app code. Do not automatically
rewrite owner drafts or published content.

Validation includes real migration execution, branch chains, stale/forged hidden
answers, independent database rejection, no partial records on refresh, native
fallback, cookie/publication protections, signed-review tampering, idempotency,
CSP hash/escaping, desktop/phone/enlarged-text layouts and existing regressions.
Real-device acceptance remains deferred. Booking/routing and further ads work
remain separate milestones; conditional questions do not route or contact leads.

## K155 · Answer-based booking links

`booking_routes` contains up to four ordered rules: `id` (`route-1`…`route-4`),
`name` (80 chars), `question_id`, `equals` (80 chars), `url` (public HTTPS,
1000 chars) and `button_label` (60 chars). A rule references a current
multiple-choice answer. Drafts may remain incomplete; publishing requires every
field, valid choice references and distinct answer conditions. The first matching
rule wins; otherwise the existing `booking_url` is used, or no button is shown.
Only active validated answers can match. No contact or answer parameters are
appended to the link and no external booking request or automatic redirect runs.

Capture stores an immutable private `outcome` beside the answer snapshot in the
same transaction. It records the original route ID/name, thank-you copy, URL and
button label. The service-only `korlix_funnel_outcome_v1` independently checks
route definitions and active answers. Existing leads receive `{}`: no historical
outcome is inferred. Owner Leads/CSV show the next step offered, explicitly not
a confirmed appointment. Cleanup deletes this snapshot with its inquiry.

After successful capture the server issues a separate `kr_<slug>` receipt cookie
(HttpOnly, Secure, SameSite=Lax, path-scoped, 30 minutes). Its domain-separated
HMAC covers only the slug, nonce and issue time. The existing form secret signs
it; if no stable secret is configured, a server restart invalidates receipts as
it already does form tokens. `?received=1` alone cannot display confirmation.
A verified receipt looks up only its saved message/link/button via the private
`receipt` command. Republished copy cannot replace that outcome; absent/expired
cookies and deleted/historical outcomes display an unavailable notice instead.
Public reads retain current published-page and Enterprise checks. Neither
contact details, answers, nor private route names are returned by this command.

The editor offers rule ordering and a live synthetic receipt preview. Removing
a source question clears its route reference so a reused question ID cannot
silently reconnect. Generated copy and duplication preserve independent routes.
Rehearsal reports its first-choice sample outcome; follow-up `{{booking_url}}`
still uses the default link. This release does not reserve calendar slots,
confirm appointments, enroll sequences, send messages, or activate ads.

Release order, after explicit production approval:
1. Apply `20260922222703_funnel_booking_routes.sql` (capture source guard
   `a5ccdff3945815fd62cb96fae0fff2e7`).
2. Deploy the backend; then deploy the frontend.
3. Verify live versions, health, browser-role restrictions, and grants.

Rollback preserves the additive column, helper, and saved outcomes. K154
application code is compatible with documents without booking routes, but its
editor can strip new rules on save and its public confirmation uses the default
URL. After routes are published, prefer restoring K155. Any return to K154
requires the owner to review and deliberately remove routes/republish first;
never rewrite owner content automatically.

Automated verification covers routing priority, conditional hidden answers,
invalid publication, receipt cookie tampering/expiry/cross-page reuse,
republished immutable outcomes, capture rollback, idempotent and uncertain
responses, deletion/replay, browser-role denial, escaped HTML, CSV safety,
synthetic rehearsal, editor save/reload, question deletion, and responsive views.
User-run live acceptance and Meta activation remain deferred.

## K156 · On-demand Meta account performance

`GET /api/funnels/meta/performance?days=7&version=<connection-version>&account_id=act_<id>`
returns a fresh account-level report for exactly 7, 30 or 90 completed calendar
days in the selected ad account's timezone. The endpoint accepts only these
three query keys. It reuses Enterprise/owner checks, the service-only encrypted
Meta connection and existing `ads_read` permission. Platform configuration,
credential expiry, the current selected account and connection version must
pass before a request. Current account metadata supplies currency/timezone;
access, binding and version are rechecked after remote work so a late response
cannot survive disconnect, reselection or downgrade. The endpoint has its own
10-requests-per-owner-per-minute limit and returns `Cache-Control: no-store`.

The provider performs GET requests on the fixed Graph API host, using the
existing configured API version, authorization header, app-secret proof,
redirect rejection and 10-second per-request timeout. Account-level insights
request `account_id`, `account_currency`, `date_start`, `date_stop`, `spend`,
`impressions` and `clicks`, with `time_increment=1`, a bounded `time_range`, and
`limit=100`. Up to three pages are allowed. Only an opaque `after` cursor is
reused; provider-supplied next URLs are never followed. Missing/repeated cursors,
page overflow or malformed rows fail the entire report without partial totals.

Rows must have the exact selected account/currency, a unique real date inside
the requested range, matching daily start/stop dates, nonnegative decimal spend
(up to six fractional digits) and safe integer counts. BigInt arithmetic sums
spend without floating-point rounding. Responses contain decimal strings for
money, integer counts, newest-first daily rows, returned-row count, account
name/ID/currency/timezone, date range and retrieval time. No token, provider
identity, binding or encrypted credential is returned. Provider errors remain
redacted; revoked access uses the existing local reconnect/invalidation flow.

No reporting records or background jobs are created. Existing connection RPCs
retain their OAuth-attempt cleanup and credential-invalidation behavior; this
is not a new read-only SQL transaction. No database migration, environment key,
permission scope or configuration activation is introduced.

The owner panel loads only on an explicit tap, clears old values when changing
period/account or starting another request, and suppresses stale responses.
Totals cover the entire selected account and all campaigns, not this funnel's
attributed performance, verified leads, revenue or ROAS. `clicks` is labeled
“Clicks (all).” Missing days are not filled; no returned rows displays an empty
state rather than zero-spend totals. Owner-entered campaign reports remain
separate. Meta may revise historical figures; this is not billing reconciliation.

Automated checks use mock Graph responses and local database fixtures. They
cover bounds, exact decimals, timezone/DST/leap dates, invalid data, fixed-host
pagination, redaction, owner isolation, expiry, request limits, revoked access,
concurrent disconnect/reselection/downgrade, UI state, integration and responsive
views. They do not verify real Meta app approval, an owner's live connection,
or actual spend. User-run acceptance and Meta activation remain deferred.

After explicit production approval, deploy backend then frontend. K155 is a
compatible application rollback with no schema rollback needed. The frontend
can be restored first to remove reporting controls before restoring K155's
backend. No owner documents or saved reporting data require conversion.

Primary API references used for the implementation:
- [Meta's official AdsInsights field definitions](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/adsinsights.py)
- [Meta's official AdAccount get_insights parameter definitions](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/adaccount.py)

## K157 · Meta campaign comparison

`GET /api/funnels/meta/campaign-performance` takes the same `days`, `version`
and `account_id` query as account performance. Both endpoints share the
10-request-per-owner-per-minute reporting limit and the same before/after
owner, Enterprise, credential and selected-account checks. No campaign ID,
provider cursor, fields, filters, remote URL or arbitrary range is accepted
from the browser.

The provider requests account-scoped insights with `level=campaign`, the same
bounded 7/30/90-completed-day `time_range`, and additional `campaign_id` and
`campaign_name` fields. No daily `time_increment` is requested. Each returned
row must span the full requested period, match the account/currency, and have
a unique numeric campaign ID and a nonblank name of at most 1000 characters.
Names are presentation text, not identities or links to local plans. Different
campaigns may have identical names; IDs disambiguate them.

Responses use `scope: campaign`, `reported_campaigns`, aggregate totals and rows
of campaign ID/name, decimal-string spend, integer impressions and clicks (all).
The same exact arithmetic and numeric bounds apply. All pages must validate
before any report is returned. Three pages of at most 100 rows each cap the
report at 300 campaigns. If Meta indicates more pages, the entire request fails
and the owner can choose a shorter period; no truncated ranking or partial total
is presented. Missing/repeated cursors and duplicate IDs, even across pages,
fail. Fixed-host GET, header authentication, app-secret proof, timeouts and
redacted errors retain K156 behavior.

The performance panel switches explicitly between Account totals and Campaign
comparison. Changing scope clears prior data and invalidates an in-flight
response; loading remains a separate tap. Campaign results are searched by name
or ID, sorted by highest spend/impressions/clicks or name, and paged locally
20 at a time. Money sorting uses BigInt micro-units. Searches do not change the
full-report totals; matching count and row range are shown separately. A fresh
load resets search, sort and paging. Empty provider data and a local search with
no matches have distinct messages. No zero-activity campaigns are invented.

These reports do not associate Meta campaigns with local funnel plans, use
matching names as proof, attribute leads/revenue or authorize publishing. No
stored report, migration, credential/scope change, background synchronization,
ad activation, ad edit or external campaign creation is added. User-run
acceptance and Meta activation remain deferred. Provider totals can change
between separate loads; comparison is not an atomic account-wide snapshot or
billing reconciliation.

Mock tests cover full-period queries, duplicate names/IDs, bounded pagination,
malformed data, exact sums and sorting, common owner/tier/expiry/revocation and
concurrency checks on both endpoints, shared rate limits, setup gates, scope
switching, errors, empty/search states, fresh-load reset and responsive views.
They do not prove Meta app approval, live connection or actual reported spend.

After explicit production approval, deploy backend then frontend. K156 is a
compatible rollback; restore its frontend first, then backend if needed. No
schema, owner-document or report conversion is needed. Keep Meta activation
separate. The official Meta SDK field/level and account-insights references in
the K156 section also cover the campaign fields and `campaign` level used here.

## K158 · Google Ads connection and account selection

This milestone adds a separate Google Ads connection card in the Ads workspace.
It prepares OAuth sign-in and account selection. Google reporting, campaign
creation, budget edits, conversion uploads, background jobs and ad publishing are
not implemented by these routes. Google and Meta activation remain deferred.
Deployment leaves the connection disabled unless all setup values and the
explicit enable flag are present. No new paid infrastructure is required.

Apply `20260922233935_funnel_google_ads_connection.sql` before the backend, then
deploy the frontend. It adds two private RLS tables, one monotonic version
sequence and one service-only SECURITY INVOKER function with a fixed search path.
Browser roles and PUBLIC have no table, sequence or function grants. Every command
checks the authenticated owner and current `user_profiles.tier` in PostgreSQL.
Advisory owner locks and connection versions reject stale writes after a refresh,
selection, reconnect, disconnect or tier downgrade.

### Deferred platform setup

| Backend variable | Required value |
|---|---|
| `KORLIX_GOOGLE_ADS_ENABLED` | `true` only when separately ready to activate |
| `KORLIX_GOOGLE_ADS_CLIENT_ID` | Google Cloud web application OAuth client ID |
| `KORLIX_GOOGLE_ADS_CLIENT_SECRET` | Client secret, stored only in the backend environment |
| `KORLIX_GOOGLE_ADS_DEVELOPER_TOKEN` | Google Ads developer token with the required access/approval |
| `KORLIX_GOOGLE_ADS_TOKEN_KEY` | Independent 32 random bytes encoded as standard base64; do not reuse Meta's key |
| `KORLIX_GOOGLE_ADS_REDIRECT_URI` | `https://chee-chai-chee-backend.onrender.com/api/funnels/google-ads/callback` |
| `KORLIX_GOOGLE_ADS_API_VERSION` | Optional; defaults to `v25` |

Use a Web application OAuth client with the exact HTTPS redirect URI, enable the
Google Ads API, configure consent and the Ads scope, and meet applicable Google
Cloud project, developer-token, verification and production-access requirements.
An OAuth connection alone does not establish API approval. Test-account access
and production-account access can differ. No credentials or flags are configured
by this release. The public readiness route only checks configuration shape; it
cannot establish that Google has approved the project or token.

Google's Ads scope is `https://www.googleapis.com/auth/adwords`, which permits
viewing and managing Ads data. The UI states this breadth accurately; this release
uses only customer listing and fixed account-detail search queries. No profile,
email, contacts or other Google scope is requested. No Google token is sent to
Flutter, rendered in callback HTML, placed in URLs or written into application
logs by this implementation.

### Sign-in and account behavior

- The owner starts a ten-minute attempt. State and the original-window finish
  proof are stored only as SHA-256 hashes. The PKCE verifier is encrypted with
  AES-256-GCM and bound to purpose, owner and attempt. It is returned internally
  once when the callback consumes state, then removed from the attempt.
- Authorization uses S256 PKCE, offline access and explicit Google consent/account
  choice. The callback exchanges the code using the web client secret and PKCE
  verifier. It verifies the granted Ads scope, bearer token and expiry, and requires
  a refresh token. Only an encrypted, owner/attempt-bound refresh token is staged.
- The user taps Continue to Google directly so Safari has a user gesture for the
  new window. Finish Google connection requires the private proof from the
  original authenticated window. Reloading loses that proof; finish in the
  original window or start again. The callback never auto-connects an owner.
- Refresh tokens remain encrypted server-side. Access tokens are obtained only
  for an explicit account operation and are not persisted. Known refresh-token
  expiry and configuration changes require reconnect. Unknown refresh expiry is
  supported. `invalid_grant` or an Ads API 401 marks the matching connection for
  reconnect; a 403 reports access/platform restrictions without misclassifying a
  valid refresh token as revoked. No blind refresh or API retries occur.
- Refresh access accounts lists IDs directly accessible to that Google login.
  Choose one and load its active advertising accounts. A direct advertiser returns
  itself if enabled; a manager query includes all direct and indirect enabled
  non-manager clients. IDs, names, currency, timezone and test-account status are
  shown. Suspended/cancelled/closed advertisers are not selectable.
- The chosen manager context is stored separately as `login_customer_id` and
  passed as the `login-customer-id` header when validating a client selection.
  The browser can choose only cached account/root IDs; fresh direct-root access
  and target account access are rechecked before saving. A later failure cannot
  restore or change a newer connection.
- Refreshing access roots clears the loaded list and selection. Loading a different
  root clears selection; reloading the same root keeps it only if still available.
  Selecting a different root in the dropdown disables old-list selection until
  loading. Account data is explicitly a last-refresh snapshot.
- Up to 500 direct root IDs and 500 active advertisers for the chosen root are
  supported. Five search pages, a 2 MiB response bound and ten-second request
  deadlines prevent unbounded discovery. Exceeding a bound fails the whole load;
  the app does not present a partial list as complete. Users with larger manager
  hierarchies need a smaller directly accessible manager account.
- Fixed Google hosts, fixed GAQL queries, validated numeric customer IDs, redirect
  rejection and opaque page-token handling prevent arbitrary URL/query execution.
  Provider error messages are redacted. Google owner mutations share a limit of
  15 requests per owner per minute; public callbacks allow 30 per IP per minute.
- Current access denial clears UI state/proof immediately. Client replacement,
  disposal and late replies cannot restore another session's details. Disconnect
  requires confirmation and a current version, and deletes credentials, account
  cache and pending attempt. It does not revoke Google consent or stop ads already
  running in Google. The dialog explains removal through Google Account connections.

Local verification uses the migration in PGlite under the service role, HTTP owner
middleware, mocked Google protocol responses and Flutter widget tests. It covers
role denial/RLS, tier/owner checks, state/proof replay, PKCE binding, cancellation,
expiry, superseded attempts, concurrent disconnect/selection/downgrade, response
redaction, manager headers, paging/capacity, popup handling, mobile layout and late
UI responses. It makes no real Google request or owner account change.

Rollback: disable Google connections if activated later, deploy the K157 frontend
then backend, and preserve this additive schema and encrypted records. Do not drop
tables during an application rollback. Activation, live provider acceptance and
permission revocation require their own later operational work.

Primary references checked on 22 September 2026:
[Google Ads release notes](https://developers.google.com/google-ads/api/docs/release-notes),
[listing accessible accounts](https://developers.google.com/google-ads/api/docs/account-management/listing-accounts),
[customer_client including indirect clients](https://developers.google.com/google-ads/api/fields/v25/customer_client),
[REST authorization headers](https://developers.google.com/google-ads/api/rest/auth),
[web-server OAuth and offline access](https://developers.google.com/identity/protocols/oauth2/web-server),
[Google PKCE](https://developers.google.com/identity/protocols/oauth2/native-app),
and [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).
The current Supabase changelog was also checked; no listed breaking change affects
these additive tables or service-only RPC. Mocked checks do not establish live
Google compatibility or platform approval.

## K159 — Google Ads account performance

Adds on-demand account totals and daily spend, impressions and clicks to the
existing Google Ads connection card. Choose 7, 30 or 90 completed calendar days;
the backend derives the interval using fresh account timezone metadata, ending
yesterday in that timezone. Currency is shown explicitly, with cost micros
converted and summed using exact integer arithmetic. No conversion estimates,
funnel attribution, revenue, ROAS or billing reconciliation are inferred.

`GET /api/funnels/google-ads/performance` accepts only `days` (`7`, `30`, `90`),
`version`, `root_id` and `account_id`. The IDs must match the current owner's
selected advertising account and loaded access root before refreshing a token.
Current Enterprise entitlement, configuration, refresh expiry and version are
checked first. Fresh accessible roots and active non-manager account details are
checked before a fixed customer-level GAQL report is requested with the saved
`login-customer-id` context. Entitlement and connection identity are checked again
before returning data, so disconnect, reselection, root refresh and downgrade
prevent an in-flight result from being released. Requests have a separate limit
of ten per owner per minute and inherit owner response `no-store` behavior.

The response includes `source: google_ads`, `scope: account`, connection/root
identity, fresh account metadata, the date range, retrieval time, totals, returned
row count and descending daily rows. Each returned row must match the requested
customer, currency, timezone and a unique date within the interval. Requested
scalar metrics omitted by ProtoJSON are interpreted as zero; explicit null,
negative, non-integer, unsafe or malformed values reject the report. Spend is
bounded to 10^18 micros and counts to JavaScript's maximum safe integer, including
summed totals. At most three pages and one daily row per requested day are
accepted. Missing/invalid/repeated cursors, excess rows/pages and inconsistent
metadata reject the whole load. The existing fixed host, redirect rejection,
ten-second deadline and 2 MiB response bound apply to each request. No automatic
retry is added.

Google can omit dates with no activity. The UI does not fill missing dates or
interpret an empty response as a verified zero total. Nonempty reports show the
sum of returned rows, and the daily section exposes exactly those rows. Google
may revise reporting. The frontend validates identity, date bounds, ordering,
metric types and exact row-to-total reconciliation before displaying a report.
Changing the period, selected root/account/version, connection availability or
client clears old data and invalidates pending results. Access denial clears data
and disables loading. Reports load only when requested and are not persisted.

There is no schema migration, new environment variable, OAuth scope, background
sync, conversion upload or ad mutation. K158's private service-only connection
schema and encrypted refresh credentials are reused. Google and Meta activation
remain deferred. The Ads scope still grants Google view/manage permission; this
implementation uses it only for account discovery and reporting.

Local checks cover the real owner middleware and migration-backed connection
store with mocked Google reports; fixed REST headers/GAQL; exact arithmetic;
account-calendar/DST/leap dates; malformed, mismatched and oversized reports;
concurrent access changes; rate limits; UI validation and stale-result handling;
and 1400, 390 and 320 px layouts (320 px at 1.3 text scale). No real Google account
or report was requested. These checks do not establish live provider acceptance.

Rollback: restore K158 frontend then backend and retain the K158 connection
schema/records. K159 writes no report data and requires no database rollback.

Primary references checked on 23 September 2026:
[Google Ads reporting](https://developers.google.com/google-ads/api/docs/reporting/overview),
[customer metrics and date fields](https://developers.google.com/google-ads/api/fields/v25/customer),
[date ranges](https://developers.google.com/google-ads/api/docs/query/date-ranges),
[zero metrics and omitted dates](https://developers.google.com/google-ads/api/docs/reporting/zero-metrics),
[paging](https://developers.google.com/google-ads/api/docs/reporting/paging), and
[ProtoJSON scalar representations](https://protobuf.dev/programming-guides/json/#representation).
