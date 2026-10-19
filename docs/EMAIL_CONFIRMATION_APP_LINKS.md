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
- Build Android and iOS from `release/k135z-frontend-20260919`, with a new build
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
