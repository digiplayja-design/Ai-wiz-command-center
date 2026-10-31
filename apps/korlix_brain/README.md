# KORLIX Brain — first native build

An independent Android/iOS app that keeps the approved Violet Eclipse interface and connects it to the shared KORLIX account service. App ID: `com.korlix.brain`. Version: `1.0.0+1`.

## Included

- Existing KORLIX sign-in, account creation, password reset and device-scoped sign-out. Tokens stay in native secure storage under a separate Brain namespace.
- Shared `general` agent behaviors and memories; typed entries, device dictation and reviewed file suggestions. Saving and deletion require an explicit review action. Undo is available for the most recent change in this app session.
- Rici live voice through the authenticated SDP endpoint. Server usage limits are enforced. Microphone tracks stop on exit, disconnect, cancellation, account change or backgrounding. No external-action tools or automatic memory writes are exposed in conversation.
- Approved hollow brain, Matrix animation, cyan precision dials, Halo Capsule Talk button, Magnetic Key Train/My Brain buttons, memory-chip Add Memory, long silent lightning, reduced-motion/pause controls and 1% crystal-bell ambience.
- A bundled interface with no remote scripts, no browser access to tokens, a restricted native command bridge and external navigation blocked inside the authenticated WebView.

## Run and verify

Requires Flutter 3.47.9 (Dart 3.13.7), Java 17 and the Android SDK, or macOS/Xcode for iOS. The shared `packages/korlix_receipt_core` directory must be present.

```sh
cd apps/korlix_brain
flutter pub get --enforce-lockfile
npm ci --ignore-scripts
npm test
flutter analyze --no-pub
flutter test --no-pub
flutter run
flutter build apk --debug --no-pub
```

In automated environments set `CI=true`, `FLUTTER_SUPPRESS_ANALYTICS=true` and `DART_SUPPRESS_ANALYTICS=true`. CI mode also skips Flutter's cloud metadata environment detection. On containers that cannot restore archive ownership, set `TAR_OPTIONS=--no-same-owner`.

The default API is the existing KORLIX backend. To test against staging, supply `--dart-define=KORLIX_BACKEND_URL=https://your-staging-host` to Flutter. Do not embed service-role or model API keys. The backend must provide account auth, persisted agent profiles/memories, file analysis, realtime SDP and usage metering.

## Verification and release limits

Local checks cover 16 auth/repository cases and 7 interface cases, including failed saves, duplicate taps, stale behaviors, separate deletion/undo, native bridge mappings, safe transcript rendering and animation pause. They use controlled fixtures and do not modify a real account.

Physical-device microphone, speech permission, Bluetooth routing, live paid-plan usage, background interruption and real-account persistence still require a device acceptance pass. Automated native build artifacts are test packages, not store submissions. iOS simulator output cannot be installed on an iPhone; device distribution needs the existing Apple signing/release process.

The current server has no atomic compare-and-swap operation for behavior updates. The app rejects an already stale edit before writing, but two devices can still race between the check and write. A server revision precondition is needed before claiming conflict-proof concurrent editing. Undo is session-local, and memory restoration can create a new server ID.

Voice uses the selected agent's existing memory setting and the backend's runtime memory selection. This app edits shared general-agent memory, not an isolated local model. File analysis consumes the existing account allowance and returns a draft; the source file is not automatically saved as memory.

## Assets

The approved interface and audio are bundled in `assets/web`. Rajdhani's license is included there. Lucide 0.468.0 is vendored with its license. Launcher branding reuses existing KORLIX artwork.
