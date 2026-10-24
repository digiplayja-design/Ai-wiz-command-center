# KORLIX Receipt Wiz

Independent Flutter app for the existing KORLIX receipt scanner and private
receipt library. Version **1.0.0 (1)**. Proposed Android/iOS identifier:
**com.korlixdeveloper.receiptwiz**. Separate store records and signing setup are
still required before distribution.

## Shared account

- Sign in with the same KORLIX AI email/password. The hub need not be installed.
  Each installed app keeps its own secure native session.
- Receipt ownership, library and usage quotas use the existing backend account.
  Installing Receipt Wiz creates no extra trial or paid entitlement.
- Registration prominently directs existing customers to sign in. Duplicate
  registration offers **Sign In** and **Forgot Password?**. Sign In retains the
  email and clears the attempted new password.
- New registration retains age, guardian-permission and policy checks and
  selects free Basic, matching the existing free receipt scanner.
- Confirmation uses the existing web destination. Users verify their email,
  then return here to sign in. No dependency on the hub's custom URL scheme.
  Password recovery uses the existing hosted recovery page.
- Signout clears local credentials and requests revocation of this installation.
  Account deletion explicitly requests deletion of the **shared KORLIX account**.

## Independent app sessions

The companion backend change on **feature/receipt-wiz-shared-sessions-20261024**
gives Receipt Wiz its own per-plan installation allowance: Basic/Pro one and
Ultra/Enterprise two, with existing server-owned account overrides respected.
KORLIX AI and Receipt Wiz can remain signed in together. Logging out of either
app does not log out the other. Shared receipts, quotas and paid entitlements
remain attached to the same account.

The server binds each Receipt Wiz login to the verified provider session ID and
restricts it to receipt and account-management routes. Changing or removing the
app header cannot turn it into a hub login. Revoked bindings are retained, and
refresh never grants a new slot or reactivates a revoked login. This requires the
companion migration and backend deployment before live testing.

## Backend prerequisite

Companion branch **feature/receipt-wiz-shared-sessions-20261024** includes HTTP 409 with
`KORLIX_ACCOUNT_EXISTS` for `client_app: receipt_wiz`, including the provider's
masked duplicate-signup result. Main-app signup retains its existing contract.
A hashed mailbox budget limits signup to five attempts per 15 minutes per backend
process with bounded memory; provider/ingress throttles remain needed across
processes. No public email-lookup endpoint is added.

Deploy this change before live duplicate-registration testing. The app recognizes
ordinary duplicate errors from the old backend, but cannot detect its masked
provider result reliably. This branch does not deploy the backend automatically.

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

- Standalone analysis and all 16 app tests pass, including duplicate-email
  handoff, recovery, session changes, narrow layouts, enlarged text, labels,
  touch targets and contrast.
- Shared-package analysis and 81 scanner/auth/consent tests pass. The hub's 93
  receipt/auth integration tests also pass. Optional shared/hub screenshot-export
  cases are not part of those counts.
- The companion backend passes 27 signup tests.
- Web release compilation and Android debug APK compilation pass. The APK has
  identifier `com.korlixdeveloper.receiptwiz`, version `1.0.0`, build `1`, minimum
  Android API 24 and target API 36. The packaged archive and native-library
  boundaries were checked; the latest reduced-motion code is included.
- No real-device installation or iOS build was performed here. Store signing,
  listings, backend deployment and real-device checks remain
  release steps. No store upload or production backend change was made.
