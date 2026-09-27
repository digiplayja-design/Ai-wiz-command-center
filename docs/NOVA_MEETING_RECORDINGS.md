# Nova meeting audio recordings

## Use

Open Meeting Co-Pilot for the selected Enterprise agent and start Nova or Start listening. Confirm the audio meter receives Zoom audio. Expand **Meeting audio recording**, tell participants and obtain their permission, leave **Include Nova’s voice from this browser** enabled, select the recording permission checkbox, then choose **Start recording**. If Zoom already carries Nova’s shared device audio, disable the extra Nova track to avoid hearing it twice. Recording never starts automatically with Nova.

Use **Stop & save** when finished. The entry changes from Recording to Saving to Saved. Choose **Open recording**, press Play, or **Download MP3**. Opening a recording pauses Nova's replies to prevent overlapping speech. **Delete** asks for confirmation and removes both the private audio and its entry. Refresh recordings to recover an uncertain request or update another browser's changes.

**Silence Nova** pauses her replies while recording continues. **Stop listening**, capture revocation, or the end of the capture stream ends recording and saves audio already received. Recordings remain accessible to the owner of the selected agent after listening ends.

## Scope and limits

- Mixed Zoom meeting audio received by the existing RTMS capture, encoded as 16 kHz mono MP3 at 64 kbps. It is not a microphone or screen recorder and does not record a separate track per participant.
- Nova’s voice from this browser is included by default in new recordings: automatic replies, waiting acknowledgments and manually reviewed spoken updates. Only samples that passed the local playback clock are sent; Silence or interruption excludes the unplayed remainder. The short activation beep is excluded. The option can be turned off before recording if Zoom already carries her device audio. This adds voice to the saved MP3; it does not configure audio sharing to other Zoom participants.
- Up to 60 minutes per recording, 32 MiB per MP3, 20 saved entries per agent, one active recording per owner/agent, and four active encoders per backend instance. Delete old entries to free the library limit.
- Listening must remain connected. Browser suspension, lease expiry, meeting changes, or loss of host authority can end capture. App switching is not an unlimited background-recording guarantee.
- Audio is finalized and uploaded when recording stops. Temporary in-progress audio is not crash-durable. A forced restart or storage failure may leave an interrupted/failed entry instead of a saved recording. The UI never calls that entry Saved. Normal service shutdown drains finalization for up to 30 seconds.
- Completed recordings remain until the owner deletes them. Signed playback/download links expire after one hour; reopen a recording to obtain fresh links. Anyone given a signed link can use it until it expires, so treat it as private. Downloaded copies are outside KORLIX deletion.

## Backend contract and privacy

`POST /api/k135z/zoom/workspace/recordings` accepts an action of `list`, `start`, `stop`, `play`, `download`, `delete`, `voice-start`, or `voice-chunk`. Every request authenticates the user, checks Enterprise access, and resolves ownership of the selected agent. Responses are `Cache-Control: no-store`. Start requires an unpredictable 32-character hexadecimal ID, the exact current capture context, and separate `consent: true`. Start checks the live host/listening lease before and after encoder preparation. Repeating the same Start ID is idempotent. Playback, Stop and Delete accept only an ID. The two voice actions also require the exact capture context and an unpredictable playback ID, and recheck the active host/listening lease on every request. Voice chunks are mono signed 16-bit little-endian PCM at 16 kHz, at most 16,000 bytes per chunk, with a consecutive sequence. Clients cannot supply storage paths, media URLs or trusted owner identity.

The transport forwards validated PCM only after the capture command is committed and while its current authority lease is valid. Silence of Nova's replies does not revoke that capture lease. Stop fences new packets immediately; saving runs independently of the HTTP request so a lost Stop response cannot discard or restart recording. Duration is measured from received PCM samples, including the last Nova sample. If Zoom is quiet at the end, a bounded silent tail aligns the extra Nova track; no speech is fabricated. The server anchors each reply to the current Zoom sample position. Network delivery and capture gaps can create some timing skew; this is not sample-perfect device synchronization.

Metadata lives in `public.k135z_meeting_recordings`. RLS is enabled and all public, anon, and authenticated privileges are revoked; only the server service role receives CRUD privileges. Every server query filters tenant, user, and agent. Media uses the private `korlix-meeting-recordings` bucket, with a restrictive storage policy denying direct anon/authenticated access even alongside a broad permissive policy for other buckets. Paths use a SHA-256 owner scope and random recording ID. Playback and downloads use server-authorized signed URLs; URLs, audio bytes, and encoder diagnostics are not logged.

