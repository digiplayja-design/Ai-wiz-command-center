# KORLIX Messenger Android release

Updated October 25, 2026 (UTC). Package: `com.korlixdeveloper.messenger`.

## Current candidate

A signed Android App Bundle has been built as **1.0.0 / version code 3**. Its filename is `KORLIX-Messenger-1.0.0-build3.aab`; size is 85,080,643 bytes; SHA-256 is `616e37207d32565f5354d5aea059966041ccf3e09e2ee62258c8e57f0d58f938`. The owner has a private copy of the release artifact, store assets and upload-key backup.

The bundle uses a dedicated Messenger RSA-3072 upload key, distinct from both the hub and the test APK. Public upload-certificate SHA-256: `35ef7904721695155160430e265765dc7bda73ff3d9018e94f9aaadc2f66b4c3`. Private keys and credentials are not in this repository. Keep the owner-controlled backup for future releases. Google Play app-signing enrollment has not yet occurred.

The version label in Account & help now reads the installed package version and build number. The app and release-workflow defaults are 1.0.0+3.

Verified for the final bundle:

- Flutter analysis: no issues; all 18 Messenger tests passed.
- Official bundletool 1.18.3: bundle validation passed; its downloaded tool checksum matched the official release digest.
- JAR signature verified against the dedicated upload certificate. The self-signed certificate has the ordinary Android upload-key trust/timestamp warnings; archive validation passed.
- Package and version match; `debuggable` is false; minimum Android API 24, target API 36.
- Bundle configuration requests 16 KB native alignment; all ten ARM64/x86-64 native libraries have at least 16 KB load-segment alignment.
- Actual Messenger Firebase app ID and approved icon are embedded in the bundle.

See `evidence/korlix-messenger-play-build3-20261025.json` for checksums, native alignment and merged permissions. This is build validation, not an exhaustive device test or evidence of Play approval.

## Push and owner testing

Firebase project `korlix-ai` has the Messenger client `1:830884744891:android:3194542789b28dd8e1e39e`. The validated public client configuration is supplied outside git. No server private credential is packaged in the app.

The production backend at commit `f31c922ce3003f8e05e99746c5a7ae77c06b00c1` now has Messenger FCM enabled through its dedicated server-only sender account. Render deployment `dep-dben7l5g1s2s7384p7ug` became live at 03:13:58 UTC on October 25. Runtime readiness reported Messenger enabled and the hub provider disabled. Eleven routing/access checks passed and an FCM validate-only request succeeded; the validate-only request did not deliver a notification.

The owner subsequently reported **“Passed”** for the Samsung background-notification test using Firebase test build 2, and instructed submission to Google Play. Record this as an owner-reported pass for that test. It does not establish every foreground/background call, denied-permission, reinstall, notification-reply or two-account scenario. Build 3 is signed with the release upload key, while the tested build 2 uses the earlier debug key; they are separate signing identities.

## Store preparation and current blocker

Google Play Console has no existing Messenger listing. The new-app form is prepared in developer account `4772708594176030332` with KORLIX Messenger, package `com.korlixdeveloper.messenger`, English (United States), App and Free. The two legally binding declarations—Developer Program Policies and US export laws—remain unchecked pending action-time owner confirmation. The Create app button has not been submitted. **No AAB has been uploaded and no release has been submitted.**

Prepared listing assets include the approved 512px icon, a 1024x500 feature graphic, two 1080x1920 opaque RGB screenshots, English store descriptions and release notes. Screenshots are direct renders of the implemented Flutter UI using synthetic conversation examples; they are not evidence of live messages. Communication is the proposed category. No paid Messenger tier or ads integration has been added.

Five public policy pages now explicitly cover independent Messenger: privacy, deletion, terms, community guidelines and child-safety standards. Native FCM token/routing data, optional notification controls and retention are disclosed. Account-deletion instructions identify Account & help → Request KORLIX account deletion and explain the shared account scope. Website commit `e38d6b73a37ff812a29da3b64027a35e01979c34` is based on the prior live website commit. See `evidence/korlix-messenger-public-policies-20261025.json` for deployment and live-page verification.

After owner confirmation, create the app and finish the actual Console requirements: app signing, listing uploads, app-access/reviewer instructions, content rating, target audience, Data safety, foreground-service use cases and any other required declarations. Confirm collection/sharing answers against all included SDKs and the actual Console questions. Review-account credentials and any required video evidence have not yet been supplied. Do not claim production readiness, review submission or a public Play URL until Console confirms those states.

## Reproducible release workflow

`.github/workflows/korlix-messenger-android-release.yml` runs on explicit dispatch or a push to the dedicated `release/korlix-messenger-android` branch. It validates dedicated signing input and the package-specific public Firebase client, runs analysis/tests, builds the signed AAB, verifies the JAR signature and records SHA-256. It does not upload to Play automatically.

The GitHub environment `korlix-messenger-android-release` exists with deployment limited to the dedicated release branch. `KORLIX_MESSENGER_GOOGLE_SERVICES_JSON` is already provisioned. The four signing secrets below remain unprovisioned in GitHub; the dedicated release branch has not been created. The current AAB was built locally using the private upload key.

| Secret | Value required |
| --- | --- |
| `KORLIX_MESSENGER_ANDROID_KEYSTORE_BASE64` | Dedicated Messenger JKS encoded as base64 |
| `KORLIX_MESSENGER_ANDROID_STORE_PASSWORD` | Keystore password |
| `KORLIX_MESSENGER_ANDROID_KEY_ALIAS` | Messenger upload-key alias |
| `KORLIX_MESSENGER_ANDROID_KEY_PASSWORD` | Key password |
| `KORLIX_MESSENGER_GOOGLE_SERVICES_JSON` | Validated public Android client JSON, already provisioned |

Do not use the KORLIX AI hub key or a debug key. Do not put a Firebase service-account credential in the client configuration. Provision signing secrets through approved secret storage before triggering CI. The existing repository default branch predates Messenger; do not replace it wholesale to expose manual dispatch.

The workflow's earlier job-level `runner.temp` expression error was fixed by moving that path into step-level environments. Actionlint 1.7.12 and the 11 Firebase-configuration tests passed in GitHub run [40154666438](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40154666438). Actionlint was rerun for the current default-version edits. The pinned toolchain still emits future Kotlin-plugin migration and SDK XML warnings; both release builds completed successfully.
