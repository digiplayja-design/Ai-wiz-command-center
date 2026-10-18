# KORLIX Social floating chat and native notifications

## Included in this update

- Android 11+ conversations have **Keep this chat floating**. After the user
  enables notifications/bubbles, Android owns the movable bubble over other
  apps. Expanding it opens a compact authenticated chat for reading and replying.
  Android settings may suppress a bubble; the normal notification remains the
  fallback. Users can dismiss it at any time. There is no overlay permission.
- The expanded bubble uses a separate Flutter engine. It reads current secure
  credentials without changing them, validates the account and login session
  before and after requests, and never rotates refresh tokens. Expired sessions
  ask the user to open KORLIX. Logout invalidates pending bubble intents.
- Android FCM and iOS APNs registration and private notifications are supported
  when their build/provider configuration is enabled. Message text and names are
  excluded from notification previews. Opening a call alert never answers it.
- A native **Reply** action opens the authenticated app (and requires unlock on
  iOS). Only the user's explicit reply action sends text. Failed replies retain
  one message ID for safe retry; ordinary notification taps only navigate.
- Existing web push stays on its existing API and service worker. Native
  registrations use separate `native_push_*` routes and account bindings.

## Configuration and activation

Floating Android chat can be tested without FCM. New-message alerts while the
bubble is collapsed require native push delivery; an open bubble polls using
the existing authenticated chat API. This is not continuous background polling.

Android:

1. Use the existing KORLIX Firebase project, or create the intended project and
   register Android package `com.korlixdeveloper.korlixai` if none exists.
2. Place its public client `google-services.json` at
   `android/app/google-services.json` in the **existing Codespace checkout**.
   The isolated prepare/resume release scripts automatically validate it and
   copy it into the new build worktree. Alternatively, set
   `KORLIX_FIREBASE_ANDROID_CONFIG` to the downloaded public client JSON before
   running the release script. An explicit selection takes priority; an invalid
   or missing explicit file stops with an error. Do not use a service-account
   JSON file. The helper rejects private credentials and mismatched Android
   packages before copying, and never prints configuration values.
   The Gradle configuration includes FCM only when the client file is present.
   With no optional file, existing builds continue with FCM disabled. A resume
   retains and revalidates an already-copied client when the original is absent.
3. Configure the companion backend FCM provider using its documented private
   credential-file procedure. Never include a provider service-account key in
   the app or in a public download.
4. Install the signed build, enable Social notifications, then open a chat and
   select **Keep this chat floating**. Allow Android notifications/bubbles.

iPhone/iPad: follow `ios/SOCIAL_PUSH_SETUP.md` for the optional signing
entitlements, APNs environment and backend provider. Ordinary iOS signing is
unchanged by default. iOS cannot use the Android chat overlay; this update adds
supported message alerts/replies. Video-call Picture in Picture is not part of
this implementation.

The companion backend is staged in [draft PR #25](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/25)
and requires its additive native-push migration and release. Its release guide
documents the provider environment variables and private credential-file setup.
Provider setup, migration application, production deployment, signed-device
delivery and store rollout must be confirmed separately. Passing compilation
does not establish delivery or store publication.

## Validation and device checks

CI analyzes and tests the Social changes, compiles Android without FCM and with
a synthetic FCM configuration, and compiles an unsigned iOS simulator app. It
does not hold release signing keys, send real notifications or contact users.
The signed Codespace release gate also runs Firebase client-copy checks and
the native action, routing, settings, floating-chat and token-store tests in
addition to the existing onboarding, billing, voice and navigation checks.

Before store rollout, test on Samsung/Android and a physical iPhone/iPad:

- Deny notification/bubble permissions; normal app chat remains usable.
- Pin, collapse, expand and dismiss a direct and group chat; reply while another
  app is open. Do not mark messages read from a collapsed bubble.
- Send a new message while KORLIX is backgrounded, then cold-open its alert.
- Reply from a notification, retry a temporary failure, and confirm one message.
- Log out and log back in to the same account; old bubbles/actions stay invalid.
- Switch accounts; stale alerts cannot expose or send another account's data.
- Recheck Rici and Social calls, lock-screen Stop, and normal message sounds.

## Build and save from the browser

Use the existing isolated Codespace release procedure and a version code above
every Play track/draft. The last user-confirmed local build was **136**; verify
the highest uploaded code before choosing the next one. Keep the build's exact
source revision and required optional client push configuration together.

To select a public Firebase client file stored elsewhere, set this before the
existing prepare/resume command (replace the path with your real file):

```bash
export KORLIX_FIREBASE_ANDROID_CONFIG=/absolute/path/to/google-services.json
```

If the file is already at `android/app/google-services.json` in your original
Codespace checkout, no extra variable or manual worktree copying is needed. The
helper copies only this validated public client configuration; backend provider
keys remain on the backend. The AAB download helper remains unchanged.

After a successful signed build, use the existing helper:

```bash
python3 scripts/download-android-aab.py /absolute/path/to/app-release.aab --build-number NEXT_CODE --port 8790
```

In Codespaces **Ports**, forward **8790**, keep it **Private**, then **Open in
Browser**. Download the named AAB and choose **Save to Files** on the iPad. Leave
the terminal running until saving finishes; then press Ctrl+C. The helper only
serves the selected bundle, not the source tree or credentials.
