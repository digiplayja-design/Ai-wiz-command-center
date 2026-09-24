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

## K160 — Google Ads campaign comparison

Adds a campaign comparison option beside the existing Google account totals.
Owners explicitly load a 7-, 30- or 90-completed-day report for the currently
selected advertising account. The period uses fresh account timezone metadata.
Each returned campaign has its ID, name, current status, advertising channel,
exact spend in account currency, impressions and clicks. Names/statuses reflect
retrieval time, not historical status within the reporting period. Enabled,
paused and removed campaign rows are accepted when returned; no status filter is
applied. Google's default excludes draft entities.

`GET /api/funnels/google-ads/campaign-performance` accepts the same four inputs
as the account endpoint: `days`, `version`, `root_id` and `account_id`. The route
selects campaign scope internally; callers cannot supply arbitrary scope, fields,
queries or page tokens. Both report endpoints share the existing ten-request
owner/minute reporting limit. The same authentication, current Enterprise,
connection-version, selected-account, root-access, active-account and post-fetch
entitlement/identity checks apply. Removed manager access or a concurrent
connection/entitlement change prevents returning the report.

The fixed GAQL query requests campaign-level totals over the entire interval,
without selecting a date/device segment. Explicit campaign resource names must
match both customer ID and campaign ID. Customer currency/timezone must match the
fresh metadata. Campaign IDs remain decimal strings and are checked against
positive signed INT64 bounds; names, statuses and channels are validated. Duplicate
campaign IDs, unexpected segmentation, malformed metrics or overflow reject the
whole response. K159's exact BigInt metric handling and totals are reused.

Campaign reports support at most 500 rows across five provider pages. The query
uses LIMIT 501 so excess rows are detected instead of silently truncating to 500.
Excess rows/pages, invalid or repeated cursors and incomplete provider data fail
the entire load. Fixed Google hosts, redirect rejection, ten-second per-request
deadlines, 2 MiB response bounds, credential redaction and version-guarded revoked
access handling remain in force. No retries or report persistence are introduced.
The existing daily account report retains its original 90-row/three-page bounds.

The response identifies `scope: campaign`, provides `reported_campaigns` and
campaign rows, and carries account/root/connection identity, interval, retrieval
time and totals. Flutter validates these bindings and reconciles all three
metrics against the rows before rendering. Empty results show no totals, while
returned zero metrics display zero. Results may omit campaigns with no returned
data and are not an inventory guarantee or a billing statement. Independently
retrieved account totals may differ. No funnel attribution, revenue or ROAS is
inferred.

The local campaign list searches names/IDs, sorts by spend, impressions, clicks
or name, and displays 20 rows per page. Spend sorting is exact to one micro-unit;
ties use campaign IDs. Search, sorting and pagination make no provider request and
do not change totals for the full returned report. Reloading clears old figures,
filters and pagination. Changing report scope, period, account/root/version,
connection availability or client invalidates pending results. Global access loss
also clears the current report. Manual campaign reports remain separate.

No schema migration, environment variable, credential, permission scope,
background sync, ad creation, budget change or provider activation is required.
K158's already-applied private connection schema is unchanged. Rollback is K159
frontend then backend, preserving all schema and owner records.

Verification includes migration-backed owner/entitlement and connection-race
checks, mocked fixed REST requests, exact totals, large campaign IDs, 500-row and
five-page bounds, response corruption, shared rate limits, scope/period races,
search/sort/pagination, stale UI responses and 1400/390/320 px screenshots (320 px
with 1.3 text scale). No real provider report or owner acceptance is performed.

