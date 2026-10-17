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
flutter analyze lib/analytics lib/onboarding lib/auth/korlix_entry_welcome.dart lib/auth/korlix_entry_intro.dart lib/auth/korlix_entry_intro_controller.dart lib/billing/korlix_plan_prompt.dart test/korlix_onboarding_test.dart test/registration_discovery_test.dart test/korlix_entry_intro_test.dart
flutter test test/korlix_onboarding_test.dart test/registration_discovery_test.dart test/korlix_entry_intro_test.dart test/auth_welcome_test.dart test/auth_remember_login_test.dart test/auth_october_integration_test.dart test/signup_eligibility_test.dart test/auth_device_session_test.dart
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

The **Isolated onboarding validation** workflow checks this PR using pinned
Flutter 3.47.7. Before SDK setup it installs and verifies a metadata firewall.
After fetching the locked dependencies, it runs analysis and regression tests
as an unprivileged user in a verified loopback-only network namespace. No cloud
metadata endpoint is contacted to test the boundary. Logs and synthetic UI
screenshots are retained in the workflow artifact for seven days. Setup stops
if the firewall or isolation checks fail; dependency lock changes also fail.

Check the workflow result for the reviewed revision before release. This CI job
does not hold release-signing keys, compile a release AAB, or publish an app.
The signed build and on-device checks above remain separate release gates.


## Registration and plan discovery

- New visitors see a static example, **Create free account**, and a separate sign-in
  choice. Devices that have signed in before go straight to sign-in after logout;
  valid restored sessions still go straight to the app. The local welcome marker
  contains no email or token and does not grant access.
- Registration keeps email/password, password-manager autofill, required age and
  consent checks, email confirmation, and policy links. Optional login preferences
  start collapsed. Password reset remains available on sign-in. Changing between
  welcome, sign-in, signup and email confirmation starts the next screen at the top.
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
restore purchases, and Basic/paid account switching. Widget tests cover the
welcome/form navigation, age and confirmation requirements, autofill, device
session fields, account-scoped starter dismissal, Basic/paid/unknown presentation,
large text, and explicit plan navigation. They must pass on the reviewed revision.

## Optional business welcome voice

The new-visitor welcome includes the owner-approved October 17 introduction,
with friendly language for individuals and emphasis on business tools and
upgraded plans. **Hear the welcome**, **Stop welcome**, **Replay welcome** and
**Read intro** are available without submitting credentials. The transcript
identifies the audio as an AI voice introduction. The free signup and sign-in
paths remain directly available.

The 30.72-second recording is bundled as 24 kHz mono PCM at
`assets/onboarding/welcome-business-v1.wav` (1,474,604 bytes; SHA-256
`aac66676dd1157cfbd0d33b7faf77671ee8582f51bb7101a376f5c891eb6747f`).
It plays locally after an explicit tap and is not a live conversation: it does
not request microphone permission, start an AI job, transmit a visitor's data,
or spend a customer's AI GAS. The clip is generated once, not on each launch.
Existing post-sign-in Rici guidance and live NOVA sessions remain separate.

The recording includes an instrumental excerpt of **MindStream** by
**DST / Deceased Superior Technician**, published under **CC0 1.0**. It is mixed
about 14 dB below active speech, using speech-controlled volume and gentle fades.
The owner requested a 6 dB music increase relative to the original music mix.
The music and voice stop together through the existing playback controls.
The original spoken script and duration are unchanged. Source links, terms,
checksums, mix settings and reproduction instructions are recorded in
`assets/onboarding/README.md`; no new app dependency or network request is added.

Leaving the welcome, putting the app in the background, muting welcome audio,
or starting a competing audio session stops playback. Coming back does not
resume it automatically. A missing/blocked clip leaves signup and the written
introduction usable. The transcript follows the approved script and does not
offer a free trial of paid plans or promise a particular business outcome.

Before promotion, listen on an Android phone and confirm speaker volume,
music balance, pronunciation, interruptions, stop/replay and offline playback. The automated
checks exercise the bundled audio format/duration, explicit playback, readable
fallback, delayed-load cancellation, saved mute, backgrounding and navigation.
