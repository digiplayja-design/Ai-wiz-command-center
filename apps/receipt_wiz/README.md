# KORLIX Receipt Wiz

Independent Flutter app for the shared KORLIX receipt scanner and private receipt library. Candidate **1.2.0 (3)**, identifier **com.korlixdeveloper.receiptwiz**. Android upgrades the existing Play app; iOS is a separate first submission. Build and submission status must be verified in the stores.

## Receipt imports in 1.2

- **Upload receipt files** opens the system file picker for JPG, JPEG, PNG, WebP or PDF (8 MB per file).
- **Import multiple files** previews up to 10 receipts, at most 40 MB total. Nothing uploads until Upload files is tapped.
- Optional AI reading uses existing consent and server-owned allowances. Originals remain saved when reading fails or the allowance runs out.
- Sequential imports show per-file results, reuse exact duplicates, and keep stable retry keys. Stop finishes the current request; unsaved files can be retried while the queue stays open.
- Account changes clear the queue and block subsequent requests. The queue is in memory, not an offline background uploader.
- Camera data uses bounded stream reads. Deletion, unsaved-edit navigation, retry selection, pagination and filtered exports have regression coverage.
- The existing KORLIX logo is red across native launcher assets, the app and store icon. The raster color edit used image_gen; flutter_launcher_icons generated platform sizes.

## Shared account

- Sign in with the same KORLIX AI email/password. The hub need not be installed.
  Each installed app keeps its own secure native session.
- Receipt ownership, library and usage quotas use the existing backend account.
  Installing Receipt Wiz creates no extra trial or paid entitlement.
- Registration prominently directs existing customers to sign in. Duplicate
  registration offers **Sign In** and **Forgot Password?**. Sign In retains the
  email and clears the attempted new password.
- New registration retains age, guardian-permission and policy checks and
  selects free Basic, with the Free receipt allowance.
- Confirmation uses the existing web destination. Users verify their email,
  then return here to sign in. No dependency on the hub's custom URL scheme.
  Password recovery uses the existing hosted recovery page.
- Signout clears local credentials and requests revocation of this installation.
  Account deletion explicitly requests deletion of the **shared KORLIX account**.

## Independent app sessions

The companion backend change on **feature/receipt-wiz-shared-sessions-20261024**
was deployed on **24 October 2026**. It gives Receipt Wiz its own per-plan
installation allowance: Basic/Pro one and
Ultra/Enterprise two, with existing server-owned account overrides respected.
KORLIX AI and Receipt Wiz can remain signed in together. Logging out of either
app does not log out the other. Shared receipts, quotas and paid entitlements
remain attached to the same account.

The server binds each Receipt Wiz login to the verified provider session ID and
restricts it to receipt and account-management routes. Changing or removing the
app header cannot turn it into a hub login. Revoked bindings are retained, and
refresh never grants a new slot or reactivates a revoked login. The companion
migration is applied and the live backend passed its health and access checks.
Existing unbound standalone sessions must sign in again before testing.

## Backend

Companion branch **feature/receipt-wiz-shared-sessions-20261024** includes HTTP 409 with
`KORLIX_ACCOUNT_EXISTS` for `client_app: receipt_wiz`, including the provider's
masked duplicate-signup result. Main-app signup retains its existing contract.
A hashed mailbox budget limits signup to five attempts per 15 minutes per backend
process with bounded memory; provider/ingress throttles remain needed across
processes. No public email-lookup endpoint is added.

The backend runtime was deployed at commit
`f35201cc93233b614d28598d0a7bef00657bbcba`. Its source branch also records the
applied migration version and release checks. The app recognizes ordinary
duplicate errors from older backends, but cannot detect their masked provider
result reliably. This frontend branch does not deploy the backend automatically.

## Interface

White registration/sign-in screens with a static circuit grid and KORLIX branding;
camera and photo/PDF intake; stored originals; editable scan results; manual entry;
search and category/year/review filters; CSV export; explicit AI consent; account
settings; larger text, higher contrast and reduced motion. Terms, Privacy and the
runtime version/build appear together in Legal & Privacy.

Larger device text settings remain effective. Screen-reader labels, autofill and
minimum touch targets are present. Real VoiceOver/TalkBack and camera testing are
still needed before distribution.

## Validate and build

Use **Flutter 3.47.7 / Dart 3.13.5**, from the repository root:

