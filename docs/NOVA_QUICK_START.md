# Nova Co-Pilot quick start

## Start a conversation

1. Open Meeting Co-Pilot with the intended agent. Connect Zoom if necessary.
2. If more than one meeting appears, choose the intended meeting.
3. Tap **Start Nova**. This permits listening, transcription, and spoken replies to anyone who addresses Nova in that meeting, including brief waiting acknowledgments.
4. Say **“Nova, what have we decided?”** or another question. Say **“think deeply”** when extra reasoning is needed.

Start Nova unlocks browser audio in the tap itself, starts listening through the existing consent/recovery flow, and enables voice without a second tap. A sole meeting is selected automatically; opening the page never starts listening or speech. An already listening session needs no repeat capture start. Choosing a different meeting requires a new Start Nova action.

**Silence Nova / Stop Nova** immediately silences this page and cancels its reply request. **Stop listening** also stops capture. The connection options retain a listening-only start. Unsupported browsers retain listening controls. Returning from another window uses the existing session recovery and shows a resume button if the browser requires a new audio gesture.

For other Zoom participants to hear Nova, start Zoom screen broadcast with device audio. The meeting can see the shared screen. Browser tab suspension and device audio routing still affect live playback; a successful local build is not proof that a particular iPad/phone is broadcasting audio.

## Response timing and small talk

- Questions ending in a question mark wait 700 ms after the latest caption before dispatch, reduced from 1,600 ms. Other fragments retain 1,600 ms; a bare wake phrase retains 2,800 ms so Nova does not interrupt a question that is still forming.
- With foreground voice enabled, the capture scheduler checks every 250 ms and polls captions no sooner than 500 ms after the previous poll completes. Only one caption fetch runs at a time. Normal cadence resumes when voice is off or suspended.
- After explicit voice opt-in, the client prepares two short acknowledgments in the background. It never waits for this preparation before enabling voice or sending a question.
- If an answer is still pending after one second and audio is prepared, Nova can say, “I'm on it. Give me a moment to think that through.” At nine seconds she can add, “I'm still working through that. Thanks for bearing with me.” Each can play once per question. Slow preparation skips the early acknowledgment after six seconds.
- The answer immediately interrupts acknowledgment audio, including audio being decoded. No waiting speech is queued behind the answer. Fast answers skip acknowledgments altogether.
- **Small talk while thinking** turns waiting speech off immediately without cancelling the actual answer. Missing/failed waiting audio does not disable normal replies.
- Stop, page suspension, changed permissions, changed meetings, and stale reply completions retain session/epoch checks. Captions heard while replying or during the existing four-second echo cooldown are not queued for later replies.

The acknowledgments use the configured Nova TTS voice and fixed English phrases. They make no claims about searches, completed work, or meeting facts. Personal memory and answers are never cached with them. Actual answer generation still uses the existing fresh selected-agent runtime and reasoning pipeline; these timing thresholds are not a measured end-to-end latency guarantee.

## Validation

Run `flutter test --no-pub test/meeting_copilot` and `flutter build web --release --no-pub --base-href /app/` from the frontend repository. The quick-start suite includes delayed audio activation, rejected consent, meeting selection/switching, single-flight caption polls, answer priority, bounded chatter, interruption, optional-audio failures, and 390/1024-pixel layouts.

Live acceptance remains necessary: measure end-of-question → first acknowledgment and end-of-question → answer on the target device; try a fast answer, a slow answer, Stop during both kinds of audio, a window switch, and Zoom device-audio broadcast. Check the backend's existing `k135z_spoken_latency` event to distinguish memory, answer generation, and speech synthesis delays without logging private content.
