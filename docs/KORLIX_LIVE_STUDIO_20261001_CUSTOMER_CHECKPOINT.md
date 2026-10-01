# Live Studio customer checkpoint — October 1, 2026

This supersedes the earlier single-channel pilot checkpoint. The user's goal is a service sold to customers. The application owner's personal YouTube channel is not required for configuration; each customer connects their own. A dedicated authorized test channel is needed later for real streaming acceptance.

## Completed and live

- Backend production commit: 88e0c8a90555cc05014f480d0b9e408638c532f9. Render deploy dep-davbgkpsrm7s73bbtij0 live October 1 at 19:45:55 UTC.
- Frontend production commit: f8595ae45fff98b60dc1b64b75cf395d82a938f0. Render deploy dep-davbfuad0e5s73fb9mvg live October 1 at 19:45:49 UTC.
- Applied Supabase migrations: 20261001180353_live_studio_customer_workspaces, 20261001180428_live_studio_connections and 20261001194226_live_studio_connection_retention.
- Seven feature tables have RLS and no anonymous/authenticated direct grants. RPCs are service-only. Production service-role workspace/connection reads passed, while direct auth.users SELECT remains denied. The only feature advisor notice is the expected informational RLS-with-no-policies entry for intentionally server-only tables.
- Disconnect and known revocation now erase YouTube-derived metadata/history as well as grants. Daily idle verification refreshes channel metadata; credential-independent maintenance purges unverified data at 28 days and expires OAuth attempts. Temporary execution fences and late-write guards protect stopping streams. Non-YouTube usage accounting and independently entered show settings remain.
- Production service-role maintenance/workspace checks passed; client roles cannot execute maintenance, and service_role still cannot read auth.users directly. Before activation, production contained zero Live Studio shows, connections and OAuth attempts.
- The customer UI requires explicit policy agreement before Google launch and provides accessible KORLIX/Google/YouTube policy links. Public privacy and terms now describe YouTube API use and data deletion.
- Post-deploy health, app, privacy, terms and compiled bundle checks passed (200); workspace remains protected (401), and unconfigured OAuth launch reports administrator setup (503). The live bundle contains Continue to Google. Browser verification confirmed the published policy section.
- 79 focused backend tests and 18 frontend tests passed. Real local FFmpeg fixtures were used; no paid generation or real YouTube broadcast was performed. Flutter web release build and Blueprint schema validation passed. PGlite exercises state/transaction behavior, not simultaneous independent PostgreSQL sessions.

Implementation details and configuration are in LIVE_STUDIO.md. Local and GitHub trees were checked for byte identity before Render deployment.

## Worker and external setup

The user approved the proposed US$25/month Render worker and YouTube setup on October 1 at 12:40 Eastern, then authorized dashboard use. Do not ask for that same cost or browser approval again.

The API already had its Supabase and OpenAI settings. Its new canonical 32-byte base64 LIVE_STUDIO_TOKEN_KEY and LIVE_STUDIO_PUBLIC_ORIGIN are installed, with LIVE_STUDIO_YOUTUBE_ENABLED=false. Do not replace the installed key. The dedicated Google client ID and secret are still absent. The worker Blueprint now references all six shared secrets from the existing API using fromService.envVarKey; it does not recreate or manage the API. No worker has been created and no additional worker billing has started. The Render API Environment page is the useful next settings destination; an older unsaved Blueprint form may still show the previous six manual fields until refreshed.

Google Cloud Console showed Site Unavailable in the assisted browser after one reload. There was no bot-verification evidence or usable login flow. Do not repeat login prompts or claim the user's own browser sign-in shares this browser's session. The concrete independent setup guide is LIVE_STUDIO_GOOGLE_SETUP.md; credentials should be entered directly into Render, never chat.

Next required work:

1. Configure the dedicated business application's Google OAuth client and enable YouTube Data API, consent details/scopes and exact callback. Install client ID/secret on the existing API. Preserve the installed encryption key. Do not borrow calendar refresh tokens or ask for secrets in chat.
2. Create the approved worker after those prerequisites are present, then enable YouTube on the API and verify readiness. New instances support separate customer jobs but the initial approved single instance supplies one encoder slot.
3. Confirm a dedicated test channel through the product's customer OAuth flow; run 15/30-minute unlisted acceptance, including controls, app closure/reopen, provider failure, disconnect, revoke and worker termination.
4. Implement verified subscription billing, plan decisions, renewals/revocation, reservation reconciliation and operating limits. Current customer grants are explicit service-managed records; no customer checkout or commercial prices have been added.
5. Finish Google verification and YouTube required-functionality review before broad sales. Current 80-character title, fixed description and unlisted-only acceptance controls are documented review items. External Testing grants expire after seven days.

Operational notes: the retention sweep runs while the API is running and catches up on restart; real provider revocation/outage tests remain. The first two migration connector requests returned expired-request-state errors and were verified unapplied. A call using functions.exec yield_time_ms 60000 succeeded in 38 seconds and production checks confirmed the schema. Early yielding may have contributed to the earlier connector failure; that cause was not independently established.

Local continuity: the prior /workspace/scratch/4a47074afad4 checkout expired during this turn. Active source trees were retained and git metadata recovered under /workspace/scratch/5eb212b18031/live-studio-git-recovery and live-studio-git-recovery-ui. Use live-studio-activation-backend and live-studio-activation-frontend. The old node_modules symlink and Flutter SDK path may now be unavailable; restore dependencies before another local test run. Release contents were checked for byte identity against GitHub before deployment.

The main app is at https://www.korlixdeveloper.com/app/ → Tools → Live Studio.

Estimated remaining: roughly 2–4 development weeks for a customer-ready MVP, plus external approval time. The prior 2–4 development days applied only to the single-channel pilot.