```bash
cd packages/korlix_receipt_core
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
cd ../../apps/receipt_wiz
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

On macOS, `flutter build ios --simulator --debug --no-pub` builds for the simulator.
The separate **Receipt Wiz — test builds** Codemagic workflow builds both platforms
and publishes to neither store. **Receipt Wiz mobile validation** in GitHub Actions
also builds an Android debug APK and an unsigned iOS simulator app using Flutter
3.47.7. Simulator output cannot be installed on an iPhone or sent to TestFlight.

Android release signing uses this app's `android/key.properties` or Codemagic's
`CM_KEYSTORE_PATH`, `CM_KEYSTORE_PASSWORD`, `CM_KEY_ALIAS`, `CM_KEY_PASSWORD`.
Missing signing fails release builds; there is no debug-signing fallback. After
configuration, use `flutter build appbundle --release --no-pub`.

iOS needs its own App Store Connect app, bundle identifier and provisioning
profile before `flutter build ipa`. Do not reuse the hub's identifier/profile.
Build numbers start at 1 independently of the hub release.

The default is the existing HTTPS KORLIX API. For an isolated test backend, pass
`--dart-define=KORLIX_BACKEND_URL=https://your-test-api`. Never embed service keys.

Before release, check new/verified/duplicate accounts, recovery, device limits,
both-app receipt visibility, real camera and denied permissions, PDF upload,
export/share, restart/session recovery, signout, and accessibility. Complete the
new app's store privacy disclosures; its dependencies omit the hub's advertising,
billing, microphone and social SDKs.

## Verification — 24 October 2026

- [GitHub Actions validation](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40113384151)
  completed successfully at source commit
  `7b21888ceea16a7c27967a86e758eaee8f35e268`. It reran both analyses, all 81
  shared tests and all 16 app tests, and produced both mobile build artifacts.
  One optional shared screenshot-export test was skipped.
- [Android debug APK](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40113384151/artifacts/12568020933)
  and [iOS simulator app](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40113384151/artifacts/12566888930)
  are available as CI artifacts until 7 November 2026.
- Standalone analysis and all 16 app tests pass, including duplicate-email
  handoff, recovery, session changes, narrow layouts, enlarged text, labels,
  touch targets and contrast.
- Shared-package analysis and 81 scanner/auth/consent tests pass. The hub's 93
  receipt/auth integration tests also pass. Optional shared/hub screenshot-export
  cases are not part of those counts.
- The companion backend passes 246 session, signup and feature regression tests.
  Its additive session migration and backend runtime are live; RLS and
  service-role-only table/function permissions were verified.
- Web release compilation and Android debug APK compilation pass. The APK has
  identifier `com.korlixdeveloper.receiptwiz`, version `1.0.0`, build `1`, minimum
  Android API 24 and target API 36. The packaged archive and native-library
  boundaries were checked; the latest reduced-motion code is included.
- The first iOS simulator build passed on Xcode 26.6 and Flutter 3.47.7. The
  artifact digest and packaged identifier `com.korlixdeveloper.receiptwiz`,
  version `1.0.0 (1)`, minimum iOS 15, camera/photo permission descriptions and
  simulator platform were verified. This is not an iPhone-installable IPA.
- At this first validation checkpoint, no real-device installation or store
  upload had been performed. The subsequent Android internal release is recorded below.

## Google Play preparation — 24 October 2026

The existing Android Codespace produced **KORLIX-Receipt-Wiz-1.aab**, version
**1.0.0 (1)**, from source `38285c6215b828947b5728d84d525a40d03af5de`.
The release build completed successfully with Flutter 3.47.7, using the existing
upload key without changing its configuration or the original working tree.
An isolated temporary build folder avoids the Codespace's nearly full project disk.
The reusable build helper is [prepare-receipt-wiz-play.sh](../../tool/prepare-receipt-wiz-play.sh).

- Bundle size: **55,132,507 bytes**; SHA-256:
  `c098a7ea0ffe93054e3dfb35df07089663310ed3882bd1ae9563a0776183c13d`.
- Bundletool 1.18.3 validation passed. The packaged ID, version, build number,
  minimum API 24, target API 36 and release mode were verified.
- All **404 application entries** passed signature verification against the
  existing upload-key certificate. The archive contains no keystore, private
  signing properties or environment file.
