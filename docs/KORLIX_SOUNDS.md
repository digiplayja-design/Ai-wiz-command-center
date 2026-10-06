# Korlix sounds and alerts

The shared foreground sound controller is `kKorlixSounds` in
`lib/sounds/korlix_sound_service.dart`. Tones are synthesized locally as WAV
audio, cached, and played without an AI request, external sound download or AI GAS.

## User controls

Open **Settings → Sounds & Alerts**, or the direct volume icon in the app header.
Controls include master mute, volume, separate clicks/messages/calls/bells switches,
sound previews, and **Korlix Signature**, **Classic** and **Soft** packs.
**Enable sounds** requests audio activation during a user gesture; browsers may
otherwise block playback. A blocked-output message lets the user retry.

Preferences use the device-local `korlix.sounds.v1` shared-preferences record.
They persist across sign-ins on that device; they are not account/cloud settings.
Writes are serialized and storage failures are shown with a retry action.
Quiet hours follow the device's local clock, support overnight ranges, and mute
all effects. Equal start and end times mean all day. Defaults are sounds enabled,
65% volume, Signature pack and quiet hours off; clicks use one-quarter of the
selected volume. The character orbit breeze uses 4.375% of the selected volume
and shares the **Clicks & movement** switch.

## Connected events

| Sound | Current hooks |
| --- | --- |
| Click | Shared `KorlixActionButton`, wrapped main-screen/login/settings actions, and Directory shared buttons. Native button activation handles touch and keyboard; typing, scrolling and canceled gestures do not create clicks. |
| Orbit breeze | A locally synthesized 420 ms airy sweep when a horizontal drag starts moving the character orbit, or a character tap/arrow initiates a rotation. One sweep per drag, including its final snap; no idle, rebuild, restored-selection or vertical-scroll sound. |
| Message | A new Social message alert, including outside the Social screen. Restored unread counts and account replacement do not replay old alerts. |
| Ringtone/ringback | Incoming Social calls and outgoing call ringing. Global alerts and the call screen share the controller. Answer, decline, connection, cancellation, expiry and teardown stop ringing. |
| Bell | Fresh completed main-chat text generation and Contract Radar jobs transitioning from running to completed. Loaded historical results do not ring. |
| Success | Confirmed Directory saves/submissions/uploads, Contract Radar profile/actions, FieldProof successful actions, and explicit Copy Box/VoiceScribe save controls after persistence succeeds. Autosave on each text edit is silent. |

Character spins also show soft cloud wisps behind and in front of the orbit,
following the direction of rotation. Each movement refreshes an 850 ms fade;
there is no idle loop. The effect ignores pointer input, stays separate from
sound preferences, and is omitted when reduced motion is enabled.

The tone library also exposes `warning`; this is not a blanket hook for every
error. Scheduled appointment reminders currently remain their existing email
workflow; this release does not add a new timed in-app reminder scheduler.

## Playback rules

- `KorlixSoundHost` restores preferences and tracks app lifecycle across routes.
  Its pointer listener only attempts silent audio activation, never click playback.
- This is **foreground-only** audio. Hiding, locking or leaving the app stops its
  effects. There is no closed-app push delivery, background call service, CallKit
  or Android telecom integration in this change.
- Recordings, speech input, Live Convo, connected Social calls and the integrated
  media players hold independent quiet-owner leases. Effects stay suppressed
  until all owners release them after stopping their media. This does not mute
  speech, call tracks or the media itself.
- Calls take priority over one-shot effects and previews. Call identity is shared
  across owners; expiry is bounded to 45 seconds and repeated refreshes cannot
  extend that original deadline. A call silenced by mute, quiet hours, background
  state or a quiet lease does not unexpectedly restart when that condition ends.
- Event IDs deduplicate within a bounded, ten-minute in-memory window. Cooldowns
  are 80 ms for clicks, 420 ms for orbit breezes, 900 ms for messages and 350 ms
  for other one-shot tones.
  Muted events are consumed rather than queued for later playback.
- Each output channel cancels superseded playback and rejects late asynchronous
  preparation. Session changes stop rings/effects and clear prior-account event
  state while retaining device preferences and active media teardown leases.

## Adding a feature hook

Wrap an actual button callback once; keep disabled callbacks null. Shared
`KorlixActionButton` already wraps its callback, so do not wrap its caller again.
For a legacy Material button, suppress its separate Android system click:

```dart
onPressed: korlixSoundAction(busy ? null : openTool),
style: korlixSoundButtonStyle(existingStyle),
```

The wrapper activates audio synchronously in the gesture, runs the real action
immediately, ignores audio failures, and omits a click if activation takes over
250 ms. Do not play sounds from build methods, styles or raw pointer events.

Play outcome tones only after the operation confirms success and the screen's
mounted/session checks pass. Use a stable operation identity for repeatable events:

```dart
unawaited(kKorlixSounds.play(
  KorlixSound.bell,
  eventId: 'feature-job:$jobId',
));
```

Media integrations use `setQuiet(owner, true)` before capture/playback and
`setQuiet(owner, false)` after cleanup, including errors and disposal. Use a
distinct owner per independent media operation. Call integrations use
`setRinging(owner, true, callId: id, expiresAt: expiry, outgoing: false)` and
`setRinging(owner, false)` when that owner stops presenting the ringing call.
Do not implement additional feature-owned ringtone timers or players.

## Validation and release scope

The release check passed 220 automated tests covering controller
preferences/lifecycle/deduplication, tone generation, gesture wrappers, settings
layout, Social call/message integration, quiet leases and connected feature
regressions. Scoped analysis found no errors; existing application warnings
remain. The Flutter JavaScript web release build also passed.

Web playback uses Web Audio. Android/iOS use the `korlix/sound_effects` method
channel and native bridges in `MainActivity.kt` / `AppDelegate.swift`. Native
bridge changes require new store builds and device QA; a web deployment cannot
update an already installed native app. Audible browser/device playback and
native release builds have not been verified in this workspace. Test real
iPad/iPhone/Android volume, mute, call transitions, recording suppression,
quiet hours and foreground/background behavior before claiming device support.