FFmpeg runs without a shell, with fixed codec arguments, bounded input/output and a private temporary directory. Played Nova PCM uses a second private temporary file, then fixed FFmpeg mixing combines the tracks without normalizing the human voice downward. A limiter protects overlapping audio. Voice input is bounded to 45 seconds per playback, 512 playbacks and one hour of total PCM per recording; sequence retries do not duplicate audio. Total output retains the 32 MiB limit. Finalization has a 25-second codec deadline. Media is removed from temporary disk on successful finalization or abort. Deletion marks an entry before removing its object and row; a failed deletion can be retried. The deployment uses the existing single backend instance and existing Supabase project. No environment variables, service plans, autonomous-email settings, or bookkeeping state are changed.

## Release and rollback

Apply `supabase/migrations/20260927024536_k135z_meeting_recordings.sql` before deploying the backend. The backend Docker image installs FFmpeg and verifies synthetic PCM-to-MP3 encoding during its build. Deploy the frontend only after the backend is healthy and the recording route rejects unauthenticated access. Existing services have auto-deploy disabled and require explicit deployments.

Rollback the frontend controls before rolling back backend code. Leave the private table and bucket intact so saved recordings are preserved for a forward fix. Do not drop the bucket or table as a routine rollback. Stop active recordings before a planned rollback where possible.

## Verification

Backend regression command:

```sh
node --test --test-timeout=30000 backend/test/k135z_meeting_recordings.test.cjs backend/test/k135z_stream_start_audio.test.cjs backend/test/k135z_meeting_response.test.cjs backend/test/k135z_spoken_reply.test.cjs backend/test/k135z_waiting_voice.test.cjs backend/test/k135z_shared_server_integration.test.cjs backend/test/k135z_scope_guard_regression.test.cjs backend/test/k135z_agent_memory.test.cjs
```

Recording tests cover explicit consent, host/lease checks, account and agent isolation, idempotence, overlapping starts, packet fencing, setup revocation, meeting end, duration limit, codec/storage failures, a pending heartbeat, shutdown draining, stale session recovery, scoped storage queries, and database privacy constraints. The real encoder test uses only a synthetic tone and ffprobe. The database test uses PGlite locally and intentionally includes a broad legacy storage policy.

Frontend tests: `flutter test --no-pub test/meeting_copilot`. The recording cases cover separate consent, meeting changes, stale signed-out responses, Stop priority over a slow poll, private playback validation, deletion, and controls at 390- and 1024-pixel widths. Release compilation: `flutter build web --release --no-pub --base-href /app/`.

No assistant-initiated live meeting capture is used for deployment validation. Live acceptance requires the owner to record a short consented Zoom meeting, Stop & save, play/download the MP3, and optionally delete it. A second participant is still needed to verify remote participant audio and Nova’s Zoom delivery. The owner should also test a recording with both their own speech and Nova’s local replies, interrupt one reply with Silence, save, and confirm both voices without the unplayed remainder.


## September 27 voice inclusion repair

The owner confirmed that recordings saved their microphone but omitted Nova. This was a missing source, not evidence that a previously saved reply can be recovered. Earlier recordings remain unchanged; new recordings include the local voice track after the updated app loads.

The browser sends played PCM in bounded packets without waiting before speaking. Stop & save drains pending voice packets for up to five seconds before stopping. Explicit Stop listening also drains after silencing Nova. Scope changes reject pending packets; abrupt browser closure, network failure, or external stream termination can lose an in-flight tail. Upload failure displays a partial-voice warning and leaves the Zoom recording available to stop and save. A slow connection never queues more than eight voice requests per playback.

No new database migration or infrastructure setting is needed. Deploy the backend before the frontend. Existing private recording storage and earlier saved media are retained.

Validation adds playback-clock/PCM tests for sample boundaries, suspension, late recording opt-in, mono conversion, bounded chunks, queue ordering, sign-out and failed uploads. Backend cases cover voice authorization, foreign contexts, malformed samples, sequence replay/gaps, duration limits, concurrent Stop and real two-frequency MP3 mixing. Both original human and extra Nova frequencies are present only in the expected intervals. These tests use synthetic audio and do not join or record a real meeting.

Implementation references: W3C Web Audio API https://www.w3.org/TR/webaudio-1.0/ and FFmpeg filters https://ffmpeg.org/ffmpeg-filters.html .
