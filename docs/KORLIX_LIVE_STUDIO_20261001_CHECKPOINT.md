# Live Studio checkpoint — October 1, 2026

## Outcome

The private rehearsal foundation is published and deployed. The server continues a rehearsal after the user closes the iPad screen. The separate YouTube worker and channel adapter are implemented but have not been activated against a real channel. Do not describe this checkpoint as an active autonomous YouTube broadcast.

Open [KORLIX AI](https://www.korlixdeveloper.com/app/), refresh, then select Tools → Live Studio. The current developer account can save a show and explicitly create a private rehearsal. K-Nova and the optional Analyst use generated speech over a graphic stage with captions and source labels. A rehearsal lasts up to 60 seconds; the pilot allows three starts in 24 hours.

## Deployed versions

| Component | Commit / version | Deployment |
| --- | --- | --- |
| Backend | `857fe4224f5af62516b02bf8c93cd0ec938eb1a1` | `dep-dav8sllg1s2s73cn25g0`, live at 16:47:36 UTC |
| Frontend | `63f972e87a205107c1a3561ad2a0f72f202db496` | `dep-dav8sn3bc2fs738g7qjg`, live at 16:48:22 UTC |
| Supabase migration | `20261001164116_live_studio_pilot` | Applied to `uxtjzjbwtppjvnsoiijv` |

Repository: `digiplayja-design/Ai-wiz-command-center`. Backend branch: `release/k135z-backend-render-20260919`; frontend branch: `release/k135z-frontend-20260919`. Render workspace: `tea-d8cskuf7f7vs73emq1p0`. Backend service: `srv-d8csvkkp3tds73emfikg`; frontend service: `srv-d8ekf7t7vvec73dpar60`. Both have automatic deployment disabled.

GitHub publication used the connected GitHub tool because the shell had no push credentials. Published Git tree hashes exactly matched the tested local commits. This documentation checkpoint can advance the backend branch without requiring another application deployment.

## Verification

- 18 Live Studio backend tests passed: real local H264/AAC encoding, private replay, ownership, client-role denial, idempotent starts, global capacity, scheduling, lease fencing, cancellation, usage caps, uncertain-call handling, backpressure listener cleanup and mocked YouTube contracts.
- 41 existing shared research/speech provider tests passed.
- Nine Flutter checks passed: account-change invalidation, request behavior, 320/390/768/1280-pixel layouts, saved shows, disabled unconfigured YouTube controls, consent cancellation, and a single server start when leaving the screen.
- The studio screenshot was reviewed with actual fonts. The production Flutter web build passed; analysis of the new files had no errors or warnings, with style-only lint information remaining.
- Production backend health returned 200 and Live Studio version 1. An unauthenticated studio request returned 401. No Live Studio worker errors were present in the checked deployment logs.
- The four new tables have RLS enabled, no anonymous/authenticated read grants, and a service-only RPC. The private video bucket is not public and is limited to 50 MiB per object.
- The worker Blueprint validates against Render's current JSON schema.

Tests use fixture providers. No real paid rehearsal, YouTube stream, or audience interaction was executed by this development session. Real account playback, provider behavior and full-duration streaming remain acceptance steps.

The security advisor's no-policy information on these four server-only tables is expected; client roles have no grants. Existing project-wide view/function/auth advisories were outside this feature change and were not modified. See [Supabase's database linter](https://supabase.com/docs/guides/database/database-linter) for those existing notices.

## Approval and remaining connection work

At 12:40 Eastern on October 1, the user said “Go ahead” after the proposed $25/month Render worker and YouTube activation were described. This approval is recorded and must not be requested again.

Prepared configuration: [`deploy/live-studio-worker.render.yaml`](../deploy/live-studio-worker.render.yaml). It proposes one `1c-2g` Docker worker in Ohio, with one CPU and 2 GB RAM, plus the existing provider usage costs. See [`LIVE_STUDIO.md`](LIVE_STUDIO.md) for configuration, the price source and acceptance steps.

Remaining blockers:

1. The connected Render tools do not expose background-worker or Blueprint creation. No Render CLI/API key is configured in this workspace. The browser integration requires permission before switching from an insufficient connector to dashboard access; no Render browser session has been opened. Ask only for this dashboard fallback, not for the already-approved worker cost.
2. No YouTube channel/account has been specified or authorized. The existing Google Calendar connection is not a YouTube connection. Obtain the intended channel and its Google authorization through the normal account flow. Do not ask the user to paste secrets into chat.
3. After connection, run an unlisted 15-minute show and then a 30-minute show. Validate ingest health, sustained encoding, source/caption presentation, moderation, audience questions, iPad-independent operation, producer controls, YouTube auto-stop/completion, restart behavior and usage receipts before broadening access.

Estimated remaining development: about 2–4 days after channel connection, with provider approval or eligibility delays affecting elapsed time. Continue to include a remaining-time estimate in development updates, per the user's preference.
