# COPY Box release record — November 3, 2026

## Scope

A standalone Flutter app at `apps/korlix_copy_box`, using the existing KORLIX
account/API infrastructure. The initial version is 1.0.0 (1), with Android package
and iOS bundle `com.korlixdeveloper.copybox`.

The source was created on `feature/korlix-copy-box-20261103`, based on existing
frontend policy/release commit `93253b767f6df1a8aec97bd29ce9cfbc09a34508`.
The KORLIX AI hub and other standalone app identities were not changed.

## Verification

Dart source syntax formatting was performed while creating the UI. Native
manifest and build configuration inspection is recorded separately below when
complete. Full analyzer, tests, native builds, and screen captures must be
verified through the dedicated CI workflow before claiming a tested build.

Local Flutter setup was stopped by automatic approval review after setup
attempted a cloud-instance metadata request. It was not retried or bypassed.
Validation is being moved to an isolated GitHub Actions job with read-only
repository access, no persisted checkout credentials, and no signing secrets.

## Release gates

- Confirm successful Android test APK and iOS simulator CI builds and inspect the
  actual app screens.
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
- Upload signed builds for internal testing/TestFlight, obtain device acceptance,
  and then submit the completed listings for review.

## Current platform requirements consulted

- Apple review guidance: https://developer.apple.com/app-store/review/guidelines/
- Apple SDK requirements: https://developer.apple.com/news/upcoming-requirements/
- Google target API policy: https://support.google.com/googleplay/android-developer/answer/11926878
- Android page-size requirements: https://developer.android.com/guide/practices/page-sizes

These sources inform implementation; they do not establish review approval.
