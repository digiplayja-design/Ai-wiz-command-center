# NOVA Live Voice workspace

Release prepared September 28, 2026. Updates the existing LIVE CONVO entry.

## Experience

- A responsive NOVA workspace with white and dark surfaces, a calm character
  stage, readable captions, and an uncluttered conversation panel.
- Start, Pause/Resume, Mute/Unmute and Stop stay visible while scrolling on a
  phone. Mute keeps the connection open; Pause closes it and retains temporary
  conversation context for this screen's lifetime.
- Voice selection, the selected agent, camera questions, typed messages,
  attachments, document generation, transcript copy and sharing remain available.
- The selected agent supplies the displayed speaker identity. The selected
  character is identified separately as the avatar; NOVA remains the voice brand.
- Reduced motion suppresses the continuous halo. The halo represents conversation
  state, not measured microphone amplitude. Avatar loading no longer presents an
  indefinite spinner as if the voice session were busy.
- Controls provide readable labels, keyboard focus, screen-reader names and
  sufficiently large targets. Status changes use a live region. Both themes are
  checked at 320, 390 and 1280 logical pixels with 125% text scaling.
- Transcript history uses a bounded, lazy list; latest turns stay at the bottom
  and earlier turns remain scrollable. Export still includes the full transcript.

## Reliability

- A session reports connected only after SDP acceptance, a connected peer and an
  open data channel. Tool configuration and temporary-context restoration then
  run on the ready transport. The previous arbitrary 350 ms startup wait is gone.
- A transient disconnected peer has eight seconds to recover without creating
  another provider session. Failed/closed peers, a closed data channel, or an
  unrecovered disconnect release the stream, channel and peer. Reconnect remains
  an explicit user action and retains temporary chat context.
- The data-channel readiness wait is limited to twenty seconds. A sixty-second
  startup deadline also handles an unanswered microphone-permission prompt. Late
  device/session results remain bound to their original connection generation.
- Microphone tracks are disabled synchronously before cleanup awaits anything.
  Usage reporting starts separately from device teardown, so report latency does
  not keep the microphone or provider connection active. Every audio track is
  included in mute/unmute, with stale-stream and concurrent-toggle guards.
- Speaking follows WebRTC output-audio-buffer events, rather than treating
  response generation as playback. A late stop event from an older response
  cannot clear a newer speaking state. This indicates provider audio streaming;
  it does not prove that a user's physical speaker is audible.
- Permission denial, missing/busy microphones, connection timeouts and audio
  initialization errors receive actionable messages. Renderer initialization
  failure is caught and can be retried on Start.
- The route listens to the app's auth revision notifier. Sign-out or a different
  session closes devices and removes the private voice workspace. A token refresh
  with the same issuer, subject and session ID does not interrupt the conversation.
  Decoded claims are used only for UI invalidation; backend authentication remains
  authoritative.
- System back and the close button use the existing Keep/Erase/Cancel flow. A
  repeated close request cannot open duplicate confirmation dialogs.

## Compatibility and verification

The backend's existing Realtime model, selected voice, semantic VAD, interruption,
noise reduction, usage limits and server-side credentials are preserved. This is
a frontend deployment with no schema or environment changes. Existing agent
learning, protected approval, email and Live Docs routing are preserved.

Targeted verification: 179 Flutter tests across live voice, Live Docs, protected
learning and related meeting co-pilot pause/integration coverage. Added tests
exercise actual screen lifecycle with fake microphone/peer/network I/O, including
fatal and transient disconnects, timeout/cancellation, transcript restoration,
playback state, all-track mute, sign-out and token refresh. UI tests cover themes,
mobile controls, typed-message/agent/voice actions, reduced motion and system back.
Flutter analyzer and the production web build are release gates. Review screenshots
are generated locally under `build/voice-review/` by the workspace test.

Testing uses fixture credentials and fake device/provider traffic. No owner
account, paid voice session, real email send or private conversation was used.
Real browser microphone permission, physical audio, Bluetooth output and provider
latency still need a short signed-in acceptance conversation on the user's device.
Browser background restrictions and operating-system audio behavior still apply.

## Source guidance reviewed

- https://developers.openai.com/api/docs/guides/realtime-conversations
- https://developers.openai.com/api/docs/api-reference/realtime-server-events/output_audio_buffer/started
- https://developers.openai.com/api/docs/api-reference/realtime-server-events/output_audio_buffer/stopped
- https://supabase.com/docs/guides/auth/sessions

The output-audio-buffer events distinguish streaming/draining from response
generation completion. Supabase's session ID distinguishes token refresh from a
different authenticated session. No provider/model migration is part of this work.

## Manual acceptance

Open LIVE CONVO, Start and allow the microphone; ask a short question and interrupt
the reply. Mute/Unmute should keep the call open. Pause should release the microphone;
Resume should reconnect with the same temporary conversation. Test a brief network
drop and a sustained drop, typed messages, camera questions, transcript export and
voice/agent selection. Check the light theme and a phone-size layout. Stop and Back
must honor Keep Current Chat, Erase Current Chat and Cancel.
