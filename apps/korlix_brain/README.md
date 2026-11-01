# KORLIX Brain+Voice

Standalone iOS/Android app for the existing KORLIX account and `general` Rici agent, with its own `com.korlix.brain` identity. Version 1.0.1, build 9 introduces **Live Conversation** (default) and **Deep Think · Sol Max**. Live uses the KORLIX AI speech-to-speech approach directly, without waiting for ASR or a separate Sol answer. Deep Think retains GPT-6.1 Sol Max. Build 9 has completed Apple processing and is Testing in the existing KORLIX Brain Internal group after explicit user approval. App Store review has not been submitted.

The approved Violet Eclipse / Champagne Precision interface is bundled offline in `assets/web`. It retains the Halo Capsule Talk button, Add Memory chip, Magnetic Key controls, Electric Cyan Precision Dial orbits, silent 3.1–3.6 second lightning and crystal twinkle ambience at 1%. Animation pause and reduced-motion support are preserved. The official KORLIX emblem now uses purple, red, green and gold. Apple, Google Play and device icon sizes are checked in.

## Connected behavior

- Native secure sign-in, refresh, password recovery, duplicate-account guidance, sign-out and shared-account deletion request.
- Native authenticated memory and behavior loading, reviewed typed/document changes, direct command-authorized voice saves, selected-item deletion, session undo and stale-training checks.
- Typed, OS dictation and selected-document inputs. A file produces a draft, never an automatic memory. Suggested memories are individually selected for review. Analysis uses the existing account allowance.
- Live Conversation uses `gpt-realtime-2.1` / low with Marin and native turn-taking. Ordinary replies do not wait for transcription or call the text-reasoning backend. Deep Think uses `gpt-6.1-sol` / max with incremental spoken phrases. Stop before changing modes; each session verifies its distinct model contract. Both modes retain account allowance, ephemeral transcripts, response reporting and no silent fallback. Credentials never cross the WebView bridge; remote navigation and network requests from the bundled page are blocked.
- Voice keeps running while navigating within the app. A 58-pixel red Stop conversation button stays fixed above the bottom safe area on every screen, including connecting/thinking/speaking states. Stop bypasses pending account operations, cancels a pending voice start, and disables microphone and playback before cleanup. Android includes a microphone foreground service with a Stop notification; iOS declares background audio with a play-and-record session. Physical-device verification is required before claiming screen-lock reliability.
- Existing service limits apply. No new prices, unlimited access or purchase flow are introduced in this first standalone build.

Memory and behavior changes affect the shared general KORLIX agent. Deep Think reloads account memory and training before each reasoning turn. Live loads account context at connection and receives memory-tool results during the conversation; reconnect to pick up external account edits. Say **“Rici, remember this: …”** or **“Rici, remember this instruction: …”** to save the exact spoken content without a separate password or review screen. Saying the command alone prompts for the next utterance, valid for 60 seconds; “cancel” or “never mind” discards it. Spoken instructions are saved as tagged, removable style memories in My Brain. Ordinary conversation is not automatically saved. Success is shown only after database acknowledgment. Duplicate transcript IDs are idempotent; interruptions suppress stale speech while preserving already-authorized saves. The backend limits memory listing to 250 entries. Training performs a fresh-content check before writing, but the existing API does not offer an atomic compare-and-swap operation.

## Build and validate

Use Flutter 3.47.9 / Dart 3.13.7, a Java 17 JDK (including `javac`) and Android SDK platforms 35 and 36 for Android, or macOS/Xcode for iOS. The app compiles against SDK 36; a native dependency also requires SDK 35. Keep `BOT=true` and `FLUTTER_SUPPRESS_ANALYTICS=true` set in automated builds to avoid cloud-instance detection and analytics.

```sh
cd apps/korlix_brain
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
flutter build ios --simulator --debug --no-pub
```

`.github/workflows/korlix-brain-validation.yml` builds both test artifacts and an unsigned iPhoneOS arm64 release binary without deployment or store submission. It also checks Apple identity and build numbering safeguards. `codemagic.yaml` contains dedicated Brain+Voice candidate and TestFlight workflows using the existing managed KORLIX distribution certificate and a separate `com.korlix.brain` profile. See [store/RELEASE.md](store/RELEASE.md) for the exact release route and draft store material. Android release signing remains unconfigured.

For browser view checks, install Playwright separately and run `node tools/check_ui.cjs`; `PLAYWRIGHT_MODULE` and `BROWSER_EXECUTABLE_PATH` can point to an existing installation. `UI_SCREENSHOTS` optionally saves local QA screenshots. The harness injects a fake bridge only in the test process and verifies approval, failure, deletion, transcript safety and four viewport layouts. Production has no mock accounts or fallback saves.

## Release verification

