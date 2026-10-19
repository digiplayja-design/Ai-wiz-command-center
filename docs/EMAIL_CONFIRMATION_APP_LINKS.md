# Email confirmation opens KORLIX

New Android and iOS builds request a confirmation callback under
`com.korlixdeveloper.korlixai://auth/confirm/<random-signup-state>`.
Supabase still verifies the email using the template's `{{ .ConfirmationURL }}`.
The app handles both cold and warm starts, validates the pending signup state,
exchanges the returned refresh token through the existing backend auth route,
checks the server-returned email, and saves the session using the secure store.
It then enters the normal signed-in home screen.

The callback does not replace an already signed-in account. Recovery links,
foreign URLs, mismatched signup states and rejected sessions cannot sign in.
No incoming URL or credential is logged or stored in shared preferences.
Only the pending email and a random signup state are stored in preferences.

## Configuration and rollout

- Supabase project: `uxtjzjbwtppjvnsoiijv` (Korlix AI).
- Add `com.korlixdeveloper.korlixai://auth/confirm/*` to Authentication > URL
  Configuration > Redirect URLs. Keep the existing Site URL and reset callback.
- The email button must keep `href="{{ .ConfirmationURL }}"`. A plain app link
  would skip email verification and is not a substitute.
- Deploy the matching backend change in
  `backend/korlix_signup_eligibility.mjs` on
  `release/k135z-backend-render-20260919` before distributing new mobile builds.
- Build the combined Android and iOS candidate from
  `release/mobile-confirmation-20261019`, with a new build
  number higher than the latest build already uploaded for each store.
- Install and test the new build before store rollout. Native manifest/plist
  changes require a new installed app; deploying the website cannot add them.

Older app builds and web signups retain their existing redirect because only
updated native clients send `confirmation_target: native` and the validated
state. Previously sent emails retain their original destination.

## Verification

Run the focused Flutter checks:

```bash
flutter test test/auth/korlix_email_confirmation_test.dart \
  test/auth_welcome_test.dart test/auth_device_session_test.dart
```

Backend checks on its release branch:

```bash
node --test backend/test/signup_eligibility.test.mjs \
  backend/test/auth_session_security.test.mjs
```

On an installed Android build and iOS build, register a new account using an
email address controlled by the tester, open the fresh confirmation email on
the same device, and tap Confirm Email Address. Check once with KORLIX running
in the background and once with it fully closed. Confirm arrival on the signed-in
home screen and that the session survives an app restart. The operating system
or email browser may ask permission to open KORLIX.

If confirming from another device or an old email, open KORLIX and sign in
normally after email verification. Expired or already-used links show a safe
sign-in message. No real confirmation emails are sent by the automated tests.

## Combined mobile candidate — October 19, 2026

This candidate preserves onboarding/session/voice/Social source
`62c3e086c17fbdaddcc1d4b6fcfc907c412da3eb` and integrates the email-confirmation
change originally committed as `1ecc4044eda9b9b7bb21ab4130c008d35d3d6926`.
The backend commit `d0db6673f692da95e7185b2fd1d7102cd078fb17` is deployed and
its health endpoint returned HTTP 200.

The iOS workflow retains the existing signing identity and TestFlight destination,
pins Flutter 3.47.7 and the previously successful Xcode 26.6 image, runs the
authentication/session/onboarding regressions, and queries App Store Connect
for the next unused build number. It stops if that query cannot be verified.
The patch version is 12.0.1; no App Store production submission is automatic.

Android signing remains in the existing signed Codespace. Codemagic has no
Android keystore configured. Use `scripts/prepare-google-play-billing-build.sh`
with this candidate's full commit and the highest version code verified across
all Play tracks and drafts. Do not build the old pinned revisions in previous
release handoff documents. Physical-device confirmation checks above remain
required before store promotion.
