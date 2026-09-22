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