The build-9 source passes Flutter analysis, 53 Dart tests and 23 Apple identity, privacy-purpose and build-number checks. The updated backend passes 54 Brain/agent-studio tests and 13 shared-agent checks. Four viewport UI checks cover mode selection, Stop visibility, scrolling, pending-stop feedback and stale events. The [signed build-9 pipeline](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6ae69eaca74da3772d1eab3a) repeated the app tests and release checks, verified the signed IPA, and successfully uploaded version 1.0.1 (9). Apple processing and approved group assignment are complete: build 9 is Testing in KORLIX Brain Internal alongside builds 8, 7, 6, 5 and 3. No testers were added or invitations resent. Public App Store review has not been submitted.

The preceding build-4 code passed Android, simulator and iPhoneOS arm64 compilation in [GitHub validation run 41247985018](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41247985018). Build 9 was compiled in the signed iOS pipeline; an updated Android binary has not been delivered.

The current production backend is commit `8dff4033d983cb10aafe3cb032b13fadaf18418d` on `release/signup-plan-intent-20261021`, Render deploy `dep-dbj9sq7b9u1s73deb3a0`, verified live. Deploy that branch; this app branch retains its original backend snapshot. Live verifies `rici-live-v1` / `gpt-realtime-2.1` / low and automatic audio replies; Deep Think verifies `sol-6.1-max-v1` / `gpt-6.1-sol` / max with speech-only output. Each waits for its explicit session acknowledgement before opening the microphone. Installed Astra and Sol clients retain their original profiles. Sessions cannot change modes mid-conversation. Account allowance and audio usage remain metered; each memory tool exchange counts as one user turn while all audio tokens count. Content-free first-audio timing is client-reported, not a completed device benchmark. Ephemeral sessions require reconnect after a backend restart.

The user reported slow responses on build 3. Three server requests took 6,995, 7,930 and 10,951 ms before speech delivery. Streaming removes full-answer buffering but does not eliminate Astra Max reasoning time. A measured conversation with the latest build on the user's phone remains pending. Build 6 also fixes the startup check that rejected the provider's initial default settings: it waits for an explicit speech-only acknowledgement before enabling the microphone, with a bounded timeout.

Before public store submission, verify shared-account sign-in, permission denial/recovery, two-way Rici audio, direct save/reconnect/delete, Bluetooth output, quota exhaustion, app switching, screen lock and document analysis on physical devices. Complete store privacy declarations and real-device screenshots. Android store signing remains unconfigured. Local tests use fixtures and do not write live account data.

Native platform references: [Android microphone services](https://developer.android.com/develop/background-work/services/fgs/service-types#microphone), [Apple play-and-record background audio](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord).

## Build 7 identity and latency correction

The shared agent runtime could promote a training alias such as Kim above the
Brain identity. Brain+Voice now supplies a dedicated Rici system prompt and
passes current training/memories as lower-priority JSON account data. Existing
shared profiles are preserved. The speech voice remains Marin; this fixes the
spoken identity conflict rather than changing the acoustic voice arbitrarily.

Exact “Rici, are you there?” and “What’s your name?” requests receive metered app
phrases without an Astra request. Build 8 uses Sol 6.1 Max for compound questions.
Pending “remember this” capture takes precedence. First complete sentences no
longer wait for 60 characters before entering the speech queue.

Build-6 production first-text measurements were 2,234, 5,363 and 7,955 ms, with
50–59 ms preparation. Max reasoning remains a source of delay; no subsecond
model-response claim is made. Post-update physical-device timing and spoken
identity verification remain pending.

## Build 8 Sol migration

Requested target: `gpt-6.1-sol`; previous Max effort requirement is retained.
The app checks the Sol protocol, model and effort before enabling its microphone
and verifies each answer chunk. The server pins each authenticated session to
its requested supported profile, keeping installed Astra builds functional.
No automatic fallback or paid processing-tier upgrade is added.

Validation: 41 Flutter tests, clean analysis, 29 Brain backend tests, 20 shared
agent-studio tests, 13 legacy-agent checks, 23 release checks and four viewport
UI checks passed. Live phone latency and spoken quality remain to be measured.
The deployed server verified model metadata access (HTTP 200) using its existing
key; that is not a speed benchmark or a completed inference. Max effort can still add response delay.

## Build 9 conversational voice correction

Build-8 production measurements showed first Sol text at 3,883 / 6,820 / 13,446 ms; account preparation was 47 / 64 / 82 ms. The user chose Live + Deep Think. Native Live replies now begin directly from audio without a per-turn Sol request or transcript wait. Deep Think retains Max reasoning for deliberate answers. The mode selector is fixed during active voice and re-enables after Stop.

The live memory tool has no content parameters: the native app binds it to the original user audio item, waits only for that item's transcript, and the backend validates the explicit command before saving. Duplicates, missing transcripts, account changes and interrupted callbacks cannot create substitute writes or stale speech. Each tool exchange counts as one user turn while all audio tokens are metered. Content-free client timing measures speech-stop to first audio for subsequent device tests.

Validation: clean analysis, 53 Flutter tests, 34 Brain backend tests, 20 agent-studio tests, 13 legacy-agent checks, 23 release checks and four viewport checks passed. Signed build 9 is uploaded, processed and Testing in KORLIX Brain Internal following explicit user approval. Physical-device voice timing and spoken quality remain pending.
