# KORLIX Messenger

Independent Flutter client for KORLIX Social. App ID: `com.korlixdeveloper.messenger`; working product name: KORLIX Messenger. Existing KORLIX credentials, profiles, connections and conversations are reused. Main Social remains available in KORLIX AI.

Approved Messenger branding: the yellow KORLIX circuit-face emblem inside a navy chat bubble. `assets/korlix_messenger_icon.png` is the source for the Android/iOS/web launcher assets and the sign-in header. Regenerate platform sizes with `dart run flutter_launcher_icons` from this directory.

Run from this directory with `flutter pub get` and `flutter run`. Use `--dart-define=KORLIX_BACKEND_URL=https://...` for an approved test backend. The Messenger account API namespace deliberately returns an unavailable message on older backends; it must not consume a hub device slot.

Shared code lives in `packages/korlix_social_core`; `lib/social` in the hub forwards to it. Chats, groups, media, calls, read receipts, themes, blocking and reporting retain existing server checks. Companion login binding is restricted to Social/account operations. An account-deletion request affects the shared KORLIX account, and the UI explicitly explains that scope.

Status: source published, companion migrations applied and backend live. Android and iOS simulator CI builds passed. The Android debug APK is ready for owner testing with existing KORLIX credentials. Store submission, signed release builds and two-device call verification remain pending. See `docs/KORLIX_MESSENGER_2026-10-24.md` at the repository root for deployment and validation evidence. Android Firebase client registration, native-push backend/provider setup, Apple push entitlements and signed-device tests are release prerequisites. Native platform notification controls report unavailable when those providers are not configured. Web push requires the existing server VAPID configuration and this app's included worker.

## Native release

Android: build debug APK with `flutter build apk --debug`. Release builds require a dedicated Messenger keystore (`android/key.properties` or `KORLIX_MESSENGER_ANDROID_*`); never use the hub's keystore implicitly. Configure public Firebase Android client JSON for the Messenger package, not a service-account key. Verify microphone/camera permissions, foreground/background calls, notification taps/replies, bubbles, sign-out and reinstall on actual devices.

iOS: use a macOS/Xcode runner, register the Messenger bundle ID, and provision its own signing/push capabilities. Base entitlements do not enable remote push. Run `flutter build ios --no-codesign` before a signed archive; background call/notification behavior requires a real-device test. The app shares account data but not installation credential storage with KORLIX AI.
