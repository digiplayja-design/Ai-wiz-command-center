# Onboarding measurement app release

This branch retains the build-133 video-session/authentication fixes and adds
first-party measurements of app opens, registration, validation and confirmation.
It also adds the private **Korlix Account → New user journey** report. Only the
existing server-authorized developer account can read that report.

Deploy the matching onboarding backend and migration before promoting this app.
No Firebase SDK, new subscription service, ad-budget change, authentication
bypass, or change to the signup policy is involved.

## Validation and release

Run in the existing Flutter development environment:

```sh
flutter pub get
flutter analyze lib/analytics test/korlix_onboarding_test.dart
flutter test test/korlix_onboarding_test.dart test/auth_welcome_test.dart
```

The prepared build script also runs these checks before building an app bundle.
Use the existing signed Codespace and its public Supabase client configuration.
Keep `KORLIX_ANDROID_BUILD_PARENT=/tmp` on the low-disk Codespace. Call
`scripts/prepare-google-play-billing-build.sh` with the highest Play version code
verified across all tracks/drafts and the full reviewed commit SHA. Last observed
version code was 133; do not assume it is still the highest.

Before promotion, test an existing installation/update (not counted as a fresh
setup), a fresh installation, signup requiring email confirmation, sign-in, a
saved AI generation, and an offline launch followed by reconnection. The report
does not attribute those observations to Google Ads. New-setup counts describe
fresh local storage, which also includes reinstallations; they are not unique
new customers. Create-account taps include locally rejected form submissions.

Local verification on 2026-10-17: Dart parsing/formatting completed. Flutter setup
was blocked by automatic approval review because it attempted to contact cloud
instance metadata, so Flutter analysis/tests and AAB compilation have not run in
this environment. Complete the checks above before publishing the update.
