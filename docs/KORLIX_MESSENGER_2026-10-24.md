# KORLIX Messenger — implementation record

Date: October 24, 2026 (America/New_York). Working product name: KORLIX Messenger. Requested by Ricardo: a detached, independently installed instant messenger connected to KORLIX Social, analogous to a social network and its separate messaging app.

## Implemented locally

- Independent Flutter application at `apps/korlix_messenger`, version 0.1.0+1, Android/iOS identifier `com.korlixdeveloper.messenger`, branded launcher assets and web manifest.
- Same KORLIX email/password, duplicate-signup recovery, password reset, age/policy declarations and explicit shared-account deletion scope.
- Namespaced native/browser credentials and per-installation identity. Signing out clears this app only. Old app servers cannot silently treat Messenger as a hub login: account requests use `/api/messenger/` and fail closed until deployed.
- A shared Social package replaces the hub's original Dart implementations with export shims. It contains the existing conversations, groups, voice notes, attachments, GIFs/stickers, calls, read receipts, appearance, notification routing and safety controls. Assets have one package-owned source; the reaction generator writes to it.
- Messenger starts on Chats; primary navigation is Chats, Groups, People. Calls, themes, invitations, profile/notification controls and account help remain available. The hub retains its existing Wall-first navigation.
- Android/iOS native Social and sound bridges under the new app identity. Android floating-chat engine reads only Messenger credentials and its device binding. Provider configuration is absent and is not simulated as enabled.
- Read-only mobile build workflows for Android debug and iOS simulator, with no store-publishing steps.

## Backend companion changes

Prepared separately in `feature/korlix-messenger-backend-20261024` in a backend worktree of the same KORLIX monorepo. Migration `20261025004400_korlix_messenger_app_sessions.sql` adds an app discriminator to the existing server-only companion-session table, preserves Receipt Wiz sessions, and scopes per-plan device slots separately for each companion. Provider-verified login IDs bind app scope and installation; a changed header cannot widen access. Messenger sessions permit Social and namespaced account operations, not AI generation or receipt APIs. Existing Social profiles and conversations are reused without a data copy.

The migration was generated with the Supabase CLI and tested in isolated PGlite. It has **not** been applied to a live Supabase project; live advisors and deployment remain release checks. No real account signup, message, call, invitation or support email was sent during testing.

## Validation

- Existing Flutter Social regression suite: 346 passed.
- Messenger auth/storage/accessibility suite: 18 passed.
- Messenger navigation and synthetic inbox checks: 5 passed; these are also included in the shared UI run.
- Shared themes, reaction assets, sound, navigation and appearance checks: 74 passed; one optional appearance-export test skipped.
- Existing secure-token/session HTTP regression checks: 42 passed.
- Backend companion/auth/signup/security checks: 54 passed.
- Backend Social/communication checks: 89 passed. An existing group-read test failure was reproduced in the unchanged backend checkout and fixed by loading the already-existing read-receipt migration in its fixture. No live group-read behavior was changed.
- Standalone and shared-core Dart analysis passed with no issues. Web release compilation and the Wasm dry run passed.
- Synthetic sign-in, duplicate-account and inbox screenshots in `docs/evidence/korlix-messenger-20261024/`. They are render evidence, not proof of a live two-account test.

## Approved icon update

The user approved the yellow-and-navy Messenger icon after reviewing its concept. The exact approved source is now used for Android, iPhone/iPad, web icons and the sign-in header. Platform assets were regenerated; five Android densities, 25 iOS icon records (including opaque 1024px store artwork), and four web icon sizes were validated. The eight existing auth-screen/accessibility checks and the updated web release build passed, and the sign-in screenshot was refreshed.

## Not released / remaining

The code is local and is not merged, deployed or submitted to Google Play or the App Store. Android SDK/NDK and a locally installed, checksum-verified JDK now allow a debug APK to compile successfully. Its package ID, app label, platform versions, embedded approved icon and v2 signature were checked. This is a developer-signed installation test, not a Play Store release or a physical-device messaging test. iOS compilation still requires a macOS/Xcode runner; native CI workflows are prepared but have not run on the new branch.

The approved multi-conversation design is implemented: compact colorful rows, latest-message previews, timestamps, unread badges, All/Unread/Requests filters and search. Voice-note previews include duration, outgoing previews identify “You”, and large-text layouts move metadata below the preview. A dedicated backend inbox RPC sorts by latest visible message, filters before pagination and preserves block, suspension and self/everyone dump rules. It requires the additional `20261025011508_korlix_messenger_inbox.sql` migration and backend route deployment. The hub's original connections API remains unchanged. The screenshot `messenger-conversations.png` uses synthetic data rendered by the implemented Flutter UI.

Latest inbox checks: 22 Flutter tests passed (including 320px/doubled-text layouts), 128 backend regression checks passed (including nine inbox SQL/HTTP/privilege tests), and Dart analysis and web compilation passed. The Android build emits compatibility warnings about future Flutter versions removing legacy Kotlin-plugin support; this version builds with the project's pinned toolchain.

The final Android debug package is `KORLIX-Messenger-0.1.0-android-test.apk` (236,163,387 bytes; SHA-256 `635bec012466473e5ffc587eb536a6e0008bdb8c4739314cfde205e883e8a608`). It supports Android API 24+ with ARM64, ARMv7 and x86-64 binaries. ZIP integrity, every native library's ELF section/program bounds, the v2 signature, the exact approved icon, and the current inbox source embedded in the Dart kernel were verified. The final incremental build reported native stripping warnings and retained valid native binaries; physical-device startup has not been verified. Sign-in is blocked until the companion backend is deployed, so this APK is for installation and sign-in-screen inspection only.

GitHub upload has not been retried. The existing `digiplayja-design/Ai-wiz-command-center` repository was confirmed public. The prior POS implementation record documents an automatic approval review rejecting source upload without explicit authorization; the prepared Messenger source remains local pending that authorization.

Before public testing: review and deploy backend migration/API, run Android and iOS native build workflows, configure separate Firebase/Apple push application registrations and the native-push backend, provide app-specific signing, and test two accounts across the hub and Messenger. Verify foreground/background messages, notification taps/replies, audio/video calls, logout isolation, reinstall, permission denial and unread synchronization. Until then, no claim of background delivery or completed native integration is made. No pricing or paid Messenger tier has been configured.
