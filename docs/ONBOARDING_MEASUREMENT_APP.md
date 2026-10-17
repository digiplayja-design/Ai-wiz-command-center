# Onboarding measurement app release

This branch retains the build-133 video-session/authentication fixes and adds
first-party measurements of app opens, registration, validation and confirmation.
It implements the approved free-signup welcome, compact registration form,
editable starter tasks and direct subscription-plan discovery.
It also adds the private **Korlix Account → New user journey** report. Only the
existing server-authorized developer account can read that report.

Deploy the matching onboarding backend and migration before promoting this app.
No Firebase SDK, new subscription service, ad-budget change, authentication
bypass, or change to the signup policy is involved.

## Validation and release

Run in the existing Flutter development environment:

```sh
flutter pub get
flutter analyze lib/analytics lib/onboarding lib/auth/korlix_entry_welcome.dart lib/billing/korlix_plan_prompt.dart test/korlix_onboarding_test.dart test/registration_discovery_test.dart
flutter test test/korlix_onboarding_test.dart test/registration_discovery_test.dart test/auth_welcome_test.dart test/auth_remember_login_test.dart test/auth_october_integration_test.dart test/signup_eligibility_test.dart test/auth_device_session_test.dart
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


## Registration and plan discovery

- New visitors see a static example, **Create free account**, and a separate sign-in
  choice. Devices that have signed in before go straight to sign-in after logout;
  valid restored sessions still go straight to the app. The local welcome marker
  contains no email or token and does not grant access.
- Registration keeps email/password, password-manager autofill, required age and
  consent checks, email confirmation, and policy links. Optional login preferences
  start collapsed. Password reset remains available on sign-in.
- The first-use panel offers three editable text prompts. Choosing one only fills
  the composer; it never generates, spends credits, or skips the normal AI-consent
  and quota checks. Replacing an existing draft or attachments requires confirmation.
  Task selection or **Explore all tools** dismisses guidance for that account on
  this device. Other accounts get their own local dismissal state.
- A verified Basic account can open current plans or keep using Basic. Paid or
  unknown account tiers do not see the Basic promotion. Existing premium-feature
  prompts also open plans directly, unless the feature is marked coming soon.
- Plan discovery uses the existing platform-specific billing screen and its actual
  store prices/renewal terms. It does not initiate a purchase, alter subscriptions,
  or advertise an unconfigured trial.

This update reuses the existing registration event allowlist. Starter-card and
plan-link clicks are not new telemetry events. Use the private onboarding report
for registration outcomes and existing billing records for paid subscriptions;
it does not establish ad attribution or guarantee a conversion increase.

Before release, also check the welcome and forms on a small phone with a keyboard
and enlarged text; confirm that sign-in/logout and email confirmation work; try
all three starter tasks and cancel replacing a draft; inspect native plan prices,
restore purchases, and Basic/paid account switching. Widget regression tests were
added/updated but remain unexecuted until the Flutter validation blocker is resolved.
