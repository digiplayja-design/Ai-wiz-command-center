# COPY Box release record — November 3, 2026

## Scope

A standalone Flutter app at `apps/korlix_copy_box`, using the existing KORLIX
account/API infrastructure. The initial version is 1.0.0 (1), with Android package
and iOS bundle `com.korlixdeveloper.copybox`.

The source was created on `feature/korlix-copy-box-20261103`, based on existing
frontend policy/release commit `93253b767f6df1a8aec97bd29ce9cfbc09a34508`.
The KORLIX AI hub and other standalone app identities were not changed.

## Verification

Validation commit: `de58d87d0277759db87d20abc048358e6ab4f89c`.
[GitHub Actions run 41739349055](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41739349055)
completed the checks below with Flutter 3.47.7 and the committed lockfiles.

| Check | Result |
| --- | --- |
| Shared account/privacy analyzer | No issues |
| Shared account/privacy tests | 59 passed |
| Copy Box analyzer | No issues |
| Copy Box tests | 73 passed |
| Android debug APK | Built successfully |
| Compiled Android identity and permissions | Passed; `com.korlixdeveloper.copybox`, minimum SDK 24, target SDK 36 |
| iOS simulator application | Built successfully with Xcode 26.6; bundle `com.korlixdeveloper.copybox`, minimum iOS 15.0 |
| Web release preview bundle | Built successfully |

The 132 automated tests cover shared credentials and consent, account isolation,
request races, data validation, write ordering, import limits, version recovery,
templates, autosave, Copy All, Add Box, recoverable trash, and compact/large-text
layouts. They use controlled network responses and do not establish live-account
or physical-device acceptance.

The compiled Android manifest contains Internet access and its own
signature-protected `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. It has no camera,
microphone, broad media/storage, or advertising-ID permissions. The dependency
lockfile uses the lean auth package and contains no `image_picker` dependency.

See [Android metadata](android-verification.json),
[iOS metadata](ios-verification.json), and
[download checksums and build provenance](build-verification.json).
The actual Flutter [interface previews](previews/README.md) were visually reviewed.

Local Flutter setup was stopped by automatic approval review after setup
attempted a cloud-instance metadata request. It was not retried or bypassed.
Validation ran in isolated GitHub Actions jobs with read-only
repository access, no persisted checkout credentials, and no signing secrets.

## Test downloads

- `KORLIX_COPY_Box_1.0.0_Android_test.apk`: an installable debug-signed Android
  test build. It is not the Play upload bundle. Export a JSON backup before
  uninstalling or changing signing identities; saved boxes are local to the app.
- `KORLIX_COPY_Box_1.0.0_iOS_Simulator.zip`: the compiled `Runner.app` for an iOS
  simulator on a Mac. It is not an iPhone installation package or a signed IPA.

Both downloads come from validation commit
`de58d87d0277759db87d20abc048358e6ab4f89c`; their hashes are recorded above.
The source and release preparation are in
[pull request 42](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/42).

## Release gates

- Test on physical Android and iPhone/iPad: clipboard/paste permission behavior,
  file picker/share sheets, local persistence, large text, offline launch, account
  switching, live sign-in, password reset, optional AI refinement, reporting, and
  account-deletion confirmation.
- Register the new app record in Google Play and App Store Connect under the
  separate package/bundle ID. No numeric Apple app ID is invented in source.
- Configure a dedicated Android upload key through `KORLIX_COPYBOX_ANDROID_*`
  variables, or a local ignored `android/key.properties`. Release builds fail
  closed if signing is missing; they never silently use debug signing.
- Provision `KORLIX_COPYBOX_APP_STORE_PROFILE` for the exact new bundle ID using
  the existing authorized Apple distribution certificate. Codemagic's candidate
  workflow verifies the Apple record and IPA identity before any upload.
- Confirm privacy disclosures against the shipping dependency tree, store age
  questionnaires, app support/deletion URLs, and actual native behavior. The
  optional AI endpoint uses existing account usage rules; no standalone purchase
  product or pricing has been introduced.
- Include optional AI content linked to the signed-in account in the store data
  disclosures: refinement sends the chosen box's full text and instruction to
  KORLIX and OpenAI, and the backend saves the request and response in account
  generation history. Keeping the original or deleting a local box does not
  remove that online history. Verify that first-use consent and Settings show
  this processing before testing with real text.
- Upload signed builds for internal testing/TestFlight, obtain device acceptance,
  and then submit the completed listings for review.

The signed-release workflows and store listing are prepared but have not been
executed or submitted. See [Android release preparation](android-release.md) and
the `korlix-copybox-ios-candidate` / `korlix-copybox-ios-testflight` workflows in
the root `codemagic.yaml`. Public store availability remains pending.

## Current platform requirements consulted

- Apple review guidance: https://developer.apple.com/app-store/review/guidelines/
- Apple SDK requirements: https://developer.apple.com/news/upcoming-requirements/
- Google target API policy: https://support.google.com/googleplay/android-developer/answer/11926878
- Android page-size requirements: https://developer.android.com/guide/practices/page-sizes

These sources inform implementation; they do not establish review approval.

## AI data handling evidence

The existing backend implementation was inspected on
`origin/release/k135z-backend-render-20260919`. In `backend/server.js`,
`POST /api/generate` calls `saveGenerationHistory` for authenticated requests.
That helper stores the account ID, full request prompt, generated response,
language, result type, search indicator, and credit usage. Copy Box disables
account memory for refinements; this flag does not bypass generation-history
storage. Local box deletion does not call an online history-deletion route.
This is source verification, not a live authenticated processing test.
