# KORLIX Live Studio customer foundation

Live Studio is a service for customers to create AI-hosted shows on their own YouTube channels. K-Nova hosts, with an optional Analyst voice. The application owner's personal channel is not part of the product configuration. An authorized test channel is still needed for real broadcast acceptance.

## Implemented scope

- Every authenticated customer can manage their own saved shows and channel connection. Generation requires an explicit server-managed Live Studio allowance.
- Each customer reviews and confirms their own YouTube channel after Google authorization. Start confirmation names that channel and pins its connection ID and revision; changing the connection during confirmation causes the start to fail safely.
- Rehearsals generate a private MP4 of up to 60 seconds. Broadcasts are explicitly confirmed, unlisted, and bounded to 15 or 30 minutes. A requested start can be scheduled one minute to seven days ahead, within the current allowance period.
- Durable run receipts reserve rehearsal count, broadcast seconds and generation capacity atomically. Rehearsals reserve 10 generation calls and broadcasts 200. Cancellation before a worker claims a run releases period reservations; the daily-start receipt remains. After claim, capacity remains reserved conservatively, including failures and uncertain provider outcomes. These are allowance reservations, not a payment ledger or a claim of actual dollar cost.
- One customer can have one executing show. A future queued show does not occupy an execution slot. Different worker instances can claim different customers independently. The approved initial worker has one encoder slot; simultaneous broadcasts require separately approved additional capacity.
- Read, replay, end, disconnect and deletion do not depend on an active generation allowance. A customer must wait for a cancelled worker to stop before deleting its show or occupying the same execution slot.
- YouTube setup can remain unconfigured while customers prepare shows. The UI reports this accurately and disables broadcast starts.

The current visual is a branded graphic stage with captions, sources and an active speaker. Photorealistic avatars, lip sync, public broadcasts, recurring schedules and 24/7 operation remain outside this release. No commercial prices or checkout have been invented.

## Access and allowances

`korlix_live_studio_grants` is service-only. It contains an explicit enabled flag, period bounds, daily-start cap, rehearsal count, broadcast seconds and generation capacity. A billing integration must write verified entitlements here; user-editable metadata and generic tier names never grant Live Studio usage. The existing appointment-payment integration is not subscription billing for this product.

For continuity, the existing server-verified developer ID allowlist can seed one bounded development grant: 30 days, three starts per rolling 24 hours, 30 rehearsals, 90 broadcast minutes and 5,000 reserved generation calls. This grant is created only if absent. Reading the workspace never renews an expired grant or re-enables a revoked one. These are internal testing limits, not advertised customer plans.

Reservation records survive show deletion. Workers recheck account availability, allowance validity and the exact channel connection before claiming scheduled work and before further paid calls. Dispatch is recorded before a provider call and completion or uncertainty afterward. No uncertain paid generation is automatically retried.

## Connections and security

`connections.mjs` implements authenticated initiation, a single-use hashed launch ticket, a secure HttpOnly SameSite=Lax browser cookie, hashed state, S256 PKCE, server-side code exchange and owner-authenticated confirmation. The callback and launch origins are fixed application configuration; the client validates the exact HTTPS launch origin and path.

Google credentials are application-wide; authorization grants belong to individual customers. Grants use AES-256-GCM with a separate 32-byte key and versioned ciphertext bound to owner, connection ID and channel ID. Secrets, leases and storage paths are excluded from customer responses. Refresh writes use their own fenced lease, and a disconnect or changed connection invalidates a refresh result before it can be used.

Disconnect removes stored authorization credentials and YouTube-derived channel metadata/history, cancels queued shows and requests active streams stop. Internal usage receipts and independently entered show settings remain. A temporary non-public channel hash keeps a stopping encoder's slot fenced until it finishes or its lease expires; stale worker writes cannot restore purged metadata. Google revocation is attempted after the local disconnect; if it cannot be confirmed, the UI explains how to remove access in Google Account permissions. Existing YouTube videos are not removed by deleting a KORLIX show or connection.

API maintenance verifies idle grants and refreshes channel metadata daily under a durable lease. Temporary provider failures back off without extending the last successful metadata check. Known invalid grants are purged; connections not verified for 28 days are purged by a credential-independent sweep, including when Google setup is unavailable. Expired OAuth attempts also lose their secrets and metadata without requiring further customer activity. These controls support the disclosed retention deadlines; real Google revocation and outage acceptance remain required before broad release.

All Live Studio tables have RLS enabled and no grants to anonymous or authenticated clients. Exposed RPCs are SECURITY INVOKER and executable only by service_role. Supabase's service role does not have SELECT on auth.users. A narrow SECURITY DEFINER boolean helper in the unexposed `korlix_live_private` schema checks only account existence and ban expiry; it has an empty search path, fully qualified object names and no client execution grants. It grants no access to auth records.

Workers use a 45-second show lease, a five-second control heartbeat and a distinct worker UUID for each encoder slot. Readiness expires after 35 seconds. Cancelled jobs retain their slot until the worker finishes or its lease expires, preventing overlapping encoders. Account deletion and expired leases release orphaned worker slots. Queue timestamps are refreshed on every run, so a newly started old draft does not expire based on its creation date.

## Media and cleanup

