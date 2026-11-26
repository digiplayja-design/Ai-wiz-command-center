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

### Android: quick checks complete; Google review underway

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

On November 26, 2026, Google Play received the exact verified signed bundle.
The release preview identified version 146 (12.0.6), API 24+, target SDK 36,
4 screen layouts, 3 ABIs and 5 required features, and displayed
`Ready to release`. Google reported zero devices losing support across every
listed form factor. Estimated new-install download size is 69.3 MB.

Production release 14, `146 (12.0.6) Christmas and AI upgrade`, was saved with
the reviewed release notes, a 100% rollout, and all existing targeted countries.
The single production change was submitted through `Send changes for review`.
[Publishing overview](https://play.google.com/console/u/0/developers/4772708594176030332/app/4974117289022654668/publishing)
then displayed `Changes in review` and `Start full rollout` for this release.
A subsequent check on November 26 confirmed the quick-check phase had ended.
Publishing overview now states `Your changes are now in review. We may find
additional issues when reviewing your app.` No new issue or required action
was displayed for the submitted release.
Managed publishing remains off, so the approved update can publish automatically.
Approval and public availability of Android 12.0.6 are not yet confirmed;
12.0.5 (145) remains the last confirmed live Android release across 178 countries.

The upload blocker is resolved. No key replacement, country-distribution
change, or unrelated app release was performed.

## Internal testing

### Android: available

On November 26, 2026, internal track `4701415604792469412` published release
50, `146 (12.0.6) Christmas internal test`, using the same verified signed
bundle already in Google Play's artifact library. The track is active and
Google displays `Available to internal testers` for version code 146.
The existing selected tester lists were retained. An additional owner account
has not been enrolled; its access change is awaiting explicit authorization.

[Android internal test opt-in](https://play.google.com/apps/internaltest/4701415604792469412)
requires an enrolled Google account. Public production review remains separate.

### Apple: newer internal build already verified

The main app's newer **12.0.7 (148)** iOS build was uploaded on November 23,
2026. The existing verification run completed successfully and its sanitized
result states: `Verified the exact build is in the existing internal group and
in beta testing.` The verifier checked the exact app/bundle/version/build,
valid processing, non-expired status, and the existing internal group's actual
build relationship. It did not read tester identities or add tester accounts.

[Successful internal TestFlight verification](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6b048b81d17d55100e0f670c?open-step=build-step-3)
ran at source `41569f3c7ee45eb598a251fd0bcfe54cb13ab5d9`.
Existing internal testers can look for **KORLIX AI 12.0.7 (148)** in TestFlight.

The initial November 26 check for older build 146 was canceled before running
after the newer internal build was found. A fresh **GET-only** check for build
148 is queued; no new app binary or Apple record changes are involved.
[Current verification run](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6b08767e83fe00259b6c29e6)
uses source `b5162de51047941a5f9770e771036ad9f1f2f2d2`.
It resolves the existing named Apple integration and reports only build status
and internal-group counts, without reading tester membership.

## Official migration sources

- https://developers.openai.com/api/docs/guides/latest-model
- https://developers.openai.com/api/docs/guides/image-generation
- https://developers.openai.com/api/docs/models/gpt-6.2-astra
- https://developers.openai.com/api/docs/models/gpt-image-2.6-sunburst
