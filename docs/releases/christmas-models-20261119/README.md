# KORLIX AI 12.0.6 — model and Christmas update

Scope: main KORLIX AI Android and iOS app, package/bundle ID
`com.korlixdeveloper.korlixai`. Other standalone apps are not being released.

## Implemented

- Shared backend reasoning: `gpt-6.2-astra`, maximum reasoning effort.
- Image generation: `gpt-image-2.6-sunburst`, xhigh quality; editing: max quality.
- Main hub default: Christmas Red & White, with static edge snowflakes,
  a seasonal greeting, and red action controls. Saved user palettes still win.
- Shared theme package keeps its prior default for standalone apps.
- Model headers match the new policy, and live-document proof accepts both
  Astra identifiers during rollout. Specialized realtime audio is unchanged.

## Verified backend

PR #74: https://github.com/digiplayja-design/Ai-wiz-command-center/pull/74

Production branch: `release/signup-plan-intent-20261021`.
Merged commit: `1b4020924abb89a222bea5feb6f404e1ed408b8a`.
Render service: `srv-d8csvkkp3tds73emfikg`, confirmed existing workspace
`tea-d8cskuf7f7vs73emq1p0`.
Deployment `dep-dbvrpbijnfac7387ucdg` is live. `/api/health` reports both new
models, the intended quality settings, and both model catalogs visible.
This is configuration/access verification, not a paid generation smoke test.
442 targeted backend tests passed. The separate repository backend regression
workflow also passed: run `44666727623`.

## Mobile source and validation

PR #75: https://github.com/digiplayja-design/Ai-wiz-command-center/pull/75

Branch: `upgrade/korlix-ai-mobile-20261119`.
Application and release source: `8120a3e55eaa79080d8e31c7ab6e81e986636aa6`.
The source tree was compared exactly with the locally prepared tree before
publishing through the connected GitHub API. The mobile baseline is the latest
main-app reporting fix, not the older website deployment branch.

109 Flutter tests passed, with one existing optional export test skipped.
Coverage includes 130 palette/skin combinations, WCAG text contrast assertions,
explicit saved preferences, phone/tablet layout, 2x text, billing and reporting.
The actual welcome component was rendered and visually inspected.
11 Python Apple release-identity/artifact checks passed. Android debug APK and
iOS simulator compilation both passed in validation run `44668912910` at source
`da038d75f7be5a924894a014f6a12539b43b6157`.

A Gradle init script supplies Maven Central directly for included-build plugin
resolution, fixing the observed Kotlin dependency lookup failure without a
dependency version change. The Android validation artifact is
`korlix-christmas-android-validation`, artifact ID `14599129328`, archived at
172,271,541 bytes with SHA-256
`716966330ad4700b92bdaf1671f9c1339e164484ce20aacd28f5da1aeb0f8e6e`.
This debug APK verifies compilation; it is not the signed Play release bundle.
For a signed Android build, install
`scripts/gradle-public-repositories.init.gradle` under the isolated build
user home at `.gradle/init.d/korlix-public-repositories.gradle`.

CI: https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/44668912910
Metadata endpoints are blocked before the Flutter CLI runs in validation;
signed Apple release commands use a scoped firewall anchor that preserves the
builder's existing firewall rules.

## Store delivery status

Google Play was inspected on November 19, 2026. Production is version 12.0.5
(145), fully rolled out to the existing 178 countries. The new source version is
12.0.6 (146); no Google release has been created or uploaded in this update yet.

The original main-app upload key is in the existing Codespace, not the Brain
or Copybox keystores shown in Codemagic. Required main-app upload certificate:
`c1d051456057e6d813f0d4e82892b856c3e67852b05cd78d302adc5da8162f7f`.
The Codespace requires GitHub authentication. Automatic approval review rejected
that sign-in pending explicit user authorization. Do not change or replace the
upload key, and do not reuse another app's signing identity.

Before the signed Android build, recheck all Play tracks/drafts for the highest
version code and preserve the existing public client definitions and optional
Firebase client configuration from the signing workspace. Version 146 is
already in `pubspec.yaml`; the older `build-google-play-billing.sh` wrapper
rejects an equal next version, so build this release directly with the verified
version rather than silently incrementing it. Install the Gradle init script
described above, resolve the locked dependencies, prepare the existing Firebase
client file, and use `flutter build appbundle --release --build-name=12.0.6
--build-number=146 --dart-define-from-file=<existing-public-client-json>`.
Verify the resulting bundle's application ID, version, and upload certificate
before uploading. Recheck the version if the Play state changes meanwhile.

Apple build: https://codemagic.io/app/6a32198d2d0806059c3df062/build/6affbdcf8f52ca275129275e

The build verified existing Apple app `6783100102`, bundle ID, and latest Apple
build 136/version 12.0.4, then selected 12.0.6 (146). It uses the existing
KORLIX_APP_STORE_PROFILE and KORLIX_APP_STORE_CERT. Its workflow tests,
compiles, signs and verifies the IPA before attempting App Store submission.
The signed IPA passed verification: 84,427,275 bytes, SHA-256
`dddf3be7a92182c77d6a0503b2b1774b5ace9fae7abc22410c60abdcc6db78a7`.
Apple upload succeeded without errors on November 19, 2026 (New York), delivery
UUID `6707a875-9d8b-4209-b97c-c74a7155437b`. Processing completed and the release
was submitted to App Review at 10:38 PM New York on November 19, 2026
(`2026-11-20T03:38:15.461Z`). Final observed state: `WAITING_FOR_REVIEW`.
This confirms submission, not Apple approval or public availability.

Review submission: `4ed5701d-c412-4afd-acee-83fc26bb9755`.
App Store version: `9789c73d-0707-489d-bda6-a49e06163243`.
The signed artifact identity is preserved in `apple-verification.json`.

## Official migration sources

- https://developers.openai.com/api/docs/guides/latest-model
- https://developers.openai.com/api/docs/guides/image-generation
- https://developers.openai.com/api/docs/models/gpt-6.2-astra
- https://developers.openai.com/api/docs/models/gpt-image-2.6-sunburst
