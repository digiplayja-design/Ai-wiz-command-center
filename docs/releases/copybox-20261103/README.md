# COPY Box release record

## Current release preparation

KORLIX COPY Box is a standalone Flutter app at `apps/korlix_copy_box`, with
Android package and iOS bundle `com.korlixdeveloper.copybox`, version 1.0.0 (1).
It uses the existing KORLIX account/API infrastructure for optional sign-in and
AI refinement. Local writing works without an account. The KORLIX AI hub and
other standalone app identities are unchanged.

The app has a black-and-white KORLIX emblem, colored writing cards, responsive
phone/tablet layouts, light/dark appearance, twelve starter boxes, folders,
favorites, search, focus editing, templates, autosave, replacement history,
recoverable trash, JSON backup/import, text export, and native sharing.

The source and release preparation are in
[pull request 42](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/42),
on `feature/korlix-copy-box-20261103`. The branch originated from frontend
policy/release commit `93253b767f6df1a8aec97bd29ce9cfbc09a34508`.

## Latest verified app source

Validation commit: **`d611bc6a1b5c8b6d7e3805725c6d7c5fe617f7e4`**.
[GitHub Actions run 41844773126](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41844773126)
completed successfully with Flutter 3.47.7, committed dependency lockfiles, and
Xcode 26.6 for the simulator build.

| Check | Result |
| --- | --- |
| Shared account/privacy analyzer | No issues |
| Shared account/privacy tests | 59 passed |
| COPY Box analyzer | No issues |
| COPY Box tests, including capture fixtures | 81 passed |
| Android debug APK | Built successfully |
| Compiled Android identity and permissions | Passed; separate ID, minimum SDK 24, target SDK 36 |
| Android native library alignment | All 10 libraries passed ELF and APK ZIP 16 KB alignment checks |
| iOS simulator application | Built successfully; separate bundle ID, minimum iOS 15.0 |
| Compiled iOS native dependency inspection | Six Mach-O binaries inspected; no flagged unused native references |
| Web release preview bundle | Built successfully |
| Store screenshot captures | Twelve actual Flutter interface captures at the three store sizes |

The **140 automated tests** cover shared credentials and consent, account
isolation, request races, data validation, write ordering, import limits, version
recovery, templates, autosave, Copy All, Add Box, trash/Undo, and compact/large-text
layouts. They use controlled network responses. Neither those tests nor the
widget screenshots establish physical-device or live-account acceptance.

