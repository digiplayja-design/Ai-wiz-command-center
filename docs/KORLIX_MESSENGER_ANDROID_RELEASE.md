# KORLIX Messenger Android release preparation

The owner reported the Android test app worked on October 24, 2026 (America/New_York). The next candidate keeps the approved yellow/navy icon and colorful multi-conversation inbox. It uses the existing KORLIX account and separate Messenger session.

Package: `com.korlixdeveloper.messenger`. The existing APK is a debug installation test. No signed Messenger AAB has been produced or submitted to Google Play.

## Prepared build workflow

`.github/workflows/korlix-messenger-android-release.yml` runs only for an explicit workflow dispatch or a push to the dedicated `release/korlix-messenger-android` branch. It validates the dedicated signing input and public Firebase client, runs Flutter analysis/tests, builds a signed AAB, verifies its JAR signature and records SHA-256. Only the AAB, signature check and checksum are uploaded. Private inputs are removed at job end. The workflow does not upload to Google Play or publish automatically.

Set these secrets in GitHub's `korlix-messenger-android-release` environment before promoting the reviewed Messenger commit to the dedicated release branch:

| Secret | Required value |
| --- | --- |
| `KORLIX_MESSENGER_ANDROID_KEYSTORE_BASE64` | Base64 encoding of a dedicated Messenger upload keystore |
| `KORLIX_MESSENGER_ANDROID_STORE_PASSWORD` | Keystore password |
| `KORLIX_MESSENGER_ANDROID_KEY_ALIAS` | Messenger upload-key alias |
| `KORLIX_MESSENGER_ANDROID_KEY_PASSWORD` | Key password |
| `KORLIX_MESSENGER_GOOGLE_SERVICES_JSON` | Public Android client JSON for the Messenger package; raw JSON, not base64 |

Keep an owner-controlled backup of the upload key. Do not reuse the KORLIX AI hub key or a debug key. No key has been generated or provisioned by this workflow preparation.

The Firebase validator accepts only the selected KORLIX app package, checks project/client identifiers and rejects service-account keys, tokens and private material. `--required` makes release preparation fail if configuration is absent; optional developer builds retain the disabled-provider behavior. Existing hub builds keep their original default package.

GitHub's manual-dispatch UI requires the workflow on the default branch; this repository's default branch is older than Messenger. The dedicated release-branch trigger allows an initial candidate without replacing the default branch. Create/update that branch only after the required configuration is provisioned. Subsequent manual runs can use the registered workflow. See [GitHub trigger documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch).

The workflow's default candidate is version name `0.1.0`, version code `2`; choose an unused, increasing code before upload. Signing and AAB construction remain untested until the actual credentials exist.

### Workflow definition correction

GitHub run `40153397217` rejected the release workflow before creating any jobs: `runner.temp` was used in job-level `env`, where the `runner` context is unavailable. The upload-keystore path now lives in the three step-level environments that need it. The dedicated workflow check validates all three Messenger workflow expressions and contexts with checksum-pinned actionlint 1.7.12, then runs the 11 Firebase configuration tests without requiring signing credentials. Both checks passed locally and in [GitHub run 40154666438](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40154666438) for commit `83c0ba48f682417730cf72cab2475b9aa6473192`. Basic YAML parsing alone did not detect the original context error.

The FCM-enabled native source set also compiled in an isolated Android debug build using a synthetic, nonfunctional client configuration. Both `KorlixPushProvider` and `KorlixFirebaseMessagingService` classes were produced. This checks SDK/source compatibility only, not real Firebase connectivity or delivery. The fixture configuration and APK outputs were removed, and no new APK was distributed. The pinned Flutter/Android toolchain emitted existing Kotlin-plugin migration and SDK XML compatibility warnings; the build completed successfully.

## Remaining connected setup and device verification

The Firebase plugin could not connect. With the owner's approval, Firebase Console registered `KORLIX Messenger` (`com.korlixdeveloper.messenger`) in the existing `korlix-ai` project. Its Firebase app ID is `1:830884744891:android:3194542789b28dd8e1e39e`; the Cloud Messaging v1 API is enabled.

The browser could not retrieve `google-services.json` from either the registration wizard or app settings, and the Google Cloud service-account page remained unavailable after one reload. The owner can obtain the public Android client file from [Messenger app settings](https://console.firebase.google.com/project/korlix-ai/settings/general/android:com.korlixdeveloper.messenger). Actual-project client compilation and real-device push verification remain pending.

Configure the matching server provider using `MESSENGER_NATIVE_*` variables and a dedicated private server-only FCM credential. Native push server integration is tracked in the backend branch's `docs/KORLIX_MESSENGER_PUSH_2026-10-25.md`. No server credential, IAM grant, or provider activation has been created by this registration.

After configuration, build the signed candidate and use Google Play internal testing. Verify two accounts across Messenger and KORLIX Social: messages/unread state, media, permission denial, foreground/background notifications, taps/replies, logout isolation, reinstall, and audio/video calls. The existing APK does not include Firebase registration. A successful owner test does not establish all of these scenarios.

Complete the Play listing, privacy/data declarations and review requirements against the final app behavior before production rollout. No paid Messenger tier or subscription has been added.
