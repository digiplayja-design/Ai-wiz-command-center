# Live Studio customer checkpoint — October 1, 2026

This supersedes the earlier single-channel pilot checkpoint. The user's goal is a service sold to customers. The application owner's personal YouTube channel is not required for configuration; each customer connects their own. A dedicated authorized test channel is needed later for real streaming acceptance.

## First customer test and live activation blocker

At 23:05 UTC October 1, the first customer confirmed their channel. A bounded initial acceptance allowance was issued (one rehearsal and one 15-minute broadcast). The private rehearsal completed. The customer initiated the live attempt at 23:12 UTC; it failed during YouTube setup before any destination event or encoder startup. Five generation calls were dispatched for rehearsal and three for the failed live attempt; those usage records must be retained.

A read-only diagnostic inside the existing Render worker confirmed channels.list HTTP 200 with the expected channel and liveBroadcasts.list HTTP 403 with reason liveStreamingNotEnabled. No broadcast or paid generation was started by that diagnostic and no credentials or raw provider bodies were printed. The user must enable YouTube Live through YouTube Studio → Create → Go live for the same channel. First activation may take up to 24 hours. OAuth channel verification does not enable streaming. Official guidance: https://support.google.com/youtube/answer/2907883.

The follow-up fix classifies provider failures into fixed actionable messages and logs only the constrained operation/status/reason. YouTube setup now precedes paid research/speech; a later generation failure still cleans up the worker-created broadcast. Direct-live broadcasts explicitly disable monitorStream because YouTube otherwise defaults it on and requires a testing transition. Existing channel/run authorization, unlisted consent and cleanup ownership guards remain. A new live acceptance run must wait for activation and a deliberate customer start.

The failed show now displays the confirmed activation reason. One additional 15-minute test was granted through October 3 at 23:08 UTC. The two original run records and all eight generation dispatches were preserved. Grant period extension also carried both receipt period-end pins forward because usage sums match exact period endpoints; extending only the grant would incorrectly reset accounting. Production verification shows 900 broadcast seconds and 200 generation calls remaining, zero remaining rehearsals, and no active show. The bounded top-up was guarded against changed accounting, active work and repeat execution. Focused validation passed 45 tests across adapter, runtime, existing SQL/HTTP and real FFmpeg fixtures; no real broadcast was started by the fix.

## Completed and live

- Backend production commit: f7a87bf8a126b1bde6953ee39233a3f3c669a87f (same runtime as 88e0c8a). Activation deploy dep-davc77ekemhc73dsoptg live October 1 at 20:34:34 UTC.
- Worker srv-davc6anavr4c73bdrqog, korlix-live-studio-worker: Docker, Ohio, 1c-2g, one instance, US$25/month, auto-deploy off. Blueprint exs-dav9d6jncjis73amohg0. Initial deployment dep-davc6avavr4c73bdrrh0 from f7a87bf became live at 20:32:49 UTC.
- Frontend production commit: f8595ae45fff98b60dc1b64b75cf395d82a938f0. Render deploy dep-davbfuad0e5s73fb9mvg live October 1 at 19:45:49 UTC.
- Applied Supabase migrations: 20261001180353_live_studio_customer_workspaces, 20261001180428_live_studio_connections and 20261001194226_live_studio_connection_retention.
- Seven feature tables have RLS and no anonymous/authenticated direct grants. RPCs are service-only. Production service-role workspace/connection reads passed, while direct auth.users SELECT remains denied. The only feature advisor notice is the expected informational RLS-with-no-policies entry for intentionally server-only tables.
- Disconnect and known revocation now erase YouTube-derived metadata/history as well as grants. Daily idle verification refreshes channel metadata; credential-independent maintenance purges unverified data at 28 days and expires OAuth attempts. Temporary execution fences and late-write guards protect stopping streams. Non-YouTube usage accounting and independently entered show settings remain.
- Production service-role maintenance/workspace checks passed; client roles cannot execute maintenance, and service_role still cannot read auth.users directly. Before activation, production contained zero Live Studio shows, connections and OAuth attempts.
- The customer UI requires explicit policy agreement before Google launch and provides accessible KORLIX/Google/YouTube policy links. Public privacy and terms now describe YouTube API use and data deletion.
- Post-deploy health, app, privacy, terms and compiled bundle checks passed (200); workspace remains protected (401). After activation, an OAuth launch without its required ticket returns 400 instead of administrator-setup 503, confirming the API loaded its configuration. This is not a Google credential-validity test. The live bundle contains Continue to Google. Browser verification confirmed the published policy section.
- 79 focused backend tests and 18 frontend tests passed. Real local FFmpeg fixtures were used; no paid generation or real YouTube broadcast was performed. Flutter web release build and Blueprint schema validation passed. PGlite exercises state/transaction behavior, not simultaneous independent PostgreSQL sessions.