The compiled APK requests Internet access and its own signature-protected
`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. It has no camera, microphone, broad
media/storage, or advertising-ID permissions. Debug simulator local-network
discovery is the only protected-purpose string in the inspected iOS artifact;
the release scanner does not apply that debug exception to a signed IPA.

Evidence and exact artifact provenance are retained in
[the final validation directory](validation-run10/):
[CI result and log excerpts](validation-run10/ci-summary.json),
[Android metadata](validation-run10/android-metadata.json),
[Android native inspection](validation-run10/android-native-dependencies.json),
[iOS native inspection](validation-run10/ios-native-dependencies.json),
[independent iOS artifact inspection](validation-run10/ios-verification.json),
and [download checksums](validation-run10/build-verification.json).

The earlier root-level `android-verification.json`, `ios-verification.json`,
`build-verification.json`, and `previews/` remain historical evidence for initial
run 41739349055 on `de58d87d0277759db87d20abc048358e6ab4f89c`. They do not describe
the refreshed downloads. Subsequent packaging/documentation changes leave the
app source, native configuration, and lockfiles from `d611bc6a` unchanged.

## Changes in the refreshed build

- Replaced the older file picker dependency with `file_picker` 13.3.2, removing
  the unused DKImagePicker/DKPhotoGallery/DKCamera dependency chain and the
  flagged location references from the compiled simulator app. Compatible
  `share_plus` 13.0.0 and `package_info_plus` 10.0.0 versions are locked.
- Preserved native file save/import while enforcing the 5 MiB import bound
  before and during stream reads. Five focused tests cover the new stream path.
- Added compiled native inspections to COPY Box's validation and candidate
  workflows so dependency and alignment regressions fail visibly.
- Aligned short notes to the top of Focus Editor and regenerated all twelve
  store captures from that exact source.

## Refreshed test downloads

- `KORLIX_COPY_Box_1.0.0_Android_test.apk`: installable **debug-signed Android
  test build**, 165,962,239 bytes. It is not the Google Play release AAB.
- `KORLIX_COPY_Box_1.0.0_iOS_Simulator.zip`: compiled `Runner.app` for the
  **iOS simulator on a Mac**, 57,854,081 bytes. It is not an iPhone installation
  package, signed IPA, or TestFlight build.

Both refreshed files come from `d611bc6a` / run 41844773126. Downloaded artifact
ZIP digests were matched against GitHub's recorded SHA-256 values and their CRCs
were checked before extraction. Inner deliverable hashes are in
`validation-run10/build-verification.json`.

Export a JSON backup before uninstalling an Android test build or changing its
signing identity. Saved boxes are local to the app and COPY Box does not encrypt
its box/backup files or automatically synchronize them to other devices.

## Store package

The [submission package](store-submission/README.md) contains the English store
name, subtitle, short/full descriptions, keywords, review/access notes, release
notes, TestFlight testing notes, privacy evidence, and drafted public-page
additions. Store field lengths were checked; reviewer credentials, personal
contact details, price choices, numeric Apple app IDs, and privacy attestations
have not been invented or placed in source.

The [visual package](store-assets/README.md) contains the monochrome KORLIX app
icons, Google Play feature graphic, and four screenshots each for Android phone
(1080 × 1920), large Dynamic Island iPhone (1260 × 2736), and 13-inch iPad
(2064 × 2752). The [manifest](store-assets/manifest.json) records source commit,
dimensions, formats, and hashes. Screenshots show the shipping Flutter widgets
with sample writing and are packaged without resizing or compositing fake UI.

The listing text and visual files are prepared; they have not been uploaded or
submitted. The existing public support/privacy/deletion URLs resolve, but the
COPY Box-specific additions in `public-page-additions.md` are still drafts.

## Account and signing state observed

Codemagic was accessible under the KORLIX account. Its stored distribution
certificate reference `KORLIX_APP_STORE_CERT` belongs to Korlix LLC and expires
June 22, 2027. No COPY Box provisioning profile was present among the stored or
fetched profiles. The available Android key was for KORLIX Brain; a dedicated
`KORLIX_COPYBOX_ANDROID_UPLOAD_KEY` was not present.

App Store Connect and Google Play Console required fresh sign-in. The Apple
secure sign-in request timed out; a user authentication handoff is required.
Consequently the existence/creation of COPY Box's own store records remains
unverified. No signing credential was created, exported, rotated, or reused from
another Android app. No store build was uploaded.

## Remaining release gates

1. Sign in to App Store Connect and Google Play Console, verify/create the
   independent app records, and confirm the publisher-controlled listing fields.
2. Provision `KORLIX_COPYBOX_APP_STORE_PROFILE` for the exact bundle ID with the
   existing authorized Apple certificate. Configure the dedicated COPY Box
   Android upload keystore under `KORLIX_COPYBOX_ANDROID_UPLOAD_KEY`.
3. Run the prepared signed candidate workflows. Verify the resulting AAB/IPA
   identity and signing. For Android, additionally inspect the AAB's bundletool
   page-alignment configuration and generated APKs; debug APK alignment is not
   evidence for a future release AAB's packaging.
4. Test on physical Android and iPhone/iPad: clipboard and paste prompts, file
   picker/share sheets, local persistence, offline launch, large text, account
   switching, live sign-in/password reset, optional AI consent/refinement/report,
   and account-deletion confirmation. Include a 16 KB-page Android environment.
5. Publish the reviewed COPY Box public-page additions, complete the store
   privacy/age-rating declarations, and provide a reviewer account with both AI
   allowance and available installation capacity under existing account limits.
6. Distribute the signed builds for internal testing/TestFlight, record device
   acceptance, and submit the completed listings for review.

The `korlix-copybox-android-candidate`, `korlix-copybox-ios-candidate`, and
`korlix-copybox-ios-testflight` workflows are prepared in `codemagic.yaml`.
Candidate signing fails closed when required identities are absent. See
[Android release preparation](android-release.md). Public store availability
remains pending.

## AI data handling and review evidence

Optional refinement sends the chosen box's full text and instruction to KORLIX
and OpenAI after explicit consent. The existing backend retains the request and
response in account generation history even when the user keeps the original.
Deleting a local box does not delete that online history. COPY Box disables
account memory for refinements; that does not bypass generation-history storage.

The backend source was inspected at
`92cad91d290d4ac93d273960c1144798f3afd14f`. Account/device identifiers, declarations,
AI content/history, and report/support data need accurate disclosures. This is
source verification, not a live authenticated processing test. See
[privacy evidence](store-submission/privacy-evidence.md) for data flows,
retention uncertainties, and the private-console handoff.

## Platform references

- [Apple review guidance](https://developer.apple.com/app-store/review/guidelines/)
- [Apple SDK requirements](https://developer.apple.com/news/upcoming-requirements/)
- [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Google target API policy](https://support.google.com/googleplay/android-developer/answer/11926878)
- [Google preview asset requirements](https://support.google.com/googleplay/android-developer/answer/9866151)
- [Android page-size requirements](https://developer.android.com/guide/practices/page-sizes)

These sources guide implementation and preparation; they do not establish store
approval.
