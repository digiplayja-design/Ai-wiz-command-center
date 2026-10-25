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

Prepared separately in `feature/korlix-messenger-backend-20261024` in a backend worktree of the same KORLIX monorepo. Migration `20261025014426_korlix_messenger_app_sessions.sql` adds an app discriminator to the existing server-only companion-session table, preserves Receipt Wiz sessions, and scopes per-plan device slots separately for each companion. Provider-verified login IDs bind app scope and installation; a changed header cannot widen access. Messenger sessions permit Social and namespaced account operations, not AI generation or receipt APIs. Existing Social profiles and conversations are reused without a data copy.

Both migrations were generated with the Supabase CLI and tested in isolated PGlite, then applied to the KORLIX Supabase project after Ricardo approved source publication and continued deployment. Their files use the actual applied versions and their SQL matches byte for byte. Live security checks confirmed RLS and service-only invoker RPCs; advisors reported no warnings or errors. No real account signup, message, call, invitation or support email was sent during testing.

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

## Release progress and remaining checks

The frontend source is published in `feature/korlix-messenger-20261024` at `b8723646ce97effc173243339268b336003918f7`. Only the prepared Messenger changes were added to the current Receipt Wiz frontend baseline; unpublished POS changes were excluded. The backend is live at `4a4995da3f729b150c6978f83ee6fd45c3d5097e`. Messenger has not been submitted to Google Play or the App Store. Android SDK/NDK and a locally installed, checksum-verified JDK now allow a debug APK to compile successfully. Its package ID, app label, platform versions, embedded approved icon and v2 signature were checked. This is a developer-signed installation test, not a Play Store release or a physical-device messaging test. GitHub Actions run [40151788140](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40151788140) completed successfully for both Android and iOS simulator jobs on source commit `b8723646ce97effc173243339268b336003918f7`. Android analysis reported no issues and all 18 app tests passed before compilation. The APK artifact is `12582577999`; the iOS simulator artifact is `12583141954`. The simulator artifact cannot be installed directly on an iPhone or iPad.

The approved multi-conversation design is implemented: compact colorful rows, latest-message previews, timestamps, unread badges, All/Unread/Requests filters and search. Voice-note previews include duration, outgoing previews identify “You”, and large-text layouts move metadata below the preview. A dedicated backend inbox RPC sorts by latest visible message, filters before pagination and preserves block, suspension and self/everyone dump rules. Its `20261025014427_korlix_messenger_inbox.sql` migration and backend route are deployed. The hub's original connections API remains unchanged. The screenshot `messenger-conversations.png` uses synthetic data rendered by the implemented Flutter UI.

Latest inbox checks: 22 Flutter tests passed (including 320px/doubled-text layouts), 130 backend regression checks passed (including nine inbox SQL/HTTP/privilege tests and two auth-alias checks), and Dart analysis and web compilation passed. The Android build emits compatibility warnings about future Flutter versions removing legacy Kotlin-plugin support; this version builds with the project's pinned toolchain.

The final Android debug package is `KORLIX-Messenger-0.1.0-android-test.apk` (236,163,387 bytes; SHA-256 `635bec012466473e5ffc587eb536a6e0008bdb8c4739314cfde205e883e8a608`). It supports Android API 24+ with ARM64, ARMv7 and x86-64 binaries. ZIP integrity, every native library's ELF section/program bounds, the v2 signature, the exact approved icon, and the current inbox source embedded in the Dart kernel were verified. The final incremental build reported native stripping warnings and retained valid native binaries; the owner subsequently reported that the test app worked on October 25. The companion backend is now deployed, so this same APK is ready for the owner to test sign-in and live conversations using existing KORLIX credentials. All 267 tracked files in the standalone app and its shared packages match the published source. The owner reported the app worked; specific sign-in, two-account and background scenarios have not been independently observed.

Ricardo explicitly approved publishing the prepared source to the public `digiplayja-design/Ai-wiz-command-center` repository and continued backend deployment. The prior upload-authorization blocker is resolved. Render deployment `dep-dbelv67avr4c73bbp11g` became live at `2026-10-25T01:47:46.328278Z` with the expected backend commit. Eight live HTTP checks passed: health and auth configuration, Messenger credential/refresh validation, authentication on sign-out/deletion/inbox, method restrictions, and the original hub sign-in route. No runtime error logs were observed during the initial verification window. These are routing/access checks, not a two-account messaging test.

Before a public native release: configure separate Firebase/Apple push application registrations and the native-push backend, provide app-specific signing, and test two accounts across the hub and Messenger. Verify foreground/background messages, notification taps/replies, audio/video calls, logout isolation, reinstall, permission denial and unread synchronization. Until then, no claim of background delivery or completed native integration is made. No pricing or paid Messenger tier has been configured.

October 25 continuation: prepared a dedicated signed Android AAB workflow with dedicated Messenger signing, required package-specific Firebase client validation, artifact signature checking and checksums. All 11 Firebase configuration tests pass, including cross-app configuration rejection and private-key rejection; workflow YAML, Bash and Python syntax checks pass. Actual release construction awaits Firebase registration and upload-key provisioning. See `KORLIX_MESSENGER_ANDROID_RELEASE.md`. The backend native-push implementation now has app/session isolation and 251 passing Social/Messenger/companion regression checks; delivery remains disabled pending provider setup.

The native-push backend is live at `f31c922ce3003f8e05e99746c5a7ae77c06b00c1` (Render deployment `dep-dbem8npsrm7s73cjr2lg`, October 25 at 02:08 UTC). Eleven live HTTP checks passed. Both native provider flags were confirmed disabled by startup readiness; no background delivery is claimed. Firebase was still not installed/connected at the final connection check. The signed-AAB workflow supports a dedicated release-branch trigger so its initial run does not depend on replacing this repository's older default branch.


## October 25 Android store preparation

Messenger FCM is now enabled in production through the dedicated server-only sender, and the owner reported that the Samsung background-notification test passed. The owner requested Google Play submission. A separately signed 1.0.0+3 AAB, validated store assets and updated public policies are prepared. The Play app is created, the signed build 3 AAB is uploaded, and the default listing is ready for review. The owner approved policy/export declarations, IARC Terms and reuse of the dedicated reviewer login; those actions are complete. All eleven initial setup tasks are complete, including reviewer access, content ratings, a 16+ audience and final Data safety save. Production draft `1` in track `4697363913471912084` contains build 3 and release notes. The owner explicitly approved worldwide availability, all available countries and regions are saved, and the country error is cleared. Google now reports one release error: the required foreground-service declaration needs genuine Android background-call video evidence. No production review submission has occurred. This supersedes the earlier setup-pending status above. See `KORLIX_MESSENGER_ANDROID_RELEASE.md` and `evidence/korlix-messenger-play-console-20261025.json` for the current candidate and precise remaining requirements.
