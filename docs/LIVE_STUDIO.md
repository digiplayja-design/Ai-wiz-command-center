# KORLIX Live Studio pilot

Live Studio adds server-run AI shows to the existing KORLIX application. K-Nova hosts; the optional Analyst uses a second voice. The first release enables saved shows and private rehearsals for the existing developer entitlement. It includes a separate YouTube worker implementation, but broadcasting remains disabled until that worker and the owner's channel are configured.

## Current scope

- Save a title, topic, category, one or two hosts, and a maximum 15- or 30-minute broadcast length.
- Explicitly start a private rehearsal: up to 60 seconds and three spoken segments, captions and source labels, saved as a private MP4. Closing the iPad screen does not cancel the server job.
- Three starts per account per rolling 24 hours; deleting a show does not reset this allowance. One queued or running job globally, including future schedules, during the pilot.
- Rehearsals run on the existing API service. They use the existing OpenAI and Supabase configuration and do not require a new hosting service. Speech and research incur the existing provider usage charges.
- Rehearsal playback uses an owner-checked five-minute signed URL. Removing a saved show removes its current private replay. A later successful rehearsal replaces that replay.
- YouTube controls stay disabled until the owner-specific worker heartbeat is present. The adapter requests unlisted broadcasts, applies AI disclosure, and waits for YouTube to confirm the actual live state.

The current visual is a branded graphic stage with captions and an active speaker. Photorealistic avatars, lip sync, multi-channel streaming, public broadcasts, automatic recurring schedules and 24/7 operation are not part of this pilot.

## Components

| Component | Location | Responsibility |
| --- | --- | --- |
| Flutter client | `lib/live_studio/` on the frontend release branch | Saved shows, private replay, status and producer controls |
| API | `backend/live_studio/routes.mjs` | Verified account access; explicit starts; owner-scoped controls |
| Database | `supabase/migrations/*_live_studio_pilot.sql` | Durable jobs, idempotency, usage receipts, worker leases and readiness |
| Rehearsal/stream engine | `backend/live_studio/runtime.mjs` | Research, speech, source-backed turns, moderation, bounded generation |
| Renderer | `backend/live_studio/media.mjs` | SVG graphics, H264/AAC segments, private MP4 and RTMPS transport |
| YouTube adapter | `backend/live_studio/youtube.mjs` | OAuth refresh, unlisted event setup, ingest checks, live chat, completion |
| Dedicated worker | `backend/live_studio/worker.mjs` | Independent cloud process for scheduled/live broadcasts |

Database tables and the RPC are service-only. RLS is enabled; anonymous and authenticated clients have no grants. User IDs always come from verified authentication at the API. Worker tokens, storage paths and stream keys are omitted from browser responses. Encoder stderr is suppressed because it can contain stream keys.

The worker records dispatch before a paid provider call and records its receipt or uncertain outcome afterward. It does not retry uncertain generation or resume a crashed show automatically. A 45-second lease fences an expired worker; the next poll marks abandoned jobs failed. Owner stop aborts pending operations, kills the encoder and attempts to complete the YouTube event. A hard restart can leave the channel displaying a disconnected event until YouTube auto-stop completes it; verify this in the acceptance test.

The stream prepares one segment ahead. Pauses and generation gaps use an original synthesized musical interlude. Pause/skip applies at segment boundaries, with a five-second control poll and additional platform playback latency. End attempts an immediate encoder stop after the control poll. Pauses count toward the maximum duration. A broadcast has a 200-generation-call ceiling; a rehearsal has a 10-call ceiling. Audience questions are filtered and moderated; accepted questions are researched before a host response. Initial pre-show chat history is ignored.

## Deployment

1. Apply the checked migration to the existing Supabase project, then verify grants/RLS.
2. Publish the backend release branch and deploy the existing Render API. The Docker image includes FFmpeg and DejaVu fonts.
3. Publish the frontend release branch and deploy the existing static service. Open Tools → Live Studio with the existing developer account, save a show, and explicitly create a private rehearsal.
4. Review the resulting spoken content, captions, source labels and iPad playback before channel activation.

