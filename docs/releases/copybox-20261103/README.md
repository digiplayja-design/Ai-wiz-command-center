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
for **November 4, 2026–June 22, 2027**. The user subsequently replied **Approve
setup**, explicitly authorizing free download on both stores and all supported
countries. Both stores' saved settings are now verified:

| Store | Download price | Saved availability | Release state |
| --- | --- | --- | --- |
| Apple | Free; $0.00 and zero local-currency prices | All 175 countries/regions **Available on App Release**; future countries included | Manual release; **Prepare for Submission** |
| Google Play | **Your app is Free**; Save changes disabled | **Targeted (178)**, including Rest of World | Production **Inactive**; no review or release submitted |

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
the signed build. The Android M2 retry finished successfully after both
analyzers and all 140 tests passed. Its downloaded AAB is 55,864,103 bytes;
independent signature, manifest, bundle configuration, and generated-APK checks
passed with documented jarsigner warnings. The verified bundle was accepted by
Google Play into the saved internal testing draft as 1.0.0 (1). It has no testers
or rollout. See the unchanged [artifact verification report](android-artifact-verification.json).

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
phone values are excluded from source. COPY Box's approved free pricing and
all-supported-country availability are saved in both stores. The completed
Apple approvals are recorded as status evidence.

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

The dedicated Android key `KORLIX_COPYBOX_ANDROID_UPLOAD_KEY` has been created,
its protected independent backup verified, and its Codemagic import confirmed
in the fresh keystore list. Its alias is `korlix_copybox_upload`, common name is
**KORLIX COPY Box Upload**, and the public SHA-256 fingerprint is
`4E:92:04:B6:04:11:F4:F5:72:30:51:6E:E3:CD:E8:8D:27:B9:8A:72:FF:3E:72:97:4A:44:94:31:10:B9:3F:A7`.
Codemagic displays the matching issuer and expiry **March 22, 2054**.

Android attempt `6aeb7e24c89c60076c761c73`, from reviewed source `4dd07806`,
failed before compilation: **The selected instance type is not available with
the current billing plan.** Commit `2c6544dba9afe2117181afabdc78a856ef4f249d`
changes only this workflow's worker from `linux_x2` to `mac_mini_m2`, the worker
already used successfully by the iOS build. No billing plan was modified.
[Android retry 6aeb7ea6004ce28f20ede0b2](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6aeb7ea6004ce28f20ede0b2)
started on Mac mini M2 at **18:56 UTC on November 4**, at that exact commit and
finished successfully in **7m 16s**. Both analyzers report no issues and all
**59 shared + 81 app tests** passed. Codemagic lists `KorlixCopyBox.aab` as
**53.28 MB**; the actual downloaded file is **55,864,103 bytes**. CI's native
scanner reported no validation errors, with APK ZIP layout explicitly
unchecked in CI. The separate downloaded-artifact check then passed bundletool
validation, verified the dedicated upload certificate and all **406 signed
payloads**, and confirmed version **1.0.0 / code 1**, minimum SDK **24**, target
SDK **36**, debugging/backup/cleartext disabled, and only INTERNET plus the
app's own signature-protected permission. Bundle configuration requests
**PAGE_ALIGNMENT_16K**; all **12 native libraries** passed ELF alignment checks.
The generated universal APK has valid v2/v3 signatures with the same upload
certificate and all 12 native libraries aligned in both ELF and APK ZIP layout.

The AAB SHA-256 is
`cc9e3b467fe3b4409db2ce93cc9ebc961cddd09333174bc9a82227c87f9bebaa`.
The [verification report](android-artifact-verification.json) documents Java's
self-signed-certificate, missing-timestamp, POSIX-attribute, and manifest-order
warnings, including the additional signed-digest coverage checks. It establishes
static artifact results; device installation, 16 KB-page runtime behavior, and
Play-delivered APK checks remain outstanding.

