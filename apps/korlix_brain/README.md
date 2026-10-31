# KORLIX Brain+Voice

Standalone iOS/Android app for the existing KORLIX account and `general` Rici agent. This app has its own `com.korlix.brain` identity and does not replace KORLIX AI. Version 1.0.1, build 2. Store release workflows and draft listing material are prepared; no Brain+Voice store submission is confirmed.

The approved Violet Eclipse / Champagne Precision interface is bundled offline in `assets/web`. It retains the Halo Capsule Talk button, Add Memory chip, Magnetic Key controls, Electric Cyan Precision Dial orbits, silent 3.1–3.6 second lightning and crystal twinkle ambience at 1%. Animation pause and reduced-motion support are preserved. The official KORLIX emblem now uses purple, red, green and gold. Apple, Google Play and device icon sizes are checked in.

## Connected behavior

- Native secure sign-in, refresh, password recovery, duplicate-account guidance, sign-out and shared-account deletion request.
- Native authenticated memory and behavior loading, reviewed typed/document changes, direct command-authorized voice saves, selected-item deletion, session undo and stale-training checks.
- Typed, OS dictation and selected-document inputs. A file produces a draft, never an automatic memory. Suggested memories are individually selected for review. Analysis uses the existing account allowance.
- GPT-6 Astra (`gpt-6-astra`) with `reasoning.effort: max` generates every conversational answer on the server; no automatic downgrade. Realtime supplies microphone transcription and spoken delivery with automatic responses disabled. Native WebRTC voice, usage limits, stop/reconnect, ephemeral transcript and response reporting. Credentials never cross the WebView bridge; remote navigation and network requests from the bundled page are blocked.
- Voice keeps running while navigating within the app. Android includes a microphone foreground service with a Stop notification; iOS declares background audio with a play-and-record session. Physical-device verification is required before claiming screen-lock reliability.
- Existing service limits apply. No new prices, unlimited access or purchase flow are introduced in this first standalone build.

Memory and behavior changes affect the shared general KORLIX agent. Astra reloads saved account memory and training before each reasoning turn. Say **“Rici, remember this: …”** or **“Rici, remember this instruction: …”** to save the exact spoken content without a separate password or review screen. Saying the command alone prompts for the next utterance, valid for 60 seconds; “cancel” or “never mind” discards it. Spoken instructions are saved as tagged, removable style memories in My Brain. Ordinary conversation is not automatically saved. Success is shown only after database acknowledgment. Duplicate transcript IDs are idempotent; interruptions suppress stale speech while preserving already-authorized saves. The backend limits memory listing to 250 entries. Training performs a fresh-content check before writing, but the existing API does not offer an atomic compare-and-swap operation.

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

## Remaining release verification

Version 1.0.1 passes Flutter analysis, all 22 Dart tests and browser interaction checks at 320, 390, 768 and 1024px. The production backend passes 30 checks. [GitHub validation run 41240702620](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41240702620) successfully built Android and iOS simulator artifacts from code commit `5a504a2ef7a7937ce89e533a713ed8ba3501b83c`. The Android 1.0.1 test APK has a different debug signing certificate from 1.0.0. Android therefore requires removing the earlier debug app before installation; unsaved local drafts are lost, while server-saved account memory remains. These are test builds; the iOS simulator ZIP requires a Mac simulator and cannot be installed on an iPhone or iPad through TestFlight.

The production backend implementation is commit `0304a4a0d6927402e4461fac193247033b22c978` on `release/signup-plan-intent-20261021` in `backend/brain_voice/core.mjs` and the scoped `/api/brain-voice/turn` route. Deployment must use that release branch; this app branch retains its original backend snapshot. The app verifies the server's `astra-max-v1` protocol and exact model/effort headers before opening its microphone. Ephemeral voice sessions require reconnect after backend restart. Reasoning tokens are metered server-side and combined with speech usage.

Test real shared-account sign-in, permission denial/recovery, two-way Rici audio, Bluetooth/speaker output, quota exhaustion, app switching, screen lock, Stop notification and file analysis on Android and iPhone. Confirm deletion-request and report receipts with the deployed backend. Run the prepared iOS signing workflow and verify the dedicated store records, then complete store privacy/foreground-service declarations and device screenshots. No live account data was written by local automated tests.

Native platform references: [Android microphone services](https://developer.android.com/develop/background-work/services/fgs/service-types#microphone), [Apple play-and-record background audio](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord).
