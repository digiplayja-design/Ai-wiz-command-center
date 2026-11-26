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

### Apple: live

Version 12.0.6 is publicly available on the [App Store](https://apps.apple.com/us/app/korlix-ai/id6783100102).
Apple's public lookup reports `currentVersionReleaseDate=2026-11-20T17:54:06Z`
and the Christmas/model release notes for the correct bundle ID.

[Codemagic release build](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6affbdcf8f52ca275129275e)
produced the signed 12.0.6 (146) IPA using the existing
KORLIX_APP_STORE_PROFILE and KORLIX_APP_STORE_CERT.
Verified IPA: 84,427,275 bytes, SHA-256
`dddf3be7a92182c77d6a0503b2b1774b5ace9fae7abc22410c60abdcc6db78a7`.
Upload delivery UUID: `6707a875-9d8b-4209-b97c-c74a7155437b`.
Review submission: `4ed5701d-c412-4afd-acee-83fc26bb9755`.
App Store version record: `9789c73d-0707-489d-bda6-a49e06163243`.
The signed artifact identity is preserved in `apple-verification.json`.

### Android: signed release verified; Google upload pending

The original main-app upload key was recovered and reused without modification.
The signed release was built from
`667968e87a4037ad25a002dff4a930cef636ab43` with Flutter 3.47.7
(`abaf9c523780a608bd46686fd5e53740a07077f8`) and locked dependencies.
Build caches and SDK were isolated from the original working tree.
The existing Firebase client configuration and the main project's public client
definitions were retained. Eleven Firebase preparation tests passed.

Verified artifact: `Korlix-AI-12.0.6-146.aab`, 165,005,481 bytes.
SHA-256: `bede93e0e439d7694ff4b9d16d527a9b95a70439811a1baad20264edaf43d657`.
Upload certificate SHA-256:
`c1d051456057e6d813f0d4e82892b856c3e67852b05cd78d302adc5da8162f7f`.
Package: `com.korlixdeveloper.korlixai`; version: `12.0.6` / `146`;
minimum SDK: `24`; target SDK: `36`; debuggable: `false`.
The certificate matches the original main-app key, JAR signature verification
passed, and official bundletool 1.18.3 validation passed.
A complete rebuild reproduced the identical SHA-256.
The exact verified bundle has been retained privately for delivery recovery.

Google Play production is still 12.0.5 (145), fully rolled out to the existing
178 countries. Production draft 14 is saved as
`146 (12.0.6) Christmas and AI upgrade` with release notes.
Google's available-bundle library was checked after the interrupted transfer:
version 146 was not received. No Google review submission is confirmed yet.
The remaining delivery step is uploading the retained verified bundle to this
draft, reviewing Google's validation, and sending the release for review.
GitHub and Google authentication are resolved; the upload key must not be
replaced or substituted with another app's key.

## Official migration sources

- https://developers.openai.com/api/docs/guides/latest-model
- https://developers.openai.com/api/docs/guides/image-generation
- https://developers.openai.com/api/docs/models/gpt-6.2-astra
- https://developers.openai.com/api/docs/models/gpt-image-2.6-sunburst
