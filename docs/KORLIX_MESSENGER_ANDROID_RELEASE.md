# KORLIX Messenger Android release preparation

The owner reported the Android test app worked on October 25, 2026. The next candidate keeps the approved yellow/navy icon and colorful multi-conversation inbox. It uses the existing KORLIX account and separate Messenger session.

Package: `com.korlixdeveloper.messenger`. The existing APK is a debug installation test. No signed Messenger AAB has been produced or submitted to Google Play.

## Prepared build workflow

`.github/workflows/korlix-messenger-android-release.yml` is manual-only. It validates the dedicated signing input and public Firebase client, runs Flutter analysis/tests, builds a signed AAB, verifies its JAR signature and records SHA-256. Only the AAB, signature check and checksum are uploaded. Private inputs are removed at job end. The workflow does not upload to Google Play or publish automatically.

Set these secrets in GitHub's `korlix-messenger-android-release` environment before running it on the reviewed Messenger source branch:

| Secret | Required value |
| --- | --- |
| `KORLIX_MESSENGER_ANDROID_KEYSTORE_BASE64` | Base64 encoding of a dedicated Messenger upload keystore |
| `KORLIX_MESSENGER_ANDROID_STORE_PASSWORD` | Keystore password |
| `KORLIX_MESSENGER_ANDROID_KEY_ALIAS` | Messenger upload-key alias |
| `KORLIX_MESSENGER_ANDROID_KEY_PASSWORD` | Key password |
| `KORLIX_MESSENGER_GOOGLE_SERVICES_JSON` | Public Android client JSON for the Messenger package; raw JSON, not base64 |

Keep an owner-controlled backup of the upload key. Do not reuse the KORLIX AI hub key or a debug key. No key has been generated or provisioned by this workflow preparation.

The Firebase validator accepts only the selected KORLIX app package, checks project/client identifiers and rejects service-account keys, tokens and private material. `--required` makes release preparation fail if configuration is absent; optional developer builds retain the disabled-provider behavior. Existing hub builds keep their original default package.

The workflow's default candidate is version name `0.1.0`, version code `2`; choose an unused, increasing code before upload. The workflow syntax and Firebase validator are checked locally, but signing and AAB construction remain untested until the actual credentials exist.

## Remaining connected setup and device verification

Install/connect the suggested Firebase plugin to register the Messenger Android client in the owner's Firebase project. Configure the matching server provider using `MESSENGER_NATIVE_*` variables and a private server-only FCM credential. Native push server integration is tracked in the backend branch's `docs/KORLIX_MESSENGER_PUSH_2026-10-25.md`.

After configuration, build the signed candidate and use Google Play internal testing. Verify two accounts across Messenger and KORLIX Social: messages/unread state, media, permission denial, foreground/background notifications, taps/replies, logout isolation, reinstall, and audio/video calls. The existing APK does not include Firebase registration. A successful owner test does not establish all of these scenarios.

Complete the Play listing, privacy/data declarations and review requirements against the final app behavior before production rollout. No paid Messenger tier or subscription has been added.
