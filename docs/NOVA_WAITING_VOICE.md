# Nova Co-Pilot waiting voice

`POST /api/k135z/zoom/workspace/waiting-voice` prepares two fixed short acknowledgments after the browser explicitly enables spoken replies. It uses the existing workspace authentication, Enterprise/selected-agent authorization, active capture lease, host/listening permission, and revision checks. It is registered alongside the existing response routes only when workspace HTTP and transcript preview are configured.

The only accepted request fields are `context` and `enabled: true`. The client cannot supply words, a voice, memories, model selection, or instructions. Successful responses contain `waitingVoice.context` and exactly two `clips` with `text`, `mimeType: "audio/mpeg"`, and base64 audio. Responses are `Cache-Control: no-store`.

The service synthesizes two fixed English phrases using `gpt-4o-mini-tts` and the same `KORLIX_LIVE_CONVO_VOICE` setting as normal replies (validated voice, otherwise `marin`). These public phrases alone are cached in process for one hour. A configured-voice change invalidates the cache. No agent runtime, meeting captions, question, answer, or customer audio is cached.

Each clip is limited to 120,000 bytes and validated as MP3. Only one preparation runs at a time; failed/cold preparations are bounded to three attempts per user and twenty per process per hour. Permission is checked before each provider request, after synthesis, and on cache hits. Cancelled or unverified synthesis is discarded; every response requires a fresh permission check. The HTTP deadline is 30 seconds. Limits and cache are per process, consistent with the existing single-instance response services.

The frontend preparation is optional and asynchronous. Failed, unsupported, or busy preparation does not delay or disable normal replies. The frontend schedules at most one initial acknowledgment and one longer-wait follow-up; the actual answer preempts both. Stop and session changes discard late preparation/reply completions. This endpoint never starts playback or changes Zoom sharing.

No database migrations, schema changes, extra environment variables, provider model changes for actual answers, or external actions are introduced. The existing `spoken-reply` and reviewed-update contracts remain intact. Fresh agent memory/training and final-answer authority checks remain mandatory.

## Local verification

From the repository root:

```sh
node --test --test-timeout=30000 backend/test/k135z_meeting_response.test.cjs backend/test/k135z_spoken_reply.test.cjs backend/test/k135z_waiting_voice.test.cjs backend/test/k135z_shared_server_integration.test.cjs backend/test/k135z_scope_guard_regression.test.cjs backend/test/k135z_agent_memory.test.cjs
```

The waiting-voice tests cover fixed provider input, configured voice, expiry, explicit opt-in, arbitrary-field rejection, authorization even on cache hits, cancellation, changed revisions, concurrent/cost limits, invalid audio, and HTTP routing. Shared-server regression coverage includes the newly registered endpoint.

Live checks must distinguish the first acknowledgment from the actual answer. Use existing `k135z_spoken_latency` stage timings for provider/memory delays. Do not claim measured live latency from fake-provider tests. The first cold session may have no waiting audio until preparation completes; the actual answer always proceeds independently.