The stream prepares one segment ahead. Each segment retains the research brief that produced its speech, even if another audience question is researched concurrently. Questions are filtered and moderated, then researched before a host response. Pauses and generation gaps use original synthesized music; pause time counts toward the configured duration.

The adapter verifies the token identifies the reserved YouTube channel before creating any event, forces unlisted visibility and marks synthetic media. Encoder failures and an incomplete final drain are reported as failures. Encoder stderr is suppressed because it can include stream keys.

End aborts pending operations and stops the encoder. A run-local cached token permits only the adapter's own created broadcast to be read and completed during cleanup, without reopening a revoked grant. Revocation can still make Google reject cleanup. The show reports unconfirmed YouTube completion rather than claiming success; YouTube auto-stop is also enabled. Real-platform timing remains an acceptance requirement.

## Deployment and application configuration

Apply the customer workspace, connection and connection-retention migrations in order, then deploy the backend and frontend release branches. The v1 RPC delegates to v2 during deployment overlap, so old clients cannot bypass customer allowances.

The approved worker Blueprint is `deploy/live-studio-worker.render.yaml`: one Docker background worker in Ohio on Render's 1c-2g plan. The user approved the proposed US$25/month worker and YouTube setup on October 1, 2026 at 12:40 Eastern and subsequently authorized Render dashboard use. That approval remains recorded. No new worker was created before the customer architecture correction.

Configure these values on the existing API. The worker Blueprint references the API's three Live Studio secret settings with `fromService.envVarKey`, so the encryption key and OAuth application cannot diverge during initial setup:

| Setting | Purpose |
| --- | --- |
| `LIVE_STUDIO_YOUTUBE_CLIENT_ID` | Web OAuth client for the Live Studio application |
| `LIVE_STUDIO_YOUTUBE_CLIENT_SECRET` | That client's secret |
| `LIVE_STUDIO_TOKEN_KEY` | Canonical base64 encoding of 32 cryptographically random bytes, identical on API and worker |
| `LIVE_STUDIO_PUBLIC_ORIGIN` | `https://chee-chai-chee-backend.onrender.com` |
| `LIVE_STUDIO_YOUTUBE_ENABLED` | `true` after application setup |

The worker also references the API's existing Supabase URL, service-role key and OpenAI API key. The referenced API remains outside the worker Blueprint and is not recreated or managed by it. There is no `LIVE_STUDIO_BROADCAST_OWNER_ID` or global YouTube refresh token in the new design. Use secret settings, never source control or chat, for credentials. Generate the canonical 32-byte base64 encryption key only once; replacing an existing key would make its stored grants unreadable. Coordinate any later credential changes across service deployments while streams are idle.

Use a dedicated Live Studio Google OAuth client, enable YouTube Data API v3, configure the consent screen and register this exact authorized redirect URI:

`https://chee-chai-chee-backend.onrender.com/api/live-studio/connect/youtube/callback`

The application requests `https://www.googleapis.com/auth/youtube.force-ssl` for the necessary broadcast and live-chat operations. Google may require verification before broad customer access. Each customer's channel must independently qualify for live streaming. App authorization, API quotas, actual unlisted behavior and channel eligibility must be checked with Google before sales claims.

Import the updated Blueprint only after app secrets are configured. It is independent of the existing API/static services, uses no persistent disk or Redis, and keeps auto-deploy off so deployments can be performed while streams are idle. Initial CPU/memory sizing must be validated during a full-duration broadcast.

The step-by-step operator handoff is [LIVE_STUDIO_GOOGLE_SETUP.md](LIVE_STUDIO_GOOGLE_SETUP.md). On October 1 the assisted browser could not load Google Cloud Console after one recovery attempt. The API encryption key and public origin are installed, with YouTube disabled while its dedicated OAuth client ID and secret are missing. No worker or broadcast has been started.

## Validation and remaining release work

Automated checks exercise actual migrations in PGlite, OAuth provider fixtures, owner and channel isolation, reservations, revocation during token refresh, worker fencing, source binding, failed encoder drains, emergency controls after allowance expiry and real local FFmpeg output. Flutter checks cover trusted launch URLs, exact channel confirmation, dynamic allowances and narrow layouts. These checks do not call paid generation providers or start YouTube broadcasts.

Before customer-ready release:

1. Complete Google application setup/verification and install shared secrets; activate the already-approved Render worker.
2. Use a dedicated authorized test channel for 15- and 30-minute unlisted streams. Verify actual visibility, AI disclosure, audio/caption/source timing, iPad reopen, pause/skip/questions/end, provider timeout, disconnect and worker/network failure.
3. Implement verified subscription billing, customer plan limits, renewal/revocation and reservation reconciliation. Establish prices from observed compute, provider and quota costs.
4. Validate sustained CPU/memory, channel/API quotas, operational monitoring and the number of simultaneous customers supported by purchased capacity.

Estimated remaining: roughly **2–4 development weeks for a customer-ready MVP**, plus external approval time. The earlier 2–4 day estimate covered only a single-channel pilot and does not apply to this SaaS goal.

## References

- https://developers.google.com/youtube/v3/guides/auth/server-side-web-apps
- https://developers.google.com/youtube/v3/docs/channels/list
- https://developers.google.com/youtube/v3/live/docs/liveBroadcasts/insert
- https://render.com/docs/blueprint-spec
- https://render.com/pricing