Primary references checked on 23 September 2026:
[campaign fields and attributed customer resource](https://developers.google.com/google-ads/api/fields/v25/campaign),
[GAQL structure, core-date filters and draft defaults](https://developers.google.com/google-ads/api/docs/query/structure),
[reporting example](https://developers.google.com/google-ads/api/docs/reporting/example),
[campaign status](https://developers.google.com/google-ads/api/reference/rpc/v25/CampaignStatusEnum.CampaignStatus),
[advertising channels](https://developers.google.com/google-ads/api/reference/rpc/v25/AdvertisingChannelTypeEnum.AdvertisingChannelType), and
[zero metrics](https://developers.google.com/google-ads/api/docs/reporting/zero-metrics).

## K161 — Facebook Page identity for Meta setup

Owners can explicitly refresh Facebook Pages, select a Page, or clear that
selection after choosing a Meta ad account. Page identity is stored for that
owner's current account setup. This does not create an ad, grant ad permissions,
verify that the Page can advertise through the account, or change
`ad_publishing_ready: false`. Actual provider activation and owner acceptance
remain deferred.

Endpoints: `POST /api/funnels/meta/pages`, `/select-page`, `/clear-page`.
Requests accept only the current integer `version` and `account_id`, with
`page_id` required for selection. Discovery and selection share ten requests per
owner per minute. All routes require authentication and current database
Enterprise entitlement. Writes recheck connection version, account, configuration,
credential expiry, and entitlement after remote work. Stale results are rejected.

The provider checks `pages_show_list` on `/me/permissions`, then reads
`/me/accounts` with explicit `id,name,category` fields. It never requests, stores,
or returns Page access tokens. Each selection discovers the currently shared
Pages again; a public Page lookup cannot establish membership. Graph hosts and
paths are fixed, credentials use the existing bearer header/app-secret proof,
redirects are rejected, and pagination follows only validated cursors. Reads are
bounded to one permission response plus five Page responses, 100 rows per Page
response, 500 unique Pages, 1 MiB per response and ten seconds per request.
Incomplete lists, repeated IDs/cursors and malformed metadata fail without
saving a partial snapshot.

A missing Page grant or Graph permission error clears cached Pages and the Page
selection while preserving the ad account, encrypted user token and account
reporting access. Expired/revoked user access uses the existing reconnect path
and also clears Page state. Account reselection, disappearance during account
refresh, successful reconnection, disconnect and deauthorization clear Page state.
A normal account refresh that retains the selected account preserves its Page
snapshot and permission-needed flag. A withdrawn Page disappears on the next
Page refresh/reselection. Cached details are a timestamped snapshot, not a
continuing permission guarantee.

Frontend controls include local name/ID/category search, 20 Pages per list page,
last-checked time and selection/clear actions. Search and pagination make no
provider requests. A new connection version resets the Page list controls.
Changing clients or losing application access clears owner data and invalidates
late results. Unreadable Page state is rejected, and conflict/permission failures
reload the safe connection state. Desktop, 390 px and 320 px layouts (the latter
at 1.3 text scale) are covered by widget checks and screenshots.

Apply `20260923011934_funnel_meta_page_identity.sql` before deploying the backend.
It adds four nonsecret columns to the existing private Meta connection table and
replaces the existing service-only `SECURITY INVOKER` RPC. Existing RLS, browser
revocations, encrypted credentials and monotonically increasing versions remain.
No new table, dependency, environment variable or provider permission is activated
by this release. The Meta Business Login configuration will need approved
`pages_show_list` and appropriate Page sharing when activation is undertaken;
existing `ads_read` reporting remains usable without that grant. Additional
provider requirements must be verified during live activation. Page selection
alone is not ad-account/Page compatibility or publishing approval.

Local tests execute the historical and additive migration on PGlite with real
PostgreSQL grants, constraints and RPC behavior. They also cover fixed mocked
Graph requests, input/permission failures, account/expiry/tier races, response
bounds and the real owner middleware's shared rate limit. No real Meta user,
Page, ad account or paid-ad request is made. Roll back frontend then backend to
K160 and retain the additive schema and encrypted owner data; do not drop columns
or reverse the migration during ordinary rollback.

Primary references checked on 23 September 2026:
[User accounts edge](https://developers.facebook.com/docs/graph-api/reference/user/accounts/),
[Pages API setup](https://developers.facebook.com/docs/pages-api/getting-started/),
[official Meta User SDK](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/user.py),
[official Meta Page SDK fields](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/page.py),
and [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).

## K162: campaign-level Meta setup review

Each Meta campaign plan can open a private setup review that brings together its
copy, audience brief, planned USD budget, current published landing page and
selected cached Meta ad account/Facebook Page. Eight server-calculated checks
cover publication, plan review, platform configuration, current connection,
selected/active account, USD currency and selected Page. This is a saved planning
review: `ad_publishing_ready` remains false. No creative, executable targeting,
ad eligibility, ad creation, platform budget or spending authorization is implied.

- `GET /api/funnels/:id/campaigns/:campaign_id/meta-setup` reads current checks,
  snapshot and fingerprint, plus the last reviewed snapshot if one exists.
- `POST .../meta-setup/review` accepts exactly `version`, `fingerprint` and
  `confirmed: true`; all checks must still pass and the fingerprint must match.
- `POST .../meta-setup/clear` accepts exactly `version` and `confirmed: true`.
  It clears only the saved review, retaining its increasing version.

The owner and current Enterprise tier are verified for every operation. The
server builds the tagged HTTPS destination and configuration binding, ignoring
no caller-controlled extra fields. All three routes share 30 requests per owner
per minute, use no-store responses and make no Meta API calls. Saved snapshots
contain only campaign/page copy and nonsecret account/Page details. Copying a
saved review labels it OUT OF DATE when current content or identity differs.

A SHA-256 fingerprint binds the snapshot to full published page content, plan and
page state, reviewed page version, Meta connection identity and configuration.
Copy edits, publication, account/Page changes, reconnects and configuration changes
invalidate a saved review; expiry/access checks also prevent it being current.
Manual report entries and unpublished draft edits do not invalidate the review.
The existing campaign planner is USD, so a non-USD Meta account blocks review;
there is no currency conversion. Cached details must be refreshed in the Meta
connection card when the owner needs updated provider information.

Apply `20260923015323_funnel_meta_campaign_preparation.sql` before the backend.
It creates one RLS-protected private table with service-role-only CRUD and a
service-role-only SECURITY INVOKER RPC with a fixed search path. No existing RPC,
provider permission, environment variable or dependency is changed. Local tests
exercise actual PostgreSQL constraints/grants, ownership and tier boundaries,
concurrent saves, stale fingerprints, preserved reporting/drafts and cascade
cleanup. Widget tests cover the complete review/copy/clear flow, bad responses,
conflict recovery, access loss and workspace changes with an open dialog, plus
1400/390/320 px layouts and 1.3 text scaling at 320 px. Live owner/provider
acceptance remains deferred. Roll back frontend then backend to K161 and retain
the additive private table and RPC; do not delete saved owner reviews.

## K163: Google campaign setup review

Google campaign cards now offer a private setup review using the same frontend
review flow as Meta. The owner sees planned copy, audience brief, USD daily/total
budget, published landing page and tagged destination, selected Google advertising
account, access root and direct/manager login context. Nine checks cover published
page, reviewed plan, configuration, current refresh-token connection, matching
access context, selected/active advertising account, USD currency and production
account. A test account or manager account cannot pass this review.

`GET /api/funnels/:id/campaigns/:campaign_id/google-setup` reads the current
snapshot/checks/fingerprint and optional saved review. `POST .../review` accepts
exactly `version`, `fingerprint` and `confirmed: true`; `POST .../clear` accepts
exactly `version` and `confirmed: true`. Every operation verifies owner/current
Enterprise tier, rejects extra input/query fields, uses no-store and shares a
30-request-per-owner-per-minute limit. Destinations and configuration bindings
come from the server. None of these routes calls Google or refreshes OAuth.

The selected account must be cached under the chosen access root. A manager
login must match that root; direct access must match the advertising account.
The cached root must remain in the connection's roots. Unknown test-account
identity fails closed. Account currency must be USD; no conversion is attempted.
Connection access with no specified refresh-token expiry is permitted, while
expired, reconnect-required and configuration-mismatched connections block review.
Provider permissions are not rechecked by this local review; refresh accounts
through the existing Google connection controls when fresh provider data is needed.

Saved snapshots contain only campaign/page copy and nonsecret Google identity.
Changes to published content, plan state/copy, account, access root, manager
context, connection or configuration invalidate the review. Manual reporting and
unpublished draft edits do not. Version/fingerprint conflicts reload safe state
and require renewed confirmation. Saved briefs can be copied with an OUT OF DATE
label when stale; clearing only removes the saved review. Client/funnel changes
and access denial clear both provider dialogs and suppress late responses.

Apply `20260923073916_funnel_google_campaign_preparation.sql` before the backend.
It adds a private RLS table and a service-only SECURITY INVOKER RPC with a fixed
search path, browser/PUBLIC access revoked, versioned saves and campaign cascade
delete. Existing Google credentials/RPC and Meta setup data/RPC are unchanged.
No provider permission or environment setting is activated, and no new package
is introduced. The frontend lockfile records the Flutter 3.47 SDK-compatible
transitive versions of matcher, meta, test_api and vector_math. Local PGlite and widget tests cover account contexts, currency/test-account restrictions,
ownership, concurrency, stale data, malformed replies and responsive layouts.

This is a planning review, not a Google ad-format, keyword, targeting, eligibility,
creative, launch or spending approval. `ad_publishing_ready` stays false. Live
owner/provider tests and external activation remain deferred. Ordinary rollback
is frontend then backend to K162; retain the additive table/RPC and owner reviews.

### K164 Google search-ad text drafts

Google campaign cards offer a private responsive-search text draft with up to 15
headlines, 4 descriptions and two optional display paths. At least 3 headlines
and 2 descriptions makes the text counts complete; incomplete drafts can be
saved. Duplicate text within each asset group, control characters, dynamic braces
and invalid paths are rejected. Paths are labels only: the server keeps the
campaign's tagged landing-page destination. No destination override is accepted.

Draft length is deliberately conservative: ASCII code points count as one and
all other code points count as two, including accents. Limits are 30/90/15 for
headlines/descriptions/paths. This covers double-width text without claiming
Google's exact counting algorithm or policy approval. The interface explains
this limitation. See [Google responsive search ads](https://support.google.com/google-ads/answer/7684791?hl=en)
and [Google Ads API overview](https://developers.google.com/google-ads/api/docs/responsive-search-ads/overview).

`GET /api/funnels/:id/campaigns/:campaign_id/google-creative` reads the draft;
`POST .../google-creative/save` accepts exactly `version`, `fingerprint`, `assets`.
Assets contain exactly `headlines`, `descriptions`, `path1`, `path2`. Both routes
are no-store, share 30 requests per owner/minute, and verify current DB Enterprise
and ownership in the service-only SECURITY INVOKER RPC. New table
`korlix_funnel_google_creatives` has RLS and no browser grants/policies. Validation
also runs inside PostgreSQL and a table constraint. Version conflicts are 409.

The context fingerprint binds plan copy/state/budget and published page content,
state and destination; unpublished edits and manual reporting do not stale it.
Copy exports saved text/context and flags stale or incomplete drafts. Saving
refreshes the draft context but is not owner creative approval. Setup reviews
remain separate account/plan reviews; editing this draft does not claim to review
creative or invalidate those account snapshots. Archived plans retain read/copy
but block edits. Owner/client/funnel changes invalidate an open dialog and late
responses. Conflict recovery preserves typed text until explicit discard/reload.

No Google credentials or live provider calls are needed. No keywords, executable
targeting, pinning, ad approval, ad creation, launch or spending is implemented.
`ad_publishing_ready` remains false. No new packages or environment variables.

### K165 owner copy reviews

The search-ad draft editor now records an explicit **owner copy review**. This is
separate from Google policy approval, campaign/account setup review, activation
or spending. No provider operation is involved; `ad_publishing_ready` stays false.

POST `.../google-creative/review` accepts exactly `version`,
`review_fingerprint`, `confirmed: true`. POST `.../google-creative/clear-review`
accepts exactly `version`, `confirmed: true`. All four creative routes share the
existing 30/owner/minute limit, no-store responses and current DB Enterprise and
ownership checks. Clear retains assets and is allowed for an archived campaign.

The additive migration initializes `draft_revision` from existing row versions,
without changing saved assets/context/timestamps/versions. Every subsequent draft
save increments that revision, including an identical save. Reviews/clears only
increment the entity version. Review requires a saved complete draft, current
context, a published page and a plan reviewed against that page version. A hash
binds the exact assets, current context fingerprint and draft revision. Both
entity version and displayed hash are checked under the existing lock order.

One saved review snapshot (assets, context, draft revision, timestamp) is retained
until replaced or cleared. Later saves and published context changes mark it out
of date; manual reports and unpublished page edits preserve it. A repeated save
cannot silently revalidate an old review, even if text is identical. UI copy of a
review uses that immutable snapshot and labels stale records. Unsaved changes,
conflicts and owner/access loss disable review actions; typing resets confirmation.

This release does not introduce an approval history ledger or automated launch.
Rollback leaves the additive columns and updated RPC in place so older save
clients continue to advance revisions correctly. Roll back the frontend first.

## K166: Google search keyword drafts

GET `/:id/campaigns/:campaign_id/google-keywords` reads a private keyword draft.
POST `.../google-keywords/save` accepts exactly `version`, `fingerprint`, `assets`.
Assets contain six arrays: `exact`, `phrase`, `broad`, `negative_exact`,
`negative_phrase`, `negative_broad`. These are preparation lists, not Google
account resources. No provider API, targeting deployment, ad or spend is created.

KORLIX draft limits are 50 positive plus 50 negative keywords, 80 Unicode code
points and 10 space-separated words per term. Text is trimmed with single spaces;
the editor normalizes pasted whitespace. API and SQL validate the limits and reject
duplicates within each match type, control characters, brackets, quotes and
keyword operators. Different match types can share text. The editor highlights
identical text across positive/negative lists; this is not exhaustive overlap
detection or Google policy validation. Empty drafts may be saved.

Both routes share 30 requests per owner/minute and no-store. Current database
Enterprise and ownership checks protect reads and writes. Private table
`korlix_funnel_google_keywords` uses RLS with no browser policy/grants; validator
and RPC are service-only SECURITY INVOKER with fixed search_path. Lock order is
funnel → campaign → keyword row; version and campaign-context hashes prevent
lost updates. Parent deletion cascades. Archived drafts remain readable/copyable.

Each save records assets, context and a new version. Campaign/published-page
changes flag the saved draft as outdated; unsaved page edits and manual reports
preserve it. Copy uses the saved snapshot with CURRENT/OUT OF DATE and incomplete
labels. Unsaved edits/conflicts disable copy, and explicit discard is required
for reload/close. Owner/client/funnel/overlay changes invalidate private state and
late responses. Missing campaigns leave Close available; malformed responses fail
closed. Keyword edits preserve existing setup and saved-copy review records.

Locations, languages, bidding, final targeting review and launch remain separate.
No dependency/environment changes. Rollback leaves the additive table/RPC in
place; older clients ignore it. Existing creative and setup RPCs are unchanged.

Match semantics verified 2026-09-23 against Google primary sources:
[positive matches](https://support.google.com/google-ads/answer/7478529?hl=en),
[negative matches](https://support.google.com/google-ads/answer/2453972?hl=en).


### K167 — saved Google keyword review

The keyword editor records an explicit owner review of its saved positive and
negative lists, match types and overlap warnings against the published page.
POST `google-keywords/review` accepts exactly `{version, review_fingerprint,
confirmed:true}`; POST `google-keywords/clear-review` accepts exactly
`{version, confirmed:true}`. Both share the existing owner rate limit, current
Enterprise/ownership checks and no-store behavior.

Review requires a saved positive keyword, current context, a published page and
current campaign-plan review. An immutable record preserves all six lists, saved
context, draft revision and original save timestamp. Every draft save increments
the draft revision and stales the previous review, even for identical keywords.
Review/clear change only entity version and review metadata; saved time and assets
are preserved. Campaign/published changes stale review, while manual reports and
unpublished edits preserve it. Clearing is confirmed and allowed after archive.

The additive migration backfills existing draft revisions without changing prior
assets, versions, save times, setup reviews or copy reviews. Snapshot size permits
maximum Unicode keyword lists and bounded context. RPC remains service-only,
SECURITY INVOKER with fixed search_path; table keeps RLS and no browser grants.

UI review and export require saved, conflict-free data; editing/reloading resets
confirmation. Export uses the exact reviewed revision, counts and save timestamp,
including when stale. Invalid metadata fails closed and existing scope/access
invalidation protects late responses. No provider call, Google approval, targeting
activation, ad creation or spending authorization occurs. Rollback can retain the
additive migration; K166 clients ignore review metadata.


### K168 — Google targeting drafts

Google campaign cards expose **Targeting draft**. GET
`/:id/campaigns/:campaign_id/google-targeting` reads the draft and pinned reference
catalog; POST `.../google-targeting/save` accepts exactly `version`, `fingerprint`,
and `assets`. Assets contain `countries`, `excluded_countries`,
`content_languages`, `location_mode` and `bidding`. Empty drafts are saveable;
empty targets never imply worldwide targeting. The draft is complete only with
a target country, content language, explicit reach and bidding choice.

Preparation limits are 20 unique target countries, 20 unique excluded countries
and 10 unique content languages. Included/excluded country codes cannot overlap.
All codes must exist in the pinned catalog. Reach is undecided, presence, or
presence-or-interest; bidding is undecided, maximize clicks, or maximize
conversions. These are preferences; bids, local areas, conversion goals and
provider eligibility require final setup. No preference is preselected.

The 219 country entries exactly match Active Country rows in Google's
[August 12, 2026 geo reference](https://developers.google.com/google-ads/api/data/geotargets).
The source ZIP SHA-256 and URL are retained in `google_targeting_catalog.json`.
The 51 content language entries come from Google's
[codes reference](https://developers.google.com/google-ads/api/data/codes-formats#languages).
Language selections document planned ad/page content, not executable Search
audience constraints: Google has announced removal of the Search campaign
language setting starting September 2026
([language targeting](https://support.google.com/google-ads/answer/1722078?hl=en)).
Reach and bidding text follow Google's
[location guidance](https://developers.google.com/google-ads/api/docs/targeting/location-targeting)
and [bidding overview](https://developers.google.com/google-ads/api/docs/campaigns/bidding/overview).
Catalog inclusion never claims that a country/account is currently eligible.

The additive migration creates a private RLS-enabled, service-only table and
three SECURITY INVOKER functions with fixed search paths. Each request checks
current database Enterprise entitlement and funnel ownership. Reads/saves share
a 30-request owner/minute limit and no-store. Funnel → campaign → draft locks
and version/context fingerprints protect concurrent saves. Published content,
reviewed-page version, campaign context and catalog version bind the draft.
Reports and unpublished page edits do not invalidate it; targeting saves preserve
setup, copy and keyword reviews. Archive allows read/export but blocks saves.

Saved labels and campaign context are snapshotted so stale exports remain
faithful. Unsaved changes and conflicts disable export. Reload/close confirms
discarding edits. Client/funnel/owner changes erase private state and discard
late reads, saves and picker selections. Malformed server metadata fails closed.
A catalog version change requires a coordinated client/SQL/catalog update.

No provider call, ad creation, launch readiness or spending authorization is
performed; `ad_publishing_ready` remains false. K169 adds owner targeting review
below. Unified launch review, local-area targeting and Meta creative preparation
remain later work. Rollback the frontend before the backend; retain the additive table and
owner drafts.

### K169 — Saved Google targeting review

POST `.../google-targeting/review` accepts exactly `version`,
`review_fingerprint`, and Boolean `confirmed: true`. The owner must have saved
complete targeting choices against the current campaign and published page, with
the campaign plan reviewed for that page. The fingerprint binds assets, saved
labels, catalog version, current page/campaign context and draft revision. The
server snapshots those exact assets, context, labels, catalog version, revision
and original save time; clients cannot supply a review snapshot.

POST `.../google-targeting/clear-review` accepts `version` and Boolean
`confirmed: true`. Clearing preserves the saved draft and timestamp and is
available for archived campaigns. Both actions increment the concurrency version
without incrementing the draft revision. Every draft save increments its revision
and makes any prior review stale, even when choices are identical. A stale review
remains available for inspection/export until explicitly replaced or cleared.
Reports and unpublished page edits preserve current reviews; published context
changes invalidate them. Other setup/copy/keyword reviews remain unchanged.

The additive migration backfills existing draft revisions from their versions,
preserving original columns. It replaces only the targeting RPC, retaining
service-only execution, SECURITY INVOKER, a fixed search path, and funnel →
campaign → targeting lock order. Reads, saves, reviews and clears share the
30-request owner/minute limit, live Enterprise/ownership checks and no-store.

The screen requires explicit confirmation, resets it on editing/reloading, and
blocks review/export/clear while dirty or conflicted. Review exports use the
exact saved snapshot, including labels, catalog version and save time. Malformed
review metadata fails closed; access/scope invalidation discards late responses.
No provider call, ad creation, Google approval, launch readiness or spending
occurs. Roll back the frontend first, then backend; retain the additive columns
and saved records. K168 clients ignore the additional review response fields.

### K170 — Combined Google preparation checklist

GET `/:id/campaigns/:campaign_id/google-preflight` returns the published-page,
plan, account-setup, copy, keyword and targeting review checks together. It rejects
query parameters, requires current Enterprise ownership, uses no-store and has a
30-request owner/minute limit. No POST endpoint or combined approval is added.

The additive `korlix_funnel_google_preflight_v1` RPC invokes the four existing
component readers in one transaction under their funnel → campaign → connection
lock order. It never modifies saved rows, calls a provider or changes a review.
Execution stays service-only, SECURITY INVOKER, with a fixed search path. The
existing readers, tables, grants and constraints are unchanged. `checked_at`
identifies this point-in-time view. `preparation_complete` requires all six
checks; `ad_publishing_ready` is always false, including when every review is
current. Cached account identity is explicitly distinguished from live provider
eligibility.

Google campaign cards expose **Preparation checklist**. Each review shows its
current/missing/out-of-date status and relevant incomplete prerequisites, and
opens the existing review editor. Closing a child editor refreshes the combined
checklist. Owners can inspect/copy a timestamped preparation summary with the
current plan, cached selected account, saved copy, keywords, targeting labels,
original draft timestamps and review status. This summary describes the latest
saved drafts at check time; old reviewed snapshots remain in their individual
editors and are not substituted into the latest draft section.

Component validators and cross-component context/check comparisons reject
malformed or mismatched responses. Refresh clears the previous summary while
loading; failure cannot leave stale data copyable. Owner/scope/client changes
invalidate data and pending responses, including open child dialogs. No ad,
platform budget, spending approval or launch is created. Roll back frontend then
backend and retain the additive read-only RPC.

### K171 — Private Meta single-image creative draft

GET `/:id/campaigns/:campaign_id/meta-creative` and POST `.../save` prepare a
single-image draft without invoking Meta. Both require current Enterprise
ownership, no query parameters, no-store responses and a shared 30-request
owner/minute limit. Save accepts exactly `version`, the current setup
`fingerprint`, and `assets` (`primary_text`, `headline`, `description`, `cta`,
`image_id`, `image_alt`). Text limits are KORLIX preparation limits: 1,000 / 100 /
200 / 180 Unicode code points, plain single-line text. These do not represent
universal Meta placement limits. Button preferences are LEARN_MORE, CONTACT_US,
SIGN_UP, SHOP_NOW and GET_QUOTE; eligibility remains a later provider check.

The service-only SECURITY INVOKER RPC reuses the Meta setup reader's entitlement,
owner, campaign/platform checks and funnel → campaign → connection → setup locks,
then locks the private creative row. It reads cached identities only. Campaign,
published-page and identity changes invalidate the context; old snapshots remain
available for comparison/export. Incomplete drafts are allowed, versions prevent
lost updates, and archived campaigns are read-only. Completion requires primary
text, headline, an image and image description; ad_publishing_ready stays false.

The RLS-enabled private table references immutable owner images. Image selection
checks ownership under FOR KEY SHARE; an indexed deferred NO ACTION foreign key
protects references while allowing auth-user/funnel cascades. The existing image
RPC now includes `creative_count` in the owner library and rejects deletion while
a Meta draft uses an image. Existing page references and public image access are
unchanged: a creative reference never grants public delivery. The deferred key
also protects direct service writes at transaction commit. No bytes are copied
into drafts. Existing WebP previews are preparation assets, not Meta upload IDs.

Meta campaign cards open a responsive text/image editor with private upload and
selection, button preference, illustrative preview, current destination, saved
context and saved-only clipboard export. Client validation rejects mismatched
identity, destination, assets, image metadata and completion flags. Dirty edits
require confirmation before discard; conflicts require reload. Owner/client/scope
changes and denied access clear private content and invalidate pending loads,
saves, image selection and file pickers. Referenced-image deletion is disabled in
the shared library. No ad publishing, budget changes, spend, provider calls or
outbound messages are introduced.

Primary references checked 2026-09-23: Meta's official business SDK
`facebook_business/adobjects/adcreativelinkdata.py` (message/name/description/link/
image fields) and `adcreative.py` (CallToActionType), Supabase functions guidance
and changelog, PostgreSQL foreign-key documentation. This chapter implements
preparation only, not SDK payload generation. Roll back the frontend then backend;
retain the additive table/RPC and image-reference protection to preserve drafts.

### K172 — Meta targeting, placement and combined preparation review

GET `/:id/campaigns/:campaign_id/meta-targeting`, POST `.../save`, `.../review`
and `.../clear-review` provide private preparation. All use current Enterprise
ownership, no query parameters, no-store and a shared 30 owner requests/minute.
Save accepts exactly version, fingerprint and assets; review requires the exact
version/review_fingerprint and confirmed:true. Clear requires version and a
Boolean confirmation. Actor, account/Page context and destination are server
controlled; no Meta endpoint is called.

Assets hold up to 20 unique country codes, integer age_min/age_max (18 through
65+, minimum <= maximum), placements (undecided / automatic / facebook_feed),
and categories. Categories are UNDECIDED alone, NONE alone, or up to five unique
special categories: HOUSING, EMPLOYMENT, FINANCIAL_PRODUCTS_SERVICES,
ISSUES_ELECTIONS_POLITICS and ONLINE_GAMBLING_AND_GAMING. KORLIX keeps undecided
and special-category drafts at its broad 18–65+ planning range; this is not a
claim that the range satisfies any country/category's live eligibility. All
genders are implicit. Country names/codes are a 249-entry ISO planning snapshot
from pycountry, with source hash and version recorded in the JSON/SQL catalog.
They are not a Meta availability list. No cities, radii, exclusions, interest IDs,
audience expansion settings, optimization objective or final payload are inferred.

The additive RLS-enabled service-only table stores draft assets, labels, setup
context, revision, version and an optional combined review snapshot. SECURITY
INVOKER RPCs have fixed search paths and no browser/public execute. Targeting
invokes the existing Meta creative reader, preserving funnel → campaign →
connection → setup → creative → targeting lock order. The draft fingerprint binds
the setup and catalog; the review hash additionally binds the targeting revision
and exact saved creative version, text, immutable-image metadata and context.

Review needs complete/current creative and targeting, a published page and a
reviewed campaign plan. It can be recorded before provider activation; it does
not certify a selected account/Page, provider availability, policy approval or
launch. ad_publishing_ready always remains false. Reviews do not mutate creative,
setup, campaign or connection rows. Changed/resaved drafts invalidate the review,
while the historical snapshot remains exportable and clearly marked out of date.
Review/clear increments the concurrency version only; saved timestamps and draft
revision remain intact. Archived drafts are readable/exportable and reviews can
be cleared, but no new save/review is allowed.

Historical reviewed image metadata is an audit snapshot, not an active image
reference. After the active creative removes an image, the existing image library
can delete it; historical review exports retain its label/hash/ID without fetching
old bytes. K171 active-draft image deletion protection remains unchanged.

The Meta campaign action opens a responsive country picker, category controls,
age and placement preferences, saved-targeting export, current saved creative
preview, and one combined owner preparation review. Opening the creative editor
from this dialog refreshes preparation on return. Dirty edits block review/export,
conflicts require reload, and owner/client/scope changes or denied access clear
private content and late responses, including open child editors. Historical
review exports use their original creative, not the current replacement draft.

Current primary references checked 2026-09-23: Meta official business SDK
Targeting, TargetingGeoLocation and Campaign.SpecialAdCategories definitions;
pycountry iso3166-1 database; Supabase functions docs and unchanged changelog.
Some Meta documentation URLs returned HTTP 429; no live provider capability or
complete policy validation is asserted. No dependencies, environment variables,
credentials, provider calls, ads, budgets, spending or outbound messages are added.
Roll back frontend then backend and retain the private additive schema and data.

### K174 — Google radius targeting drafts

The existing Google targeting routes accept an optional `proximities` array.
Legacy country drafts retain their exact five-field shape. Radius mode requires
an empty `countries` array and permits up to 10 distinct areas; a complete draft
needs at least one area. Each area contains exactly `label`, `latitude_micro`,
`longitude_micro` and `radius_meters`. Coordinates are integers within geographic
bounds; distances are integer meters from 1,000 through 200,000. Labels have
1–80 Unicode code points and exclude controls, angle brackets and surrounding
ASCII spaces. Duplicate coordinate/distance triples are rejected. These limits
are KORLIX planning choices, not a claim of provider eligibility.

The additive migration replaces the private targeting validator and RPC without
rewriting existing drafts or reviews. `radius_supported:true` enables the new
editor only after the backend capability is present. Existing fingerprints,
optimistic concurrency, owner checks, lock order, service-only permissions and
historical review behavior are preserved. Radius changes invalidate the saved
review, and combined preparation remains bound to the exact saved assets.

The editor accepts an owner label, latitude/longitude with at most six decimal
places and a kilometer distance with at most three. Decimal input is converted
exactly to microdegrees/meters. Switching a populated target type requires
confirmation before clearing its selections. Saved and historical targeting
exports and the combined preparation summary include exact radius details.
Country exclusions remain available and can remove part or all of an area.
No negative radius, geocoding, map, city/region search, coordinate-to-country
verification or Google account eligibility lookup is introduced.

Primary reference checked 2026-09-23: Google's location-targeting documentation
(`https://developers.google.com/google-ads/api/docs/targeting/location-targeting`)
for ProximityInfo and microdegree coordinates, plus Supabase functions guidance
and changelog. This remains preparation only: no provider calls, credentials,
ads, spending or outbound messages. Roll back frontend then backend; retain the
compatible validator/RPC to preserve radius drafts and historical reviews.

### K175 — Meta radius targeting drafts

The existing Meta targeting routes accept optional `custom_locations`, using
the same exact four-field label/microdegree/meter model as Google drafts. The
array has at most ten distinct center/distance combinations and requires an
empty `countries` array. Meta draft radii range from 1,000 to 80,000 integer
meters. These are KORLIX planning limits, not provider eligibility guarantees.
Existing five-field country drafts retain their original representation.

The compatible migration adds a private radius validator and replaces the
targeting validator/RPC. It rewrites no rows and preserves country draft/review
fingerprints, versions and snapshots. New responses include radius_supported.
All functions remain SECURITY INVOKER with fixed search paths and service-only
execute privileges; ownership, existing lock order, route limits and optimistic
concurrency are unchanged. No new table or RLS policy is introduced.

Radius drafts with categories NONE may complete the existing combined creative
and targeting preparation review. Undecided or special-category radius drafts
remain saveable but incomplete and cannot be reviewed in KORLIX yet. Keep all
accurate category selections; this is an application support boundary, not an
assertion of Meta's rules. Existing broad age defaults and country-only special
category reviews remain unchanged. Every review remains preparation only.

A shared radius entry component and validators serve Google and Meta with their
own bounds. Google's limits, API shape and display behavior are preserved.
The Meta editor confirms populated target-type changes, saves exact coordinates,
and includes radius details in saved/historical exports. A radius or category
change invalidates the combined review while retaining its original creative
and image metadata. Dirty edits, stale saves, archive restrictions, owner/scope
changes and private image protections retain their existing behavior.

Primary references checked 2026-09-23: Meta's official business SDK
TargetingGeoLocation.custom_locations and TargetingGeoLocationCustomLocation
latitude/longitude/radius/distance_unit fields (raw GitHub source), plus Supabase
functions guidance and unchanged changelog. Meta basic-targeting docs returned
HTTP 429. No complete live targeting policy or account capability is asserted.
No map, geocoding, city search, location exclusions, delivery expansion control,
provider calls, credentials, ad creation, budgets, spending or outbound messages
are added. Roll back frontend then backend; retain compatible SQL and draft data.


### K176 — Google city and region target lookup

Owners can choose **Cities and regions** in the existing Google targeting editor.
The private `GET /:id/campaigns/:campaign_id/google-targeting/locations` route
accepts exactly `q` (2–80 trimmed Unicode characters), `country` (a listed code)
and `kind` (`all`, `city`, `region`). It reuses the targeting RPC's current
Enterprise, funnel ownership and campaign-platform checks, `no-store` response
headers and the shared 30-request owner/minute limit. Search is explicit, bounded
to 30 matches and reports `more` when a narrower query is needed. No provider
account, credential, network request or database mutation is needed for lookup.

`google_locations_catalog.json.gz` contains 69,110 Active reference locations in
201 countries, from Google's August 12, 2026 geo-target CSV. Included types are
City, State, Province, Region, Department, Canton, Governorate, Prefecture,
Autonomous Community, Division, Territory, Union Territory and Okrug. These are
selected named-location types, not every geographic type. Postal codes, counties,
municipalities, neighborhoods and Nielsen DMA/TV data are outside this chapter.
Canonical names disambiguate similar place names; no parent hierarchy, coordinates,
place boundaries or eligibility are inferred. Accents and case are folded for
search only; saved canonical names and Google criteria IDs remain exact.

Reference source and attribution: [Google Ads geo targets](https://developers.google.com/google-ads/api/data/geotargets),
Google Developers, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/),
with transformations described here: Active/type/country filtering, sorted compact
rows and gzip packaging. The source ZIP SHA-256 is
`d4a62971cb283e405a07d537a0af400816ff5a36283e60376a51c7657f3d1e89`.
Rebuild deterministically with
`python3 backend/funnels/build_google_locations.py /path/to/geotargets.zip`.
The builder rejects any other archive. Runtime lookup uses bundled bytes and
never downloads a catalog. Reference availability is not current ad eligibility;
Google country/account/policy checks remain necessary before eventual launch.

Draft assets optionally include `geo_locations`, at most 20 different objects
with exactly `id`, `name` (canonical name), `country` and `type`. This mode excludes
whole-country targets and the `proximities` key, including an empty radius list.
A chosen location cannot be inside an explicitly excluded country. The API checks
all four values against the bundled catalog before saving. The service-only SQL
boundary independently validates object shape, known country, text limits, types,
duplicate IDs and mode/exclusion rules; it does not contain a second geographic
catalog. Direct service-role code remains trusted to enforce catalog membership.
No caller-supplied labels or provider IDs bypass the private API checks.

The additive migration creates `korlix_google_location_valid_v1` and replaces the
existing targeting validator and RPC. All three use SECURITY INVOKER, fixed
`search_path=public,pg_temp`, and service-role-only execution. No table or RLS
policy is created, and no existing row, draft revision, review or fingerprint is
rewritten. Existing country/radius drafts and reviews retain their representation.
The response adds `locations_supported:true` and the pinned
`location_catalog_version:google-locations-2026-08-12`; the UI gates the new mode
on that capability. Saved/historical targeting exports and the combined Google
preparation summary include exact location names, types and criteria IDs.

Changing a populated target mode requires confirmation. Search results are
cleared when query/country/type changes; late responses cannot populate a newer
search or changed workspace. Losing access closes the search's useful state.
Saved changes stale the targeting review while retaining its historical snapshot.
No geocoding, map, Meta lookup, provider activation, ad creation or spend occurs.
Owner hands-on acceptance remains deferred.

Release migration before backend, then frontend. Keep the compatible migration
and all saved rows during rollback. K175 clients cannot interpret newly saved
`geo_locations` drafts; prefer a K176 fix-forward for such owners rather than
removing or converting their choices. Do not rewrite their drafts to roll back.

### K177 — Meta city and region lookup for targeting drafts

The Meta targeting editor adds **Cities and regions**, mutually exclusive with
whole countries and radius areas. `geo_locations` holds up to 20 unique
`{key,name,country,type,region}` objects. Keys belong to Meta; Google criteria IDs
are never substituted. City and region namespaces are separate. Names, country
codes and optional region labels are preserved in saved drafts and historical
combined creative/targeting review exports. No radius, boundary, delivery
expansion or live eligibility is inferred from a name.

GET `/:id/campaigns/:campaign_id/meta-targeting/locations` accepts exactly `q`
(2–80 trimmed characters), `country`, `kind` (`all`, `city`, `region`) and the
current targeting `fingerprint`. Search is an explicit action, not a keystroke
request. The route uses the existing shared 30-request owner/minute targeting
limit, no-store, current Enterprise entitlement, funnel/campaign ownership and
an editable Meta campaign. It requires existing platform configuration, an
unexpired owner connection and its selected active cached ad account. The
existing service-only connection command supplies credentials; they never reach
the browser. This release does not enable the platform or configure credentials.

The provider adapter performs one GET to the fixed Graph `/{version}/search`
endpoint with `type=adgeolocation`, a country, query, city/region location types
and limit 31. Bearer authentication and appsecret_proof reuse existing Meta
configuration. Redirects are rejected; timeout is ten seconds and the response
body is capped at 1 MiB. At most 30 sanitized results are returned with a `more`
flag. Provider pagination URLs, extra fields, tokens and error details are never
returned or followed. Malformed, duplicate, unexpected-type or cross-country
results fail closed. There is no new provider permission request or environment
variable; real API access and account eligibility remain unverified until the
explicitly deferred activation work.

After remote work the route repeats the authoritative campaign/entitlement read
and connection read. Downgrade, disconnect, account/Page/config changes,
archiving or a concurrent targeting save discard the late response. It issues a
30-minute HMAC receipt for each returned row, binding every displayed field,
owner, funnel, campaign and current context fingerprint. The receipt has a
separate domain string and uses the existing server Meta app secret. It is not
a Meta authorization token or an eligibility certification.

Save may include a `location_proofs` object keyed by `type:key` for new choices.
The backend accepts an exact previously saved row or verifies its fresh receipt.
It first checks authoritative saved version and fingerprint, then the SQL save
checks them again atomically. A receipt cannot cross owners, campaigns, context
changes or edited names/IDs. Receipts remain transient; they are stripped before
SQL and never stored in drafts, review history or exports. Existing selections
can be retained or removed after disconnection without a new provider request.
Saving targeting, reading drafts, reviewing and exporting never call Meta.

The migration creates the private `korlix_meta_location_valid_v1` and replaces
the existing Meta asset validator and targeting RPC. It adds no table or policy,
rewrites no rows, and preserves country/radius fingerprints and review history.
All three functions use SECURITY INVOKER, fixed public/pg_temp search paths and
service_role-only execution. SQL independently validates structure, type,
country membership, limits and mutually exclusive target modes. SQL does not
verify provider membership or receipt signatures: trusted service callers must
preserve the HTTP boundary validation. The existing funnel → campaign →
connection → setup → creative → targeting lock order is unchanged.

`locations_supported:true` advertises the schema; `location_lookup_ready`
reflects editable/current connected-account prerequisites. With platform setup
deferred, the picker explains why search is unavailable while existing choices
remain readable/removable. Mode replacement requires confirmation. Search/query,
country/type changes, owner/scope/client changes and denied access clear stale
results. Duplicate results are disabled. The UI keeps receipts separately from
assets and includes exact Meta keys in saved/historical exports. Status badges
wrap on narrow screens and at increased text sizes.

Only **No special category** named-location drafts can complete preparation
review in this chapter. Undecided/special-category local drafts may be saved at
the existing broad age range, but review stays incomplete; this is a conservative
KORLIX scope limit, not a statement of Meta policy. Actual publishing and
spending remain disabled. Owner hands-on acceptance, real provider calls and
activation remain deferred.

Local verification covers SQL shape/grants and unchanged legacy snapshots,
HTTP scope/rate/no-store, exact transient receipts and expiry, tampering,
concurrent context changes, late results, bounded/redacted provider responses,
legacy Page adapter behavior, picker/save/export flows, unavailable connection
states, and desktop/narrow-phone layouts. These mocked checks do not establish
live Meta access, search coverage or category eligibility.

Apply the migration before backend deployment, verify the backend, then deploy
the frontend. Keep additive SQL and saved choices on rollback. K176 clients
cannot interpret `geo_locations` in Meta drafts, so prefer a fix-forward and
preserve selections and snapshots rather than converting/deleting them.

Primary references checked September 23, 2026: Meta's official
[TargetingSearch SDK](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/targetingsearch.py),
[city fields](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/targetinggeolocationcity.py),
[region fields](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/targetinggeolocationregion.py),
and [Supabase functions](https://supabase.com/docs/guides/database/functions).
Meta targeting-search documentation returned HTTP 429; full current search
parameter/permission behavior still needs live provider acceptance after
activation. Supabase changelog was unchanged from K176. No live provider account
was queried to prepare this chapter.

### K178 — Campaign budget pacing from manual results

Campaign cards expose **Budget pacing** for Meta, Google and Other plans. Owners
save a UTC reporting start date; the window ends after the campaign's current
1–90 day duration, inclusively. The current USD daily plan supplies the total
planned amount. Plan edits update the comparison on refresh without changing the
saved start date. A reporting window is not a provider flight schedule, spending
authorization, enforced budget or automatic pause rule.

The tracker sums only owner-entered daily reports within that window. A missing
date is unknown, not zero. Today's entry contributes to recorded spend and total
plan overrun detection, but remains partial and is excluded from completed-day
comparisons. Future dates are pending; reports outside the window are counted as
excluded. An explicit zero entry counts as reported. Completed-day variance uses
only completed dates with entries and their matching daily planned amounts, so a
reporting gap cannot manufacture underspend. The UI shows completed-day coverage,
missing dates, total-plan overrun, and expandable daily coverage. Plan minus
recorded spend is clearly distinguished from confirmed money available to spend.
There is no forecast, currency conversion, imported-provider total or attribution
claim. Arithmetic uses integer USD cents and UTC calendar dates, including leap
days and year boundaries; at most 90 window days and 731 source rows are handled.

GET `/:id/campaigns/:campaign_id/budget`, POST `.../save` and `.../clear` use the
shared authenticated-owner wrapper, no-store and a shared 30-request owner/minute
limit. Query parameters are rejected. Save accepts exactly `version`,
`campaign_version`, `start_date`; clear accepts the two versions and
`confirmed:true`. The start date must be an exact real YYYY-MM-DD date within the
past 730 days or next 365 days, using the database's current UTC date. Both HTTP
and SQL validate mutation shapes. The response includes server date/time, a
point-in-time current plan and manual reports; `budget_enforced` and
`ad_publishing_ready` always remain false.

The additive RLS-enabled private `korlix_funnel_campaign_budget_windows` table
references its campaign with cascading deletion. Browser and PUBLIC table/RPC
grants are revoked. The service-only SECURITY INVOKER command repeats current
Enterprise entitlement and ownership checks, locks funnel → campaign → window,
and checks both window and campaign versions. Campaign/report edits therefore
invalidate stale saves as well as concurrent window edits. Clearing retains a
versioned empty row to prevent a stale save from recreating an old window; it
does not delete daily reports. Archived campaigns are read-only. No existing
function, campaign review, campaign version, report or provider connection is
changed by this migration or by saving/clearing a reporting window.

The client independently verifies identity, source, currency, dates, coverage
and all derived totals before display or export. Dirty date changes hide the old
comparison and block copying until saved; discard and clear require confirmation.
Refresh and failed writes clear stale totals. Account/workspace/client changes
and access denial clear private content and invalidate pending results. A copied
saved summary includes the check timestamp, exact saved window/current plan,
all daily coverage, and the manual-reporting/spending limits above.

Focused local verification executes the actual migration and Express routes,
covering browser roles, ownership, downgrade, archive, version conflicts,
clear/recreate, cascade, invalid inputs, no-store/rate limiting, UTC boundaries,
missing versus zero reports, partial today and integer precision. Flutter checks
cover corrupted/mismatched responses, exact save/clear requests, conflict and
refresh failures, saved export, late responses/scope changes and desktop/390px/
320px (1.3 text scale) layouts. Existing campaign/report behavior is retained.
These checks are not owner acceptance; all hands-on acceptance remains deferred.

Apply the additive migration before the backend, verify it, then deploy the
frontend. On rollback, roll back frontend then backend and retain the additive
table/RPC and saved windows. K177 simply lacks the budget tracker; existing
campaigns and reports remain usable. No environment changes, new dependencies,
provider calls, provider activation, ad creation, spending or outreach are added.

Primary guidance checked September 23, 2026: [Supabase database functions](https://supabase.com/docs/guides/database/functions)
and [changelog](https://supabase.com/changelog). Both fetched documents match the
K177 hashes; the listed changes do not alter this private invoker-RPC design.

### K179 — Linked Meta campaign reporting

**Linked Meta campaign** on Meta plan cards lets an Enterprise owner associate
one reported Meta campaign by its exact ID. Names can repeat; the picker shows
IDs and requires confirmation. A Meta campaign can link to only one of the
owner's plans per ad account. Loading choices and performance is explicit, with
7, 30 or 90 completed ad-account calendar days. Search and 20-row client pages
operate on at most 300 returned campaigns. A campaign absent from Meta's report
cannot be newly selected in that period; try another period. This reuses the
existing read-only insights adapter and ads_read access, with no new permission,
environment variable, dependency, background sync or provider mutation.

The report shows the linked campaign's spend, clicks (all) and impressions in
the account currency, separately from KORLIX tagged inquiries. Exact decimal
spend is preserved to six fractional digits; no currency conversion, inferred
cost per conversion, revenue or ROAS is added. A missing provider row is unknown,
not zero. An explicit zero remains zero. The saved name is a snapshot; the current
reported name is shown separately if Meta renames the campaign. Provider figures
can be revised. Manual USD daily results and Budget pacing remain separate.

Inquiry counting requires this plan's exact k143 tracking tag and Facebook UTM
source. PostgreSQL converts the account-timezone start midnight and midnight
after the final day into a half-open UTC interval. This includes the first
instant and excludes the last, handling daylight-saving changes and fractional
timezone offsets. The database independently requires the period to end yesterday
in that account timezone and match exactly 7, 30 or 90 days. Tags are
visitor-supplied and are **not verified Meta conversions**. The owner-selected
association covers the entire chosen period, including dates before linking.

GET `/:id/campaigns/:campaign_id/meta-link`, POST `.../save`, and POST
`.../clear` share a 30-request owner/minute limit. GET `.../campaigns` and
GET `.../performance` share the existing Meta performance 10-request owner/minute
quota. All routes use authenticated ownership, current Enterprise access,
no-store and strict query/body shapes. Save requires the exact version,
fingerprint, confirmed flag, provider campaign ID/name and a choice receipt.
Clear requires version, fingerprint and confirmation. Report requests accept
only days and the current fingerprint; the browser cannot choose dates or a
timezone. Opening or refreshing the association only reads local state.

Choice receipts expire after 30 minutes and bind owner, funnel, plan, context,
provider ID and name using a domain-separated HMAC with the existing Meta app
secret. The HTTP layer verifies the receipt, then strips it before the RPC.
Receipts and performance metrics are never persisted. SQL validates shapes,
ownership, entitlement, local Meta platform, selected account readiness, version
and fingerprint. SQL does **not** independently verify the HMAC or provider
membership: privileged service writers must preserve the HTTP boundary.

The additive RLS-enabled private `korlix_funnel_meta_campaign_links` table has
cascading campaign/owner references and an owner/account/provider uniqueness
constraint. Browser and PUBLIC grants are revoked. Its service-only SECURITY
INVOKER RPC has a fixed public/pg_temp search path. Commands lock funnel →
campaign → Meta connection (shared) → association. The fingerprint binds plan
and funnel versions, association version, connection version/binding, selected
account, expiry and configuration. Clear retains a versioned empty row so a
stale request cannot recreate an old link. Clearing works after disconnect and
on archived plans; archived plans cannot save new links but can read/report a
current link. No existing SQL function, review, manual result or provider
connection is changed by saving or clearing an association.

Remote reads recheck current secret/connection state, fetch the selected
account, and require exact ID, currency, timezone and active status. The existing
adapter limits reports to three pages/300 campaigns with per-request timeouts.
The new adapter boundary checks IDs, duplicates, counts, decimal money and
aggregate totals before returning data. After the provider read, context,
entitlement, connection/binding and calendar day are checked again. Disconnect,
reselection, reconnect, account currency/timezone changes, plan edits and
concurrent relinking suppress stale results. Reconnect requires a fresh link;
an ordinary account refresh can retain it if identity and reporting context
remain the same. Only the linked row is returned in a performance response.

The UI verifies response identity, account, fingerprint, source, period shape,
currency/metric bounds and measurement context before display or copying. SQL,
not Dart, performs IANA timezone conversion. Changing period, refreshing, failed
requests, workspace/client changes and denied access clear prior results.
Selection confirmation is inline so private candidate names disappear on scope
invalidation. Export includes the saved association, reporting/check timestamps,
exact UTC interval, source-separated figures and attribution/spending limits;
choice receipts are excluded.

Focused local checks execute the actual migration and Express routes, including
private grants, ownership, entitlement loss, signed-choice tampering/expiry,
one-to-one links, optimistic conflicts, clear/recreate, shared quotas, changed
accounts, late responses, missing versus zero, money precision, and timezone
boundaries. Flutter checks cover validation, exact save/clear, copy, period
changes, search/pages, stale-state rejection and desktop/390px/320px layouts
(320px at 1.3 text scale). Existing Meta reporting and campaign UI checks remain
green. These use mocks/local databases: hands-on acceptance, real provider calls,
activation, ad creation, spending and outreach remain deferred.

Apply the additive migration before the backend, verify it, then deploy the
frontend. Roll back frontend then backend while retaining the additive table,
RPC and saved associations. K178 ignores this association and remains compatible.

Primary references checked September 23, 2026: Meta's official
[AdAccount SDK and insights parameters](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/adaccount.py),
[PostgreSQL AT TIME ZONE](https://www.postgresql.org/docs/current/functions-datetime.html#FUNCTIONS-DATETIME-ZONECONVERT),
[Supabase database functions](https://supabase.com/docs/guides/database/functions)
and [changelog](https://supabase.com/changelog). Supabase documents match K178
hashes; listed changes do not alter this private invoker-RPC design. No real
provider account was queried during implementation.

### K180 — Linked Google campaign reporting

**Linked Google campaign** on Google plan cards adds the same explicit reporting
association as K179 for Google Ads. Owners choose a campaign by exact ID from
the selected advertising account's report and confirm the link. Names may
repeat. A provider campaign can link to only one of the owner's plans per
advertising account, even if that account is reachable through multiple
managers. This reporting association does not certify that the saved plan
matches the provider campaign, launch ads, change bids/budgets, or grant new
Google permissions.

Choice/report loading is explicit and uses 7, 30 or 90 completed account-calendar
days. At most 500 returned campaigns are available, with search and 20-row UI
pages. Existing Google campaign reporting supplies exact decimal cost, clicks,
impressions, status and channel. Campaign IDs remain positive int64 strings all
the way through storage and rendering, including values above JavaScript's
safe integer range. Google cost_micros is converted by the existing adapter
using integer arithmetic; account currency and up to six decimal places are
preserved. Missing provider rows remain unknown; explicit zero stays zero.
Saved and current names remain distinct. No conversion cost, revenue, ROAS or
currency conversion is inferred. Manual USD results and Budget pacing stay
separate.

KORLIX inquiry counts use this local plan's exact k143 tag and Google UTM source.
The database converts account-timezone calendar midnights to a half-open UTC
interval and requires the requested 7/30/90-day period to end yesterday in that
timezone. DST and fractional offsets are retained. Tags are visitor-supplied
and are **not verified Google conversions**. The association applies to the
whole chosen period, including dates before it was saved. Google test accounts
are supported for read-only association/reporting and are visibly labeled as
not live ad delivery; their test flag also appears in copied summaries.

Five authenticated no-store routes live under
`/:id/campaigns/:campaign_id/google-link`: GET the saved association, POST
`/save`, POST `/clear`, GET `/campaigns`, and GET `/performance`. Local commands
share 30 requests per owner/minute. Provider choices/performance share the
existing Google reporting 10-request owner/minute quota. Save accepts exactly
version, fingerprint, confirmed:true, provider_campaign_id,
provider_campaign_name and proof. Clear accepts version, fingerprint and
confirmation. Remote reads accept only days and fingerprint; browser-supplied
accounts, manager headers, dates and timezones are rejected.

The new private RLS-enabled `korlix_funnel_google_campaign_links` table stores
the selected account and access-account/manager context, credential binding and
config identity, name snapshot and optimistic version. It stores no token,
choice receipt or metrics. Its owner/account/campaign uniqueness is independent
of access manager. Browser and PUBLIC grants are revoked. The service-only
SECURITY INVOKER RPC has a fixed public/pg_temp search path and repeats current
Enterprise, ownership, Google platform and context checks. Commands lock funnel
→ campaign → Google connection FOR SHARE → association. Clear keeps an empty
versioned row and is available after disconnect, changed access paths and
archive. Archived plans cannot save new links but can read/report a current link.
The additive migration changes no existing RPC, provider connection, campaign
review or manual result.

Thirty-minute HMAC receipts bind owner, funnel, plan, fingerprint, provider
ID/name and expiry using a Google-specific purpose and the existing OAuth
client secret. Meta receipts cannot be reused. HTTP verifies and discards the
receipt before SQL. SQL validates local shape/identity/readiness but does not
independently prove provider membership or verify signatures; privileged
service writers must preserve this HTTP boundary.

Google-specific access checks include the current direct-access root list,
root ID, login-customer-id relationship, selected non-manager enabled account,
refresh-token expiry, currency, timezone and test-account identity. Direct
access requires the root to equal the selected account and sends no manager
header. Manager access requires the matching manager header. Each explicit
remote read refreshes access using the existing encrypted refresh token,
rechecks available roots and the selected account, and calls the existing
read-only campaign search adapter. That adapter bounds each request to ten
seconds/two MiB, at most five pages and 500 campaign rows. The new boundary also
validates IDs, duplicates, enums, exact metrics and aggregate totals. Local
context/entitlement, credentials and the reporting calendar day are rechecked
after remote work. Changing root/manager, reconnecting, losing access or editing
the plan/link rejects late data; a changed access path requires a fresh link.

The UI validates account/root/manager context, identity, fingerprint, period
shape, metrics and measurement context before display/export. SQL performs
IANA timezone conversion. Private content and pending confirmations clear on
workspace/client/access changes. Period changes, refreshes and errors remove
old results. Copy includes saved access context, test-account status, exact
reporting interval, provider status/channel and reporting limitations, without
choice receipts. No automatic provider lookup occurs on opening the panel.

Focused verification uses the actual migration and Express routes in a local
database with provider mocks, plus Google reporting regressions and Flutter
checks. Coverage includes manager/direct access, root removal or changes during
loading, revoked/expiring refresh access, test-account identity, receipt replay,
int64 IDs, 500-row bounds, duplicate names, clear/conflicts, no-store/shared
quotas, exact monetary values and timezone boundaries. UI checks cover saved
and stale link flows, response rejection, exports, late responses and desktop,
390px and 320px layouts (1.3 text scale at 320px). No full suite, real provider
account call or owner hands-on batch was run. Activation, ad creation, spending
and outreach remain deferred.

Apply the additive migration before the backend, verify it, then deploy the
frontend. Roll back frontend then backend to K179 while retaining the private
table/RPC and owner associations. K179 ignores this new link. No new dependency,
environment variable, permission, scheduled worker or provider mutation is added.

Primary references checked September 23, 2026: Google's official
[REST examples](https://developers.google.com/google-ads/api/rest/examples)
confirm manager-header/direct-access handling, campaign resources and reporting
fields; the existing v25 reporting adapter is reused. The v25 field-reference
pages were unavailable through web retrieval, so no changed field contract is
assumed. [Supabase functions](https://supabase.com/docs/guides/database/functions)
and [changelog](https://supabase.com/changelog) were fetched again and match K179
hashes; reviewed changes do not alter this private invoker-RPC design.

## K181 — Create a paused Google Search campaign

K181 adds an owner/Enterprise creation flow to Google campaign cards. It compiles the current reviewed plan, published landing page, responsive search-ad copy, positive/negative keywords and country, city/region or radius targeting into one atomic Google Ads mutation. It creates a separate average daily budget, a Search campaign, one Search ad group and one responsive search ad. Campaign, ad group and ad are explicitly **PAUSED**. Positive keywords are enabled inside the paused group; this cannot activate delivery. Google Search is on, Search Partners and Display are off. Country exclusions use presence. Saved targeting language IDs become actual language criteria.

This first version supports production USD accounts and the saved **Maximize Clicks** bidding choice. It does not silently change Maximize Conversions to another strategy. All six preparation checks must be current, the selected account and direct/manager access path must match fresh Google checks, and the owner must explicitly confirm paused creation, acknowledge the average-budget limits, and declare that the campaign does not contain EU political advertising. Start is chosen from today through the next 30 days in the account timezone; end is derived from the plan's 1–90-day duration. Google v25 uses `startDateTime` at `00:00:00` and `endDateTime` at `23:59:59`, interpreted in the customer timezone. No activation or resume operation exists.

### Activation boundary

`KORLIX_GOOGLE_ADS_CREATE_PAUSED_ENABLED=true` is a new, default-OFF server gate. It also requires valid existing Google configuration, `KORLIX_GOOGLE_ADS_ENABLED=true`, and exactly API `v25`. Configuring connections alone cannot enable creation. The K181 release must leave provider settings and this new gate unchanged; provider activation and owner acceptance remain deferred. Test accounts remain available for older read-only reporting but cannot enter this first production-creation flow. Existing `ad_publishing_ready` remains false; `create_ready` is limited to the paused operation. No provider credentials, real account requests, advertising, expenditure or outreach are required to install this chapter.

### Routes and persistence

All routes are authenticated, authoritative owner/Enterprise scoped, and `Cache-Control: no-store`, under `/api/funnels/:id/campaigns/:campaign_id/google-create`:

| Method | Suffix | Input / behavior |
| --- | --- | --- |
| GET | none | Local preparation and saved creation record only; no provider request. 30 owner requests/minute. |
| POST | `/create` | Exact keys: `fingerprint`, `start_date`, `confirmed:true`, `budget_acknowledged:true`, `no_eu_political_ads:true`. Five owner requests/minute. |
| POST | `/reconcile` | Exact `attempt_id`. Read-only provider lookup of an existing uncertain attempt. Five owner requests/minute. |

New migration: `supabase/migrations/20260923210921_funnel_google_paused_create.sql`. It adds `public.korlix_funnel_google_creations` and `public.korlix_funnel_google_create_v1(uuid,text,uuid,jsonb)`. RLS is enabled, PUBLIC/anon/authenticated privileges are revoked, and only service_role has required CRUD/EXECUTE. The RPC is SECURITY INVOKER with fixed `search_path=public,pg_temp`. Campaign primary key and unique attempt UUID enforce a single dispatch slot per plan. Owner/date index supports scoped operational investigation. Campaign and user references cascade on intentional parent deletion. No existing function is redefined.

The snapshot stores the exact approved plan, page destination, account/access identity, copy, keywords, targeting, date window and declarations. It contains no OAuth token, secret configuration hash, receipt or provider metrics. The private ledger also stores the request hash, durable attempt ID, result resource names and timestamps. Browser output excludes the internal dispatch bit and request hash.

### Dispatch and uncertain outcomes

1. Read coherent current preparation and check the owner-supplied fingerprint/date/declarations.
2. Refresh OAuth access, check accessible roots and fresh selected account, then send the exact grouped request with `validateOnly:true`. Validation errors create no ledger slot and no Google resource.
3. Recheck connection identity. In a transaction with the established funnel → campaign → connection → component → ledger lock order, repeat current entitlement, reviews, fingerprint and account-calendar checks, then atomically claim the sole dispatch slot. The row starts `unknown` **before** the external write.
4. Only the request whose claim returned `dispatch:true` may send once, with `partialFailure:false`, `validateOnly:false`, and resource-name-only results. Recompiled claimed content must match the previously validated request hash.
5. Validate every returned resource name, account, operation count, uniqueness and parent identity, then record completion. The service-only internal `finish` action can record an already-dispatched result after entitlement or plan changes; it never authorizes a new send. Every HTTP response still repeats current owner/Enterprise checks.

Concurrent or repeated create requests with any existing attempt return its record and do not send again. Network timeout, unreadable/malformed result, provider rejection after dispatch, process crash or failed local completion all preserve `unknown`. No background retry, timeout-based reset, resend button, force-complete endpoint or automatic compensation/delete exists. Unknown does not mean failed. Once the claim has committed, later local edits do not cancel that authorized paused snapshot; this is the dispatch boundary.

An explicit result check searches only by a fixed `KORLIX <server UUID>` creation name. It uses four bounded GAQL reads to verify one campaign/budget, one paused ad/group and the expected keyword and location/language criteria. It verifies account, budget amount, schedule, network and bidding settings, political declaration, destination, copy and paused state before recording recovered resource IDs. It tolerates irrelevant provider text-asset performance labels but rejects changed text/pins. No missing, paginated, duplicate, externally enabled or edited structure is adopted. Absence does not authorize resending; if the result cannot be established, an operator must inspect Google Ads using the saved name. There is intentionally no self-service reset of an ambiguous dispatch. This is at-most-one KORLIX dispatch per retained plan, not a claim that Google offers a universal idempotency key or that a stored record monitors subsequent delivery.

### Interface and spending limits

The dialog shows account, timezone, average daily amount and the exact creation window, with three initially unchecked confirmations. Date changes, refreshes, errors and context changes clear confirmations. After a request failure the owner must reload the durable record; an uncertain attempt offers only read-only checking. Historical records preserve the submitted snapshot across later local edits. Scope, client, funnel and entitlement changes suppress late private responses, confirmations and copying. Copyable summaries include account/access context, dates, declarations, assets and resource IDs. No provider outcome or policy approval is inferred from local preparation.

Google's average daily budget is **not a hard daily cap**, and multiplying it by the planned days is **not a hard total cap**. The campaign remains paused at creation. Real activation, provider-enforced budget/pause controls, Meta creation and verified conversion attribution remain separate unfinished work. K179/K180 reporting associations are separate from the creation ledger and are not silently replaced. A created campaign does not establish verified conversions. No real provider operation or deferred hands-on acceptance has been performed as part of local K181 implementation.

### Focused local verification

`node --test backend/test/funnel_google_paused_create.test.mjs backend/test/funnel_google_paused_provider.test.mjs backend/test/funnel_google_ads_provider.test.mjs backend/test/funnel_google_preflight.test.mjs` covers real PGlite migration/SQL and Express routes, narrow request compilation, single dispatch under concurrent requests, snapshots, independent grants, identity/entitlement changes, provider validation and response handling, incomplete outcomes, read-only recovery, disabled gates and retained provider/preparation behavior. Provider HTTP is mocked. Frontend checks cover narrow bodies, confirmations/date reset, unknown outcomes, scope invalidation, access denial, exact summaries and real-font layouts at 1400px, 390px and 320px/1.3 text scale, plus existing campaign UI regression checks. These checks do not certify live Google permissions, ad policy eligibility, billing setup or conversion tracking.

Primary contracts checked September 23, 2026: [grouped REST mutations](https://developers.google.com/google-ads/api/rest/examples), [mutation transactions](https://developers.google.com/google-ads/api/docs/mutating/overview), [bidding strategies](https://developers.google.com/google-ads/api/docs/campaigns/bidding/assign-strategies), [targeting criteria](https://developers.google.com/google-ads/api/docs/targeting/criteria), [average daily budgets](https://support.google.com/google-ads/answer/6385083), and the official [v25 campaign schema](https://github.com/googleapis/googleapis/blob/master/google/ads/googleads/v25/resources/campaign.proto) and [mutation service schema](https://github.com/googleapis/googleapis/blob/master/google/ads/googleads/v25/services/google_ads_service.proto). The v25 protobuf definitions were read directly because some rendered reference pages were unavailable or exceeded retrieval limits. This caught the current date-time field names; older date-only mutation fields are not used.

## K182 — Google activation and pause controls

The Google plan card now opens **Google campaign controls**. Opening/refreshing the command record reads local data only. **Load current Google status** is an explicit provider read. Controls apply only to the exact resources recorded by K181; a K180 reporting association alone is insufficient. This release does not enable providers or send a real Google command.

`KORLIX_GOOGLE_ADS_CONTROLS_ENABLED=true` is a separate, default-OFF server gate. It requires valid existing Google configuration, `KORLIX_GOOGLE_ADS_ENABLED=true`, and exactly API v25. Paused creation need not stay enabled to control an already recorded creation. Leave all gates and credentials unchanged during publication/deployment. Existing creation/preparation/reporting `ad_publishing_ready:false` fields describe those operations; control availability is expressed separately by K182 checks and fresh `can_activate`/`can_pause` values.

Owner/Enterprise routes at `/api/funnels/:id/campaigns/:campaign_id/google-controls`:

| Method | Suffix | Input | Rate per owner/minute |
| --- | --- | --- | ---: |
| GET | none | No query fields; local creation and latest command only | 30 |
| POST | /inspect | Exactly `{}`; fresh account and provider status | 10 |
| POST | /apply | Exactly `proof`, `action`, `confirmed:true`, `spend_acknowledged` | 5 |

`action` is `activate` or `pause`; `spend_acknowledged` must be true only for activate and false for pause. No browser-provided resource, budget, dates, provider operation, internal command ID, receipt or dispatch flag is accepted. There is no HTTP finish, retry, reset or force-confirm route. Responses are no-store. No generic provider mutation transport is exported.

Activation/resume:

- Requires a completed K181 creation, current preparation reviews, unchanged created plan/page/copy/keywords/targeting, and an unexpired end date in the account timezone. Reconnecting the same account/access manager is possible after renewing reviews. The saved schedule and budget are displayed; this control cannot change either.
- Fresh OAuth/roots/account checks verify the selected production USD, enabled, nonmanager account and current connection version/config. Invalid OAuth marks reconnect using the version guard. Credentials remain server-only.
- The exact saved campaign must be PAUSED. A bounded full inspection compares its recorded campaign/budget/group/ad IDs, budget amount/nonsharing/reference count, dates, Search networks, bidding type, location reach, political declaration, ad copy/destination and keyword/location/language criteria. It requires one active ad group and an APPROVED, REVIEWED ad. Limited approval is conservatively unavailable in this version. Group/ad may be PAUSED or ENABLED for a resume after a campaign-level pause.
- An initially unchecked activation confirmation and separate spending authorization are required. The five-minute HMAC proof binds owner, funnel, plan, coherent local fingerprint and normalized provider observation. Refresh/errors/account/workspace changes clear confirmations and observations.
- Apply repeats local/Google checks, validates the exact mutation without changes, rereads Google state after validation, rechecks connection identity, and then claims the command in SQL. A 75-second pre-claim deadline and 85-second pre-send deadline prevent a slow confirmation from starting a late write after the normal client timeout; a claim that returns too late stays UNKNOWN without sending. The actual grouped request enables the saved ad, group and campaign atomically, using only `updateMask:status`, `partialFailure:false`, and resource-name-only responses. It does not update copy, targeting, budget, dates or reporting links.

Pause:

- Requires fresh access to the exact saved campaign, observed ENABLED, the controls gate, and no uncertain command. It changes only that campaign to PAUSED. It intentionally does not require current preparation, matching copy/targeting or an open schedule. Local draft edits, archiving or unpublishing therefore do not prevent a pause while owner/Enterprise and provider access remain available.
- It never enables/changes children and does not cancel earlier charges. A PAUSED or REMOVED campaign offers no redundant status mutation. Loss of Enterprise/account/platform access requires delivery control directly in Google Ads.

Durable command journal:

`korlix_funnel_google_commands` is private RLS storage with no browser policies/grants, service CRUD only, cascade campaign/owner foreign keys, unique command UUID, unique campaign/sequence, one partial unique UNKNOWN slot per campaign, owner/date index, bounded observation and coherent receipt state. The invoker/fixed-path, service-only `korlix_funnel_google_controls_v1(uuid,text,uuid,jsonb)` uses the existing funnel → campaign → connection → preparation/creation lock ordering, then the latest command. No existing function is replaced.

The transaction repeats local entitlement/readiness/fingerprint checks and persists UNKNOWN **before** any write. Only its claimed command sends once. Concurrent/replayed confirmations fail after the first claim. Exact provider response resource identities are verified before the service-only finish stores CONFIRMED. Finish can record the receipt after a tier change but never sends; final HTTP reads repeat current access. Successful history is retained up to 1,000 commands per plan, then additional commands are blocked. Tokens, proofs, secrets and raw provider error payloads are not journaled.

Timeouts, malformed responses, post-dispatch provider errors, process crashes or failed receipt persistence retain UNKNOWN. This blocks every subsequent KORLIX command for that plan. A crash after claim but before sending also stays unknown. A current status observation is not proof of the earlier request's outcome, so inspection never clears UNKNOWN or authorizes a retry. The interface explicitly warns that ads may be spending and directs the owner to inspect/control the campaign in Google Ads. There is no automatic retry, time-based reset, read-based completion or compensating status change. Never delete owner data or a creation/command record to work around uncertainty.

Limits: the database claim is the local dispatch boundary. Edits after the claim do not cancel it. Google reads and mutation are separate requests; external Google Ads/other-tool edits can race despite rechecks, and there is no cross-system conditional write. Avoid simultaneous editing. The inspection covers the modeled saved fields, not every account-level setting or provider feature. Google acceptance is a historical mutation receipt, not proof of current status, immediate delivery, billing/policy eligibility or verified conversions. No background status polling, automatic spend cap, post-creation budget edit, Meta control or conversion attribution is included.

Local checks cover actual PGlite migration/authorization/serialization, Express route boundaries, mock provider mutations and failure recovery, strict field-mask transport, provider drift and policy checks, stale/replayed proofs, late access loss, UI confirmation lifecycle and desktop/mobile text scaling. Real provider activation, API/account calls, ad creation/serving, spending, lead submissions, outreach and owner acceptance batches remain deferred.

Current contract references: [campaigns](https://developers.google.com/google-ads/api/docs/campaigns/overview), [mutating resources](https://developers.google.com/google-ads/api/docs/mutating/overview), official v25 [campaign operations](https://github.com/googleapis/googleapis/blob/master/google/ads/googleads/v25/services/campaign_service.proto), [ad group operations](https://github.com/googleapis/googleapis/blob/master/google/ads/googleads/v25/services/ad_group_service.proto), [ad operations](https://github.com/googleapis/googleapis/blob/master/google/ads/googleads/v25/services/ad_group_ad_service.proto), [budget reference count](https://github.com/googleapis/googleapis/blob/master/google/ads/googleads/v25/resources/campaign_budget.proto), and [ad policy summary](https://github.com/googleapis/googleapis/blob/master/google/ads/googleads/v25/resources/ad_group_ad.proto). Reviewed September 23, 2026. No new dependency or catalog.

## K183 — Controlled Google average daily budget changes

K183 adds explicit budget review and mutation for the exact K181-created Search campaign. It extends K182's command journal, so status and budget confirmations cannot race into separate provider writes. No provider gate is enabled by this release. Real account/provider acceptance and owner acceptance remain deferred.

`KORLIX_GOOGLE_ADS_BUDGET_ENABLED=true` is a new default-OFF server gate, requiring the existing controls gate, configured Google access and API v25. Paused creation need not be enabled for an existing campaign. Keep credentials and all provider flags unchanged during deployment.

Owner/Enterprise routes under `/api/funnels/:id/campaigns/:campaign_id/google-controls`:

| Method | Suffix | Exact body | Owner rate/minute |
| --- | --- | --- | ---: |
| POST | `/budget-preview` | `daily_cents` integer, 100–1,000,000 | 10 |
| POST | `/budget-apply` | `proof`, same `daily_cents`, `confirmed:true`, `spend_acknowledged:true` | 5 |

Opening controls or refreshing the record is local-only. Preview explicitly refreshes OAuth/account access, checks the exact campaign/budget relationship, Search channel, original provider name, PAUSED/ENABLED status, DAILY/STANDARD budget, nonsharing, single reference, and exact expected amount. A changed external budget or shared/replaced budget is rejected; use Google Ads directly. No custom provider resource or operation is accepted from the client.

A proposed increase also requires K182's current reviews, unchanged historical campaign content, open schedule and full saved-resource inspection with an APPROVED/REVIEWED ad. An enabled campaign can receive a budget increase; full inspection permits PAUSED/ENABLED children. Reductions intentionally remain possible with stale reviews, archived plans or paused landing pages, but require current owner/Enterprise access, a matching saved account and budget, gates, journal capacity and no uncertain command. A budget change never pauses, activates or changes the schedule. Unchanged amounts are rejected.

The five-minute HMAC proof binds the owner, funnel, plan, coherent local fingerprint, exact before/after amounts, campaign status and normalized inspection. Status proofs cannot authorize budget changes or vice versa. Apply repeats access/provider checks, runs validate-only, rereads provider state, repeats connection identity and claims the command in SQL. The 75-second pre-claim and 85-second pre-send deadlines match K182. A too-late claimed request remains UNKNOWN without sending.

The single Google mutation updates only the saved `campaignBudgetOperation.update.amountMicros` with REST `updateMask:amountMicros`, integer cents multiplied by 10,000, `partialFailure:false` and `RESOURCE_NAME_ONLY`. The response must confirm the exact saved budget. There are no provider retries or automatic compensation. Errors or failed receipt persistence after claim retain UNKNOWN and block **all** subsequent KORLIX status/budget commands. Observations cannot clear that state. Use Google Ads to inspect current delivery and control spending; never delete journal or creation history to bypass uncertainty.

Migration `20260923225318_funnel_google_budget.sql` adds nullable integer `daily_cents` to the existing private RLS journal, extends the action constraint with `budget`, and requires a bounded amount exactly for budget commands. It replaces `korlix_funnel_google_controls_v1(uuid,text,uuid,jsonb)` in place, retaining invoker mode, fixed search path, service-only execution, existing ownership/tier checks, lock order, one UNKNOWN slot and 1,000-command limit. No new table, browser policy, dependency or catalog is introduced. The existing campaign/sequence index also supports reading the latest confirmed budget within the bounded journal.

The reader returns `budget_enabled` and `managed_budget` (`daily_cents`, `original_daily_cents`, `command_id`, `confirmed_at`). The managed amount comes from the most recent CONFIRMED budget receipt, otherwise original creation. Unknown requests do not advance it. The original K181 creation snapshot, local plan and manual reporting remain unchanged. Activation/resume and later budget inspection use the managed amount, while current-content checks continue comparing the original saved content. A receipt is historical acceptance, not a fresh provider observation or billing guarantee.

The interface labels original and latest confirmed budgets separately. Budget review displays the observed amount, proposed amount and status, then requires two initially unticked confirmations. Editing, refreshing, errors or workspace/access changes clear the proposal/confirmations; delayed private responses are suppressed. Amount parsing uses integer cents and rejects fractions of a cent, exponents and locale separators. Both increases and decreases require acknowledging that earlier charges remain and that today's limit may use a higher budget selected earlier that day. No recalculated local “planned total” is presented as a cap.

Google reads and mutation are separate requests, without cross-system compare-and-set. External account changes can race with confirmation; avoid simultaneous editing. A provider response confirms the requested operation, not subsequent delivery or eventual charges. Modeled-field inspection does not inspect every account-level setting.

Deployment order: approved public source, exact migration, backend release/deploy and anonymous verification, then frontend release/deploy and verification. Applying the schema while K182 runs is compatible for existing status commands and defaults budget availability to false; prior open proofs become stale. Deploy the backend before the new frontend. After actual budget commands exist, rolling back to K182 can make its older UI reject budget journal entries and its activation inspection expect the original amount. Retain the journal/migration, disable controls if necessary, use direct Google Ads control and deploy a forward fix; do not erase receipts or restore the old RPC over budget history. With all gates still disabled and no budget writes, the recorded K182 service commits remain the normal service rollback targets.

Local verification: 35 actual-SQL/route/provider checks, including existing K182 controls, and 23 Flutter checks, including existing campaign workspace behavior. These verify bounds, sharing/drift, exact masks and receipts, uncertainty, proof replay, competing status/budget claims, unchanged creation history and confirmation lifecycle. No live provider/account call, ad change or hands-on acceptance is established by those checks.

Contract references reviewed September 23, 2026: official v25 [budget resource](https://github.com/googleapis/googleapis/blob/master/google/ads/googleads/v25/resources/campaign_budget.proto), [budget service and field mask](https://github.com/googleapis/googleapis/blob/master/google/ads/googleads/v25/services/campaign_budget_service.proto), [how budget changes take effect](https://support.google.com/google-ads/answer/10487143), and [changing an average daily budget](https://support.google.com/google-ads/answer/2375420). For most campaigns, the day-of-change spending limit reflects twice the highest average daily budget used that day; lowering a budget does not erase prior spending. This implementation changes average daily budgets only, not campaign total budgets.

## K184 — Meta paused campaign creation

The Meta plan card now opens **Create paused Meta campaign**, with the saved image, primary text, headline, description, button, destination, Page, ad account, target area, age, budget and schedule available for review. Opening and refreshing the record are local reads. Image previews use the owner's private image endpoint. This chapter does not enable providers or perform live advertising operations. Owner acceptance and real provider/account acceptance remain deferred.

New gate `KORLIX_META_CREATE_PAUSED_ENABLED=true` defaults OFF and requires existing valid Meta configuration and exactly Graph API v26.0. Keep all credentials and provider flags unchanged during release. Creation requires Enterprise ownership, a published landing page, a reviewed campaign, a current Meta setup review and a current combined creative/targeting review. This version supports active USD accounts, **Facebook Feed only** (mobile and desktop), no special ad category, and the existing saved country, coordinate/radius or city/region targets. Automatic placements and special-category drafts remain available for preparation but cannot create through this flow.

Owner/Enterprise routes under `/api/funnels/:id/campaigns/:campaign_id/meta-create`, all no-store:

| Method | Suffix | Exact input | Owner rate/minute |
| --- | --- | --- | ---: |
| GET | none | No query parameters | 30 |
| POST | `/create` | `fingerprint`, `start_date`, `confirmed:true`, `budget_acknowledged:true` | 5 |
| POST | `/reconcile` | Saved `attempt_id` only | 5 |

No client resource IDs, account/Page choices, provider fields or internal state are accepted. There is no HTTP progress, finish, retry, resume, reset, activate or cleanup route. Historical records remain readable after local archiving or pausing the landing page, subject to ownership and Enterprise access.

The start date is tomorrow through the next 30 days in the selected account's IANA timezone; duration remains 1–90 calendar days. SQL computes local midnight through 23:59:59 on the final day, including timezone offset transitions. The ad set receives integer USD cents as its daily budget, `OUTCOME_TRAFFIC` campaign objective, `LINK_CLICKS` optimization, `IMPRESSIONS` billing, `LOWEST_COST_WITHOUT_CAP` bidding and `WEBSITE` destination. Campaign budget sharing and dynamic creative are off; audience automation requests `advantage_audience:0`. KORLIX supplies the reviewed tracking URL, single-image unpublished Page story and selected CTA. No campaign-level budget is created. These requested settings still require Meta account and policy eligibility.

Before any resource creation, KORLIX verifies the image's stored WebP digest/dimensions, decodes it with bounded Sharp settings and encodes a lossless PNG. It uploads PNG bytes directly, never a public image URL. The request hash binds the compiled plan and PNG digest. Source images remain private WebP assets; their local image description is not mapped to an unverified Meta alt-text field. Meta may normalize targeting or apply account/creative defaults; this version does not claim to disable every enhancement or inspect every account setting. Check Ads Manager, including creative rendering and default city reach, before any future activation.

Fresh access checks verify the current selected active USD ad account, exact account metadata, connection version/config/expiry, Meta USER token app/user identity, token and data-access expiry, scopes `ads_management`, `pages_show_list`, `pages_read_engagement`, `pages_manage_ads`, and the exact shared Page with `ADVERTISE` or `MANAGE` task. Page discovery is bounded to 500. Tokens stay server-only; provider calls use a fixed Graph host/version, bearer authorization, HMAC app-secret proof, rejected redirects, a ten-second timeout and a bounded JSON response. Invalid OAuth marks only the matching connection version for reconnect. Errors returned to the browser exclude raw provider details.

Meta creation uses **five separate writes**, not an atomic transaction:

1. Upload the verified image and record its image hash.
2. Create the campaign with `status:PAUSED` and record its ID.
3. Create its ad set with `status:PAUSED` and record its ID.
4. Create the image/link creative and record its ID; a creative itself has no delivery status.
5. Create the ad with `status:PAUSED` and record its ID.

Campaign validate-only runs before the durable claim. Later ad set, creative and ad validation occurs when prerequisite IDs exist. Validate-only must return the supported unambiguous success shape. Every later write repeats current local access and connection checks. There is a 75-second pre-claim deadline and an 85-second check before each write; ten-second provider timeouts fit within the client's 100-second timeout in normal operation, while slow storage or a lost response can still leave an uncertain record. No write is retried automatically.

Migration `20260923232651_funnel_meta_paused_create.sql` creates private RLS table `korlix_funnel_meta_creations` with no browser grants/policies, service CRUD only, owner/campaign cascade keys, one attempt per plan, unique attempt UUID, bounded snapshots/receipt maps, fingerprints/request hashes and coherent `unknown`/`created` timestamps. Its service-only invoker RPC `korlix_funnel_meta_create_v1(uuid,text,uuid,jsonb)` fixes the search path and uses the existing funnel → campaign → connection/preparation lock order. It replaces no existing function. `prepare` checks the exact current fingerprint; `claim` repeats eligibility and persists UNKNOWN before writes. Ordered progress records each confirmed receipt immediately. Internal progress/completion can persist a receipt after late entitlement loss, while the final owner read still denies access.

Any failure after claim stops remaining writes, leaves UNKNOWN and preserves already stored IDs. A lost image upload receipt cannot be recovered automatically. Confirming again returns the existing record and never continues it. Meta Ads Manager is the place to inspect or clean up partial resources; never delete the journal to bypass uncertainty.

**Check creation result** performs only provider reads. It requires the original account and Page, current access and an already stored upload hash. It verifies a full matching paused graph: exact campaign/ad set/creative/ad IDs and relationships, names, modeled budget/schedule/targeting/copy/CTA/destination/image hash, and all prior receipts. If the campaign ID receipt is missing, an exact-name scan is bounded to 500 campaigns and rejects duplicates. Child reads reject multiple ad sets/ads and paging. Unknown targeting fields, automation additions and changed creative links are rejected. Extra provider normalization can conservatively prevent reconciliation; it never permits a resend. A missing complete graph is not proof that nothing was created. The completed record is historical acceptance, not live delivery, approval or a conversion claim; reporting links remain separate.

Both confirmation boxes start unticked and reset after edits, refreshes, failures or workspace changes. The owner explicitly approves image upload/paused creation and acknowledges that Meta's daily budget is an average, individual days can vary after activation, and the local planned total is not a hard cap. No activation or spending authority is granted by this step. Partial resource IDs, original image/copy and history can be copied for follow-up.

Deploy the approved source and migration, then the backend with anonymous verification, then the frontend. The new schema is additive and K183 can remain live during migration. Keep the ledger and migration if services roll back; do not erase provider receipts. With gates disabled, the recorded K183 service commits are the rollback targets. Once actual attempts exist, retain their records and use Ads Manager for any uncertain or active resources.

Local verification covers actual PGlite migration/role checks and Express flows, single dispatch under concurrent confirmations, partial/lost receipts, validation failures, connection/tier changes, default-off gates, bounded recovery, exact mocked provider bodies and private WebP-to-PNG fidelity. Flutter checks cover strict current/history validation, two confirmations, schedule edits, uncertain outcomes, stale-response suppression, access denial, copied summaries and real-font desktop/mobile layouts. These are local checks, not live-provider acceptance.

Contract references inspected September 23, 2026: Meta's official Python Business SDK [API version](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/apiconfig.py), [ad-account create edges](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/adaccount.py), [campaign](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/campaign.py), [ad set](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/adset.py), [ad creative](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/adcreative.py), [ad](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/ad.py), [targeting](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/targeting.py), [link data](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/adcreativelinkdata.py), and [Page story](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/adcreativeobjectstoryspec.py). The SDK identifies Graph v26.0. Rendered Marketing API reference pages returned HTTP 429; the SDK confirms fields, not live account eligibility or response acceptance. No SDK dependency is added. Validate-only/receipt shapes, Page scope acceptance, CTA, city reach, radius and creative defaults still require the deferred provider acceptance before enabling this gate.

## K185 — Meta campaign status, activation and pause

K185 adds **Meta campaign controls** for the exact resources recorded by K184. Opening or refreshing the dialog reads local history only. Loading current status explicitly contacts Meta. This release does not enable advertising providers, create real ads or authorize spending. Owner acceptance and authenticated provider/account acceptance remain deferred.

`KORLIX_META_CONTROLS_ENABLED=true` is a new default-OFF gate requiring existing valid Meta configuration and exactly Graph v26.0. K184's creation flag need not remain enabled for an existing campaign. Keep credentials and all gates unchanged during deployment. The feature requires Enterprise ownership, the same saved ad account and fresh active USD account/token access. Status and pause require `ads_management`; they do not require a selected Page or current creative/setup reviews. Activation additionally requires both current reviews, unchanged saved content/account/Page, an open schedule, full Page advertising permissions and a matching provider graph.

Routes under `/api/funnels/:id/campaigns/:campaign_id/meta-controls`, all owner/Enterprise and no-store:

| Method | Suffix | Exact input | Owner rate/minute |
| --- | --- | --- | ---: |
| GET | none | No query parameters; local record only | 30 |
| POST | `/inspect` | Empty object | 10 |
| POST | `/apply` | `proof`, `action:activate\|pause`, `confirmed:true`, `spend_acknowledged` true exactly for activation | 5 |

The browser cannot choose provider resources or write internal receipts. There are no HTTP progress, finish, reconcile, reset, resume-command, cleanup or budget endpoints. Resuming a successfully paused campaign is a new explicit activation command, subject to all current activation checks.

Inspection reads configured and effective campaign status for the exact saved campaign ID and account. When eligible for activation, it checks the original modeled campaign, ad set, ad, creative and image relationships, budget, schedule, destination, copy and targeting. Activation requires a PAUSED campaign and PAUSED/ACTIVE children. Known disapproval, billing restrictions, delivery issues and nonempty review feedback block activation. `PENDING_REVIEW`, `IN_PROCESS` and `PREAPPROVED` ad effective states can still be observed; **no Meta policy approval is asserted**. Activation may trigger review and does not guarantee delivery. Unmodeled account settings and creative enhancements are not certified.

The five-minute HMAC proof binds actor, funnel, campaign, local fingerprint and normalized provider observation. Apply refreshes access and exact details, validates every intended status change with `execution_options:[validate_only]`, rereads the graph, checks the connection and claims one SQL command. The preclaim deadline is 75 seconds; each write has an 85-second pre-send deadline. Refreshing, errors and workspace/access changes discard the UI proof and both activation confirmations. Pause has a separate single confirmation, without spending authorization.

Activation changes only currently PAUSED children, in order **ad, ad set, campaign**; the campaign is always last. After a confirmed prior pause, already ACTIVE children are not rewritten. Each request is a separate POST to the exact saved resource with only `status:ACTIVE`; pause sends only `status:PAUSED` to the campaign. The adapter uses the existing fixed Graph host/version, bearer token, HMAC app-secret proof, denied redirects, bounded responses and ten-second timeout. No budget, schedule, creative or targeting mutation occurs.

Before each write, KORLIX repeats local ownership/tier/connection checks. Activation also repeats review/content/schedule eligibility and full provider graph inspection against statuses confirmed so far, then repeats the local fingerprint/connection after that read. A concurrent local edit, revoked access, unexpected status, provider issue or timeout stops later writes. Meta reads and writes are separate: they cannot prevent an external account edit racing after the last check. Avoid editing the campaign in another tool during confirmation. Provider eventual consistency can make a successful child change appear stale on the next read, stopping the command with the parent still paused. That conservative behavior and real Graph response shapes remain part of deferred provider acceptance; no retry or reconciliation is automatic.

New private RLS table `korlix_funnel_meta_commands` stores at most 1,000 serialized commands per campaign, with one UNKNOWN slot, ordered intended steps and per-step accepted status receipts. UNKNOWN is saved before any write. Each receipt is persisted before the next step. The record is CONFIRMED only after every receipt is present. Failure, lost response, malformed receipt, failed receipt storage or lost completion leaves UNKNOWN and blocks **all** later KORLIX commands, including pause. A status observation cannot settle it. Late entitlement revocation still permits internal receipt storage but denies subsequent private reads and new writes. No automatic compensation, retry, continuation or command deletion is available.

An uncertain command may have enabled the campaign even when its last receipt was lost. The interface shows partial receipts and tells the owner that ads may be spending. Inspect and control delivery directly in **Meta Ads Manager**. That fallback also applies when account access, Enterprise access, platform gates or journal capacity prevent KORLIX pause. Pause remains available with stale drafts, archived plans, paused landing pages or no Page selection when those other requirements are met. Local edits, archive and reporting associations never change Meta delivery. Accepted pause is historical receipt, not a guarantee that prior delivery or charges have finished posting.

Meta's average daily budget may vary by day; the planned total is not a hard cap. Activating requires separate unchecked confirmations for the saved campaign and spending under its original average daily budget/schedule. The interface shows original identity, budget, schedule, expandable content details, observed configured/effective states, command time and partial receipts. It does not label the ad approved.

Migration `20260924000946_funnel_meta_controls.sql` is additive: one new service-only invoker RPC `korlix_funnel_meta_controls_v1(uuid,text,uuid,jsonb)` with fixed `public,pg_temp` search path and one private journal. It reuses K184's coherent ownership/preparation locks. No existing table or RPC is replaced. Browser roles have neither table CRUD nor function execution. Ordered steps, prefix receipts, exact resource identities, full completion, sequence capacity and uncertainty are enforced by the RPC and constraints.

Deployment order: chapter-specific approval, public source, exact migration, backend release/deploy and anonymous verification, then frontend release/deploy and verification. Migration is compatible with running K184. Retain creation/command history on service rollback. Do not delete uncertain records to bypass the gate; use Meta directly and a forward fix. Keep both services' auto-deploy disabled.

Local checks: 54 backend cases (28 new controls/SQL/provider cases and 26 K184 regressions) and 31 Flutter cases (13 new controls cases and 18 creation/workspace regressions). These cover serialization, replay, two confirmations, exact status-only bodies, partial/lost receipts, validation failures, drift between writes, current account access without Page, late access loss and desktop/mobile enlarged text. No live account, real ad/spending or owner A–G acceptance is established by these checks.

Contract references reviewed September 24, 2026: official Meta Python Business SDK [ad updates/status/feedback](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/ad.py), [ad set updates](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/adset.py) and [campaign updates](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/campaign.py). The SDK lists status updates and validate-only execution options on each node; local transports remain dependency-free. Supabase [database function security](https://supabase.com/docs/guides/database/functions) and [changelog](https://supabase.com/changelog) were refreshed; no relevant breaking change was found for this private invoker RPC.

## K186 — Meta average daily budget changes

K186 extends **Meta campaign controls** with a reviewed change to the exact ad set recorded by K184. It displays the original amount separately from the latest confirmed budget. Input is $1.00–$10,000.00 USD in integer cents, requiring both a specific amount confirmation and a spending acknowledgment. The range is a KORLIX planning limit; Meta can reject amounts that do not meet account/ad-set minimums. Opening and refreshing remain local reads; **Review budget change** explicitly reads Meta. Editing, refresh, errors and workspace/access changes discard proofs and confirmations; delayed private responses are suppressed.

The new default-OFF `KORLIX_META_BUDGET_ENABLED=true` also requires existing Meta configuration, exact Graph v26.0 and `KORLIX_META_CONTROLS_ENABLED=true`. Keep every credential and provider flag unchanged during code release. Two owner/Enterprise/no-store routes extend `/api/funnels/:id/campaigns/:campaign_id/meta-controls`:

| Method | Suffix | Exact input | Owner rate/minute |
| --- | --- | --- | ---: |
| POST | `/budget-preview` | daily_cents | 10 |
| POST | `/budget-apply` | proof, daily_cents, confirmed:true, spend_acknowledged:true | 5 |

The browser cannot supply account/ad-set IDs or internal receipts. Read results add `budget_enabled` and `managed_budget` with `daily_cents`, `original_daily_cents`, `command_id` and `confirmed_at`. Only a CONFIRMED budget command advances the managed amount; otherwise it comes from original creation. The original plan, review snapshots and creation record remain immutable. Activation/resume inspections use the latest confirmed amount, while saved-content checks still compare original creation with the local draft. A receipt is historical acceptance, not a current Meta observation or billing guarantee.

Preview proves current active USD account/token access, the original campaign/account, exactly one ad set with the saved ID and campaign relationship, ACTIVE/PAUSED configured statuses and the exact managed daily budget. It rejects campaign-level budgets, lifetime budgets, ad-set budget sharing and enabled budget schedules. Schedule flags must explicitly be false; missing or unsupported fields fail closed. Pagination/additional ad sets and external amount changes also reject review. Reductions can proceed without Page selection or current content reviews, including stale/archived drafts, but still require this exact budget/account proof. Increases additionally require current reviews, original account/Page/content, an unexpired saved schedule, Page advertising permissions and the full matching campaign/ad-set/ad/creative graph with no reported disapproval/delivery issues. Policy approval is never asserted.

Both changes retain the saved delivery status and schedule. The sole mutation is a POST to the saved ad-set node with `daily_budget` as integer USD cents; no status, creative, targeting or schedule is sent. Validate-only uses the same amount with `execution_options:[validate_only]`. Existing fixed Graph origin/version, bearer authorization, app-secret proof, denied redirects, bounded responses and ten-second per-request timeouts remain. The five-minute HMAC proof binds actor/funnel/campaign, local fingerprint, observed status/budget/graph and proposed amount. Apply rechecks the exact observation before and after validation, then claims a serialized command. After claim it rereads local access/fingerprint, provider details and the connection again before sending. Preclaim deadline remains 75 seconds and pre-send 85 seconds. External tools can still race between provider reads and writes; avoid simultaneous edits.

Migration `20260924010035_funnel_meta_budget.sql` extends the existing private RLS journal with nullable integer `daily_cents`, a budget action, a single `budget` step and exact numeric progress receipt constraints. It replaces `korlix_funnel_meta_controls_v1(uuid,text,uuid,jsonb)` with the same invoker/search-path/service-only execution contract. No new table, browser policy, dependency or catalog is added. Status and budget commands share the same 1,000-command sequence and single UNKNOWN slot, so competing proofs dispatch at most one command. Existing campaign/sequence indexes support the bounded latest-confirmed-budget query.

UNKNOWN is persisted before the write. The exact ad-set/amount receipt is saved before completion. A lost response, malformed receipt, failed progress storage or failed completion leaves UNKNOWN and does not advance the managed amount. All subsequent status/budget commands remain blocked. There is no automatic retry, compensation or settlement; observing a later budget/status cannot prove whether the earlier request is settled. Late entitlement loss still permits internal receipt storage, then denies private reads and further writes. Use Meta Ads Manager for uncertain outcomes and delivery control. Never erase history to authorize another command.

An average daily budget is not a hard total cap. Changing it can affect spending on an active campaign; lowering it does not reverse earlier charges or guarantee a lower bill that day. This release does not perform live advertising operations or certify provider acceptance. Budget field availability and validate-only/response shapes remain subject to deferred account acceptance, especially missing schedule flags or provider normalization.

Release under Ricardo's standing KORLIX development authorization: review and test exact source, publish it, apply the migration once, deploy/verify backend, then deploy/verify frontend. Preserve auto-deploy off and all advertising gates. The migration is compatible with K185 while gates remain off; open old proofs become stale. Once budget commands exist, an older K185 UI can reject budget history and an older activation adapter expects the original amount. Retain the schema/receipts, use Ads Manager and prefer a forward fix rather than restoring the old RPC. With gates disabled and no budget commands, the recorded K185 commits are service rollback targets.

Local verification includes actual PGlite schema/role tests and Express flows, concurrent status/budget claims, partial/lost storage results, proof replay and amount tampering, stale-draft reductions, postclaim drift/deadlines, late access loss, exact Meta request bodies and blocked unsupported budget modes. Flutter tests cover parsing, both confirmations, changed input, unknown results, failures, late response suppression and real-font 1400/390/320px layouts including 1.3 text scale. Results are recorded in the K186 release checkpoint; owner acceptance A–G and live provider acceptance remain deferred.

Contract references inspected September 24, 2026: official Meta Python Business SDK [ad set fields/updates](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/adset.py) and [campaign budget fields](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/campaign.py). SDK files confirm `daily_budget`, budget schedule/sharing flags and validate-only update parameters; they do not prove live account response semantics. Rendered Marketing API reference returned HTTP 429; no browser fallback was used. Supabase [function security](https://supabase.com/docs/guides/database/functions) and the [changelog](https://supabase.com/changelog) were refreshed; listed recent breaking changes do not affect this private invoker RPC or existing public journal.

## K187 — Campaign inquiry attribution

K187 adds a **Campaign inquiry attribution** report for each Meta, Google or Other campaign plan. It separates link-associated inquiries from visitor-editable tag-only matches over 7, 30 or 90 UTC calendar dates, including today. Daily rows reconcile to the displayed totals. A third count identifies link-associated inquiries whose submitted source/campaign tags differ; it is a subset of the link count. An inquiry associated with another recognized link is excluded from this campaign's tag-only count. Deleted inquiries disappear through the existing cleanup cascade. Counts are submissions, not unique people, sales, verified ad clicks or platform conversions. Nothing is backfilled.

Opening the report is read-only. **Create attribution link** persists one stable, unguessable public share code for the exact campaign. Repeated/concurrent requests return the same link. Creation requires current Enterprise ownership, a published page and a nonarchived campaign. The recognized link is displayed for explicit copying. Existing tracking links, campaign snapshots, ad destinations and manual/provider reports are unchanged; using those older links continues tag-only reporting. Merely creating a link does not edit a provider resource. Archiving a local plan retains its link association; pausing the page blocks new inquiries.

At the public page GET, a valid `kl` code is resolved against the exact published funnel. Its association is bound into the existing browser-cookie/form HMAC token. Invalid, duplicated, foreign-funnel or absent codes carry no association. Browser POST fields cannot add or replace it. Guided steps and validation redisplay retain the same bound token; the existing exact-review proof, consent, honeypot, nonce, expiry and version checks remain. Codes are public sharing identifiers, not user credentials or proof of where the visitor clicked. A link may be copied elsewhere and generate a valid association there.

Capture uses a service-only transaction under the original funnel lock: revalidate the code/funnel, execute the original lead/CRM/follow-up capture, then insert the inquiry evidence. If evidence insertion fails, the whole capture rolls back. Concurrent/repeated submissions preserve the original inquiry association. A preexisting untracked inquiry cannot gain evidence on retry; an existing association cannot move. Cleanup tombstones suppress resurrection. No receipt or public response contains campaign evidence, contact data or submitted fields. No pixel, click ID, third-party script, conversion upload, IP/user-agent storage, new consent category or ad-platform request is introduced.

API under `/api/funnels/:id/campaigns/:campaign_id/attribution`: owner GET accepts only optional `days=7|30|90` (default 30; 30 reads/minute); POST `/link` accepts exactly `{days:7|30|90}` (5 requests/minute). All private responses are no-store and enforce current Enterprise ownership. The report returns `source:campaign_link_attribution`, explicit `provider_verified:false`, exact campaign/funnel IDs, the UTC window, daily rows/totals and an optional link. Flutter verifies scope, dates, window length, row totals and link identity, clears stale private results after errors/access/workspace changes, and suppresses late results.

Apply `supabase/migrations/20260924013755_funnel_campaign_attribution.sql`, then `supabase/migrations/20260924015359_funnel_campaign_attribution_grants.sql`, before the backend. The second migration explicitly removes hosted default service-role UPDATE/DELETE grants before granting SELECT/INSERT; it preserves the already-applied first migration. It adds two private RLS tables with no browser policies/grants, and `korlix_funnel_attribution_v1(uuid,text,uuid,jsonb)`, SECURITY INVOKER with fixed public,pg_temp search path. Only service_role has SELECT/INSERT and RPC execution; table UPDATE/DELETE are not granted. Inquiry deletion cascades evidence. No previous function is replaced. Existing owner cleanup remains the way to remove inquiry data.

Actual SQL/HTTP tests cover strict input/role boundaries, stable link creation, tampered and cross-funnel codes, independent tag evidence, guided consent/review, HMAC tampering, concurrent/lost-response replay, rollback of CRM/inquiry/workflow, no backfill/reassignment, UTC windows, cleanup/tombstones, republishing and entitlement loss. Flutter checks cover report reconciliation, create/copy, windows, errors, delayed results, access/scope loss and real-font desktop/mobile layouts. Local mocks and production anonymous checks do not establish deferred owner acceptance or live provider conversion acceptance.

Rollback: frontend then backend to K186, retaining both additive tables and all evidence. Old backend versions can still accept ordinary inquiries but do not record new link evidence, so document that coverage gap or prefer a forward fix. Do not label old inquiries as verified to fill it. Remaining work includes provider-specific conversion attribution/acceptance and reporting reconciliation; K187 establishes first-party link evidence only. Current official [Supabase function guidance](https://supabase.com/docs/guides/database/functions) and [changelog](https://supabase.com/changelog) were reviewed; no relevant public invoker-RPC breaking change was identified. Exact release results are retained in the K187 checkpoint.