Implementation details and configuration are in LIVE_STUDIO.md. Local and GitHub trees were checked for byte identity before Render deployment.

## Worker and external setup

The user approved the proposed US$25/month Render worker and YouTube setup on October 1 at 12:40 Eastern, then authorized dashboard use. Do not ask for that same cost or browser approval again.

At 16:29 Eastern the user replied saved after entering Google credentials directly in Render. Both expected environment-variable names were confirmed without revealing values. The canonical 32-byte base64 LIVE_STUDIO_TOKEN_KEY was preserved. The worker Blueprint references all six shared secrets from the existing API using fromService.envVarKey; it does not recreate or manage the API. The already-approved US$25/month worker was created after confirming zero connected channels, active/queued YouTube shows and ready workers. The API's LIVE_STUDIO_YOUTUBE_ENABLED is now true and its activation deployment is live.

Worker identity 1dda1ad1-bdc8-4b95-98ed-d73997b1d3d0 announced successfully; updated_at advanced from 20:32:58 to 20:33:38 UTC, ready_until stayed in the future and run_id remained null. Startup logs reported live without configuration/readiness errors. No test job, paid generation or broadcast was started. The worker dashboard is https://dashboard.render.com/worker/srv-davc6anavr4c73bdrqog. The environment update itself triggered an API deploy; a subsequent explicit deploy queued a second identical deployment. Both completed; check list_deploys after future environment updates before triggering another deployment.

Google Cloud Console showed Site Unavailable in the assisted browser after one reload. There was no bot-verification evidence or usable login flow. Do not repeat login prompts or claim the user's own browser sign-in shares this browser's session. The concrete independent setup guide is LIVE_STUDIO_GOOGLE_SETUP.md; credentials should be entered directly into Render, never chat.

Next required work:

1. Connect a dedicated authorized test channel through the product's customer OAuth flow. This verifies the Google client, enabled API, exact callback and consent/test-user setup, which could not be independently checked in Google Cloud. Connecting alone does not broadcast.
2. Confirm the returned channel identity, then run authorized 15/30-minute unlisted acceptance, including controls, app closure/reopen, provider failure, disconnect, revoke and worker termination. Initial capacity is one simultaneous encoder slot.
3. Keep worker deployments idle and preserve the shared key. Additional encoder instances need separately approved capacity.
4. Implement verified subscription billing, plan decisions, renewals/revocation, reservation reconciliation and operating limits. Current customer grants are explicit service-managed records; no customer checkout or commercial prices have been added.
5. Finish Google verification and YouTube required-functionality review before broad sales. Current 80-character title, fixed description and unlisted-only acceptance controls are documented review items. External Testing grants expire after seven days.

Operational notes: the retention sweep runs while the API is running and catches up on restart; real provider revocation/outage tests remain. The first two migration connector requests returned expired-request-state errors and were verified unapplied. A call using functions.exec yield_time_ms 60000 succeeded in 38 seconds and production checks confirmed the schema. Early yielding may have contributed to the earlier connector failure; that cause was not independently established.

Local continuity: the prior /workspace/scratch/4a47074afad4 checkout expired during this turn. Active source trees were retained and git metadata recovered under /workspace/scratch/5eb212b18031/live-studio-git-recovery and live-studio-git-recovery-ui. Use live-studio-activation-backend and live-studio-activation-frontend. The old node_modules symlink and Flutter SDK path may now be unavailable; restore dependencies before another local test run. Release contents were checked for byte identity against GitHub before deployment.

The main app is at https://www.korlixdeveloper.com/app/ → Tools → Live Studio.

Estimated remaining: roughly 2–4 development weeks for a customer-ready MVP, plus external approval time. The prior 2–4 development days applied only to the single-channel pilot.
