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

## iOS upload checkpoint — November 4, 2026

Apple App Store Connect now has the separate **KORLIX COPY Box** app
**[6830765098](https://appstoreconnect.apple.com/apps/6830765098)** for
`com.korlixdeveloper.copybox`, under Korlix LLC team `FJKJ9MUDZ4`.
A signed **1.0.0 (1)** IPA was built and uploaded successfully by
[Codemagic build 6aeb61e5004ce28f20edd5ba](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6aeb61e5004ce28f20edd5ba)
from `4dd07806ff471263b1fb82d593f300cfe9693a4d`. The build finished in 5m 16s.

Apple TestFlight shows build `ddd61c5d-982c-404c-9aaa-d280bd0495be` as
**Ready to Submit**. No testing group, tester invitation, or verified device
installation has been recorded. The public App Store version remains
**Prepare for Submission**; it has not been submitted for review or released.

All twelve Apple screenshots are uploaded and visible: four large iPhone,
four medium iPhone, and four iPad images. A fresh listing tab confirms the public
promotional text, description, keywords, support URL, copyright, version, and
manual release option are saved. App Review contact details and the complete
prepared notes were accepted and saved. After reload, Save was disabled, the
contact names persisted, and the notes contained 2,606 characters. Phone and
email were redacted by the observation layer, so exact-value readback was not
available; no actual phone value is stored here. Reviewer username/password
remain unsupplied, and the sign-in-required checkbox remains checked. The selected
build 1.0.0 (1) persisted after reloading the version tab, with Save disabled. App
Information confirmed the subtitle and primary Productivity category saved;
the secondary category is blank. The privacy policy URL is saved and visible.
After the user's explicit approval, the updated Paid Apps Agreement was accepted
through secure second-factor verification. Business Agreements shows **Active**
for **November 4, 2026–June 22, 2027**. COPY Box-specific price and territories
remain unresolved.

Seven privacy categories are published: Email
Address, Customer Support, Other User Content, User ID, Device ID, Product
Interaction, and Other Data Types. Each uses **App Functionality**, is **linked
to the user**, and is **not used for tracking**. The exact deployed-source review
supports the no-tracking conclusion. After the user explicitly approved the
publication attestation, the final Publish confirmation was accepted. App Store
Connect now explicitly displays **Published by Ricardo Bailey**; all seven
classifications remain unchanged.

The age questionnaire was inspected and cancelled without saving. Actual AI
content frequency remains unresolved: the general backend `/api/generate` path
has no COPY Box topic/output filter and requires live-account evaluation for
those answers. The content-rights form was inspected without submitting an answer.

Apple's processed Build Metadata independently reports **Binary State:
Validated** and confirms the exact app identity, version/build, iOS 15.0 minimum,
iPhone/iPad support, arm64 architecture, and the app-private keychain group
`FJKJ9MUDZ4.com.korlixdeveloper.copybox`. TestFlight's device acceptance
instructions are saved. This establishes processed-build metadata, not device
installation or runtime acceptance.

The [release status](release-status.json) records the exact app, profile, build,
source, and evidence limitations. The latest asset commit, `9eda2fb7`, adds
screenshots/documentation without changing the application code or signing from
the signed build. Android signing and its release AAB remain pending.

## Automated app validation and test downloads

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

## Additional medium iPhone screenshots — November 4, 2026

The live App Store Connect Media Manager for COPY Box app `6830765098` requires
the medium Dynamic Island iPhone group. After the existing large images were
uploaded, the medium well displayed “Using Existing Assets.” A dedicated medium
set is also prepared: four genuine Flutter widget captures at
1206 × 2622 were produced by
[focused run 41872257288](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41872257288)
from capture commit `339e41f055882a24e35cd43ea39b273c1ff960a4`. The fixture renders
a 402 × 874 logical viewport at 3× using the shipping widgets, fonts, and sample
content. The isolated capture commit adds only that profile and a focused
workflow; it leaves app behavior and native configuration unchanged.

The four new images are in `store-assets/app-store/iphone-medium/`, ordered as
workspace, templates, focus editor, and dark workspace. They were visually
checked, fully decoded, and packaged as RGB PNGs with identical RGB pixels to
the raw captures. All original sixteen PNG files retain their prior hashes.
The combined manifest now lists sixteen screenshots and twenty PNG assets, with
separate provenance for the medium set. The original large iPhone group remains
available as an optional group, and the 13-inch iPad set is unchanged. This
focused capture run does not replace the full validation evidence above or
establish physical-device acceptance or store submission.

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
additions. Store field lengths were checked. Reviewer credentials and actual
phone values are excluded from source; COPY Box price and availability choices
remain unresolved. The completed Apple approvals are recorded as status evidence.

The [visual package](store-assets/README.md) contains the monochrome KORLIX app
icons, Google Play feature graphic, and four screenshots each for Android phone
(1080 × 1920), medium Dynamic Island iPhone (1206 × 2622), optional large Dynamic
Island iPhone (1260 × 2736), and 13-inch iPad
(2064 × 2752). The [manifest](store-assets/manifest.json) records source commit,
dimensions, formats, and hashes. Screenshots show the shipping Flutter widgets
with sample writing and are packaged without resizing or compositing fake UI.

The listing text and visual files are prepared; asset preparation does not
establish store submission. The existing public support/privacy/deletion URLs resolve. COPY
Box-specific HTML additions are merged through
[pull request 43](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/43)
as `da283a8dfe7b51f68ad7b581b8555f017cac3c54`, whose tree matches the reviewed
source. That exact commit has not been deployed; Render still serves the
October 25 release. Render rejected the existing GitHub connection as a
deployment connection rather than a sign-in method, and the alternative secure
sign-in request was declined. Authentication attempts stopped without a
deployment. See the [November 4 continuation](continuation-20261104.md)
for the safe deployment target and remaining account steps.

## Account and signing state observed

On November 4, the user authorized Cloud Browser access for Apple and Codemagic.
The explicit bundle identifier and App Store Connect record were created, and
App Store distribution profile `YG5PJS847P`, named
`KORLIX_COPYBOX_APP_STORE_PROFILE`, was created with existing certificate
`4635LCY72R`. The profile expires June 22, 2027 and was imported into Codemagic
under the exact reference required by the workflow. The existing certificate
reference remains `KORLIX_APP_STORE_CERT`; no replacement distribution certificate
or private key was created.

The `korlix-copybox-ios-testflight` workflow completed its signed build and Apple
upload. Codemagic displayed the IPA as 23.03 MB. Its browser download was not
available for an independent local artifact inspection, so exact byte size,
SHA-256, and embedded profile decoding are not claimed as locally verified.
Apple's processed Build Metadata separately confirms the signed application,
team and app-private keychain entitlements; debugging is disabled and
`beta-reports-active` is true.

The dedicated Android key `KORLIX_COPYBOX_ANDROID_UPLOAD_KEY` remains
unconfigured. Google Play sign-in succeeded and the KORLIX organization account,
developer ID `4772708594176030332`, was positively identified. Its homepage
listed five apps, none COPY Box; the exact package search returned **No results
found**. The Create app form was staged with **KORLIX COPY Box**,
`com.korlixdeveloper.copybox`, **English (United States)**, and **App**. Check
availability explicitly returned **Package name available**. Free/paid remains
unset, the Developer Program Policies and US export declarations are unchecked,
and **Create app was not submitted**. No COPY Box Play record, upload certificate,
or store release version code has been established. The earlier available key
belonged to KORLIX Brain and was not substituted for COPY Box.

## Remaining release gates

1. Supply and verify a dedicated working KORLIX reviewer login in the private
   App Review fields, with sufficient AI allowance and installation capacity.
   Contact details and prepared notes are saved, but reviewer username/password
   remain unsupplied; the review section is not complete.
2. Obtain COPY Box-specific price and country availability choices. The version
   is saved for manual release. The November 2 free/$0 and worldwide/all-175
   approvals concerned **Brain + Voice**; their exact antecedent was checked and
   they do not authorize COPY Box settings.
3. Evaluate actual AI content frequency through a live account, complete the
   age/content questionnaire, and supply the content-rights declaration. Configure
   TestFlight testing and complete physical iPhone/iPad acceptance: clipboard and
   paste prompts, file picker/share sheets, local persistence, offline launch,
   large text, account switching, live sign-in/password reset, optional AI
   consent/refinement/report, and account-deletion confirmation.
4. Complete the staged Google Play creation form after the COPY Box free/paid
   choice and required declarations are settled. Configure
   `KORLIX_COPYBOX_ANDROID_UPLOAD_KEY` and run
   `korlix-copybox-android-candidate`. Verify the signed AAB,
   bundletool page-alignment configuration, and generated APKs; complete device
   acceptance including a 16 KB-page Android environment. Debug APK evidence does
   not establish release-bundle packaging or runtime behavior.
5. Authenticate Render and deploy only the reviewed merge commit
   `da283a8dfe7b51f68ad7b581b8555f017cac3c54`, then verify all four COPY Box
   public policy/support pages. A generic configured-branch deployment is not
   the reviewed publication target.
6. Submit the completed store listings after the remaining release gates are
   satisfied. Neither public review nor public mobile availability is complete.

The candidate and upload workflows remain in `codemagic.yaml`. The iOS upload
workflow does not automatically submit beta/App Store review or assign tester
groups. The Android candidate has no Play publishing step. See
[Android release preparation](android-release.md) and the
[November 4 continuation](continuation-20261104.md).

## AI data handling and review evidence

Optional refinement sends the chosen box's full text and instruction to KORLIX
and OpenAI after explicit consent. The existing backend retains the request and
response in account generation history even when the user keeps the original.
Deleting a local box does not delete that online history. COPY Box disables
account memory for refinements; that does not bypass generation-history storage.

The original backend inventory at `92cad91d290d4ac93d273960c1144798f3afd14f`
was checked again against the primary API's exact deployed source,
`bf830fd98fd2e1846fed8b00e5ad73b69cbad6cb`, on November 4. Account/device
identifiers, declarations, AI content/history, and report/support data need
accurate disclosures. This is deployed-source verification, not a live
account-processing or deletion-fulfilment test. See
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