- All eight 64-bit native libraries passed 16 KB ELF alignment checks, and the
  bundle requests `PAGE_ALIGNMENT_16K` native-library packaging.
- The merged manifest requests Internet, camera and its own signature-level
  dynamic-receiver permission. It contains no advertising identifier permission.
- [Store copy](store/google-play/listing.json), the existing brand icon, a
  1024×500 feature graphic and four 1080×1920 screenshots are prepared in
  [store/google-play](store/google-play). Screenshots were exported from the
  actual app with local sample data; the export test passed and the images were
  visually reviewed. PNGs have no alpha channel.
- [App-content disclosures](store/google-play/app-content-draft.json) are a draft,
  not a submitted certification. Provider/logging details, review access and
  applicable Play questionnaires remain to be completed.
- [Validation of the store-preparation commit](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40117102254)
  also passed: both analyses, the existing shared/app tests, Android debug build
  and iOS simulator build. Screenshot export is run separately with its explicit
  sample-data environment setting.

The owner approved Google's Developer Program Policy and US export-law
declarations, and the separate free **KORLIX Receipt Wiz** app record was created
on 24 October 2026 (Play app ID `4974803615919424879`). Google accepted the
verified signed bundle above. Release **1.0.0 (1)** is now **active and available
to internal testers**, using the existing nine-user internal tester list. The
release review showed **Ready to release**, with no remaining warnings, before
publication. This release is unreviewed and is not a public production launch;
Google currently displays its temporary package-based name.

- Store listing copy, icon, feature graphic and four real-app screenshots are
  saved and **ready to send for review**. The owner explicitly approved the AI
  declaration, which labels only the assistant-authored feature graphic. The
  short description has no final punctuation. Screenshot order in Play is scan,
  receipts, shared account, receipt review.
- Privacy policy, no-ads, non-government, no-health-features, financial scope,
  and Productivity category/public support contact are saved. Financial scope is
  declared as **Other**, with an explicit receipt/expense recordkeeping description.
- The complete ten-data-type questionnaire is saved as a draft. Its current
  no-sharing answer relies on Google's provider/consent exceptions and must be
  checked against actual provider settings before certification. Infrastructure
  diagnostic/IP/query retention still requires confirmation.
- Following the owner's explicit approval, IARC Terms of Use were accepted and
  the content-rating questionnaire was saved as **Completed**. Ratings include
  **ESRB Everyone** and **PEGI 3**, with no content descriptors. These content
  ratings do not change the intended 16+ audience or the shared-account age policy.
- Google Play now shows **8 of 11 initial setup tasks complete**. Public review
  still requires dedicated reviewer sign-in details, the dependent target-audience
  questionnaire and final Data safety certification. The open reviewer form's
  password field was checked for presence only and was still empty; no credentials
  were read, entered or stored. A working authorized review account must be
  supplied directly in Play Console.
- The internal-test invitation page was checked. It requires an invited Google
  account; the current Console account was not recognized as an invited tester.
  No new tester addresses were added and no invitations were sent.

See [Play release status](store/google-play/play-release-status.json) for the
exact Console and test-track links. Physical-device validation remains pending.

## Receipt Wiz Full candidate

Version 1.1.0 adds purple/coral, amber and green styling, monthly usage, and an
Android Upgrade/My plan screen. Free: 20 AI scans/month and 100 receipts within
250 MB. Full: 1,000 scans/month and 5,000 receipts within 2 GB for US$8.99/month
(localized price confirmed by Google Play). Pro, Ultra and Enterprise include
Full; existing developer overrides remain unlimited. All allowances belong to
the shared account and reset on the first calendar day at 00:00 UTC.

The independent `receipt_wiz_full` / `monthly` product is bound to
`com.korlixdeveloper.receiptwiz`. It never upgrades or downgrades the hub tier.
Only verified backend entitlement grants access. Failed scans return allowance;
manual entry, search and CSV remain free, and expiration/limits do not hide
saved receipts. Restore and Google Play management are available in My plan.

Deployment is pending explicit production approval after an automatic review
blocked the shared backend deploy. Do not publish the candidate internal release
or enable checkout before the database, backend, Play catalog and policies are
ready. See `docs/RECEIPT_WIZ_FULL_RELEASE_2026-10-24.md` for the release checklist.