No new paid service is created by committing these files or deploying the existing services.

## Proposed YouTube worker activation

The reviewable configuration is `deploy/live-studio-worker.render.yaml`. It creates one Docker background worker in Ohio on Render's `1c-2g` plan: 1 CPU and 2 GB RAM, listed at **US$25/month** on October 1, 2026, plus provider usage and applicable bandwidth/workspace charges. This is an initial sizing recommendation; a full-duration test must establish whether encoding keeps up. No Redis or persistent worker disk is required. State is in Supabase and disposable media is removed after the run.

The owner approved proceeding with the proposed $25/month worker and YouTube setup on October 1, 2026 at 12:40 Eastern. This approval is recorded; it does not need to be requested again. At this checkpoint no new worker or channel broadcast has been activated. The current Render connector cannot create background workers, and a Render API key is not configured in this workspace. Dashboard access and the owner's channel authorization remain necessary to complete setup.

In Render's secret settings, provide the existing Supabase URL/service role and OpenAI API key plus:

| Secret/setting | Required value |
| --- | --- |
| `LIVE_STUDIO_BROADCAST_OWNER_ID` | The verified Supabase UUID of the channel owner with pilot access |
| `LIVE_STUDIO_YOUTUBE_CLIENT_ID` | Google OAuth client for the approved channel integration |
| `LIVE_STUDIO_YOUTUBE_CLIENT_SECRET` | Its client secret |
| `LIVE_STUDIO_YOUTUBE_REFRESH_TOKEN` | Owner-authorized offline token with YouTube access |
| `LIVE_STUDIO_YOUTUBE_ENABLED` | `true`, only when channel activation is approved |

Use the Google account's authorization flow; do not paste tokens into chat or commit them. Enable the YouTube Data API and use the documented `https://www.googleapis.com/auth/youtube` OAuth scope. The channel must be eligible and enabled for live streaming. The pilot does not yet provide a self-service OAuth connection screen. Unverified API-project restrictions and channel eligibility can prevent a requested unlisted stream; keep broadcasting disabled until the actual account passes the test.

Import the approved Blueprint from the backend release branch with its custom file path. Enter secrets in Render. The worker announces readiness every ten seconds; it expires after 35 seconds without a heartbeat. It is restricted to its configured owner. The app can then start or schedule an explicitly confirmed unlisted show, one minute to seven days ahead. Auto-deploy is off to avoid interrupting an active broadcast; deploy while idle.

## Remaining live acceptance

These require the approved real channel and worker; mocked tests do not prove them:

- A complete 15-minute unlisted broadcast, followed by a 30-minute test, with sustained CPU/memory and ingest health recorded.
- Close the iPad screen, reopen it, verify state, pause/resume/skip, submit a question, and end the show.
- Confirm real YouTube visibility, AI disclosure, captions/audio timing, replay behavior and moderation under selected audience questions.
- Exercise provider timeout, worker termination and network loss. Confirm the encoder stops and uncertain paid operations are not automatically repeated.
- Confirm cleanup and budget receipts, then decide whether to broaden pilot access or add public/recurring broadcasts.

Automated checks use fixture providers and an in-memory PostgreSQL-compatible database, plus real local FFmpeg encoding. They never obtain a user token, call a paid generation provider or start a real YouTube broadcast.

## References

- [Render compute pricing](https://render.com/pricing)
- [Render Blueprint specification](https://render.com/docs/blueprint-spec)
- [YouTube Live API](https://developers.google.com/youtube/v3/live/getting-started)
- [YouTube live streaming eligibility](https://support.google.com/youtube/answer/2474026)
- [OpenAI moderation](https://developers.openai.com/api/docs/guides/moderation)

Estimated remaining work after this foundation: about 2–4 development days for channel setup and live acceptance; provider approval/eligibility delays can extend elapsed time.