Google Play sign-in succeeded and the KORLIX organization account, developer ID
`4772708594176030332`, was positively identified. The separate
**[KORLIX COPY Box app 4974456296219116192](https://play.google.com/console/u/0/developers/4772708594176030332/app/4974456296219116192/app-dashboard)**
was created after selecting **Free** and accepting the approved Developer
Program Policies and US export declarations. A fresh dashboard confirmed the
title and app ID. The creation form used `com.korlixdeveloper.copybox`,
**English (United States)**, and **App**, after Check availability had explicitly
returned **Package name available**. Default automatic protection was displayed
enabled and left unchanged. A fresh pricing page confirms **Your app is Free**
with Save changes disabled. All production availability rows were selected and
saved; the fresh page shows **Targeted (178)**, including Rest of World, and
production **Inactive**. No review or rollout submission occurred. The verified
AAB was subsequently uploaded and accepted as version code **1**, version
**1.0.0**, in internal testing draft release **1**, track
**4699672053930799570**. The separate upload-certificate registration page was
not rechecked. The earlier available key belonged
to KORLIX Brain and was not substituted for COPY Box.

Google Play's App signing page independently shows its **App signing key: In
use**, with displayed install base **0.0%**. Its Digital Asset Links JSON names
`com.korlixdeveloper.copybox` and app-signing certificate SHA-256
`C5:B8:82:D1:29:C8:46:A9:D6:36:06:75:11:B3:5D:AB:52:1B:DD:3C:9D:D0:0C:57:82:BC:4E:C3:25:07:C8:0A`.
This is Google's managed app-signing certificate; the separately prepared upload
key has the `4E:92:…` fingerprint above. No signing setting was changed, and no
separate enrollment prompt appeared. Play's later accepted bundle upload is
recorded separately; explicit upload-certificate registration UI evidence was
not refreshed.

Google App content's observed Actioned snapshot showed **3 declarations**: **Ads**, **Financial
features**, and **Health apps**, all edited November 4. The saved answers are no
ads, no financial features, and no health features; financial documentation and
regional health requirements were not required. No review was sent. App access was inspected but
not saved: it requires a working restricted-feature reviewer account and an
affirmation of full access, including premium features. The empty details form
was cancelled and the selection discarded. The Advertising ID answer **No** was
subsequently saved, supported by the source and signed bundle's permission
inventory; no review was sent.

The Google [main store listing](https://play.google.com/console/u/0/developers/4772708594176030332/app/4974456296219116192/store-listings)
is saved and shows **Ready to send for review** on both the overview and reopened
edit page. The exact English title, 72-character short description, and
2,685-character full description match the prepared text. One icon, one feature
graphic, and four phone screenshots are saved in workspace, templates, focus
editor, and dark workspace order. Only the assistant-designed feature graphic
has the AI asset label; the icon and actual Flutter screenshots are unlabelled.
Productivity, support email/URL, and privacy URL are saved; public phone is blank.
This status describes the main listing, while other release gates remain open.

Internal draft **1.0.0 (1) - initial internal test** has the prepared English
release notes and processed app bundle **1 (1.0.0)** saved. Play reports API
**24+**, target **36**, four screen layouts, three ABIs, and one required feature;
ReTrace mapping and native debug symbols are attached. Preview showed one
warning: no testers are specified, so the release is unavailable to any users.
No error was displayed. **Save and publish was not clicked**; no testers,
invitations, or rollout were configured.
Final track readback confirms **Inactive**, **Draft**, and **1 of 3 complete**,
with version code **1**, **178 countries**, and **19,573 supported Android
devices** shown.

A bounded Google Data safety draft is saved at Step 2: the combined
collection/sharing question is **Yes**, account creation is **Username and
password**, and the deletion URL is
`https://www.korlixdeveloper.com/delete-account.html`. Encryption in transit and
optional data-only deletion remain unanswered; data-type, usage, and preview
steps were not reached. This is not a final or published declaration.

## Remaining release gates

1. Supply and verify a dedicated working KORLIX reviewer login in Apple's private
   App Review fields and Google Play App access, with sufficient AI allowance
   and installation capacity.
   Contact details and prepared notes are saved, but reviewer username/password
   remain unsupplied; the review section is not complete.
2. Evaluate actual AI content frequency through a live account, complete the
   age/content questionnaire, and supply the content-rights declaration. Configure
   TestFlight testing and complete physical iPhone/iPad acceptance: clipboard and
   paste prompts, file picker/share sheets, local persistence, offline launch,
   large text, account switching, live sign-in/password reset, optional AI
   consent/refinement/report, and account-deletion confirmation.
3. Configure deliberate Android testing and complete device/live-account
   acceptance, including a 16 KB-page environment and Play-delivered APK checks.
   Static checks of the signed AAB and generated universal APK passed; the saved
   Play internal draft has no testers and has not been rolled out.
4. Complete Google Play target audience, applicable content rating, and remaining
   app-content declarations. Complete Data safety beyond the saved Step 2 draft,
   including the unanswered operational questions and data-type, usage, and preview steps.
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
