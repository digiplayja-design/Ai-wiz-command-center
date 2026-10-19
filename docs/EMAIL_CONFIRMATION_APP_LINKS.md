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

## Release verification — October 19, 2026

The iOS candidate was built from
`cf1a36370acd6d50f0268e61d733248c0ecba33e` as **12.0.1 (132)**. Codemagic
build `6ad645697550aed8109033b0` passed all 96 selected checks, produced the
signed IPA, and uploaded it successfully to App Store Connect app
`6783100102`. Apple finished processing the build and its TestFlight beta
review submission was `WAITING_FOR_REVIEW` when checked. This is not an App
Store production submission.

The Android candidate is **12.0.1 (139)**, using source
`f3b8fce9fedc60c0eb65d1814c2a14cf37a1895b`. The user confirmed Play's highest
uploaded version code was 138; Play Console's release and bundle list also
showed 138 as the latest version. The build uses the existing signed Codespace
and an isolated worktree on its temporary build disk. The user's working branch
and uncommitted files are preserved.

The Android release gates passed 281 Flutter tests and eight configuration
tests. One existing smoke-preview test was skipped because
`KORLIX_SMOKE_PREVIEWS` was not enabled. The Codespace SDK is Flutter 3.44.0 /
Dart 3.12.0. Its SDK constraints resolve `matcher` 0.12.19, `meta` 1.18.0,
`test_api` 0.7.11, and `vector_math` 2.2.0 in the isolated build. Flutter also
migrates the Android minimum SDK setting to `flutter.minSdkVersion` (24),
matching the API 24+ minimum already shown for Play release 138. These generated
Android build adjustments do not replace the iOS workflow's locked SDK setup.

Android packaging completed after Flutter automatically retried a timed-out
Kotlin compiler download. The completed AAB passed archive integrity and JAR
signature verification. Its merged release manifest confirms the expected
package, version 12.0.1 (139), API 24 minimum, target API 36, and the confirmation
app-link handler with Flutter's default deep-link handling disabled.

- Saved Codespace artifact:
  `/workspaces/Ai-wiz-command-center/release_uploads/KORLIX-12.0.1-139-email-confirmation.aab`
- Size: 156,314,545 bytes.
- SHA-256: `c1d467253e731d7dfa5cee5204ca9d5efb8892f2ddac4c5d9972711690200e06`.
- Build log: `/tmp/korlix-confirmation-139.86kdDM.log`.
- Isolated build worktree: `/tmp/korlix-play-billing-139.oIMaoB/source`.

The user explicitly authorized transferring this bundle through a private,
GitHub-authenticated Codespaces URL and publishing it to Korlix AI's Google Play
internal testing track. The downloaded file's size and SHA-256 matched the
verified artifact. The single-file transfer server was stopped and Codespaces
confirmed that no ports remained forwarded.

Google Play accepted **139 (12.0.1)** and published internal release `43` on
October 19, 2026 at 1:56 PM America/New_York. The release details show
**Available to internal testers**, with 19,280 supported devices. The release
review reported no devices losing support. Play reports API 24+, target SDK 36,
three ABIs, a 61.7 MB new install, and a 6.77 MB update.

Release record:
https://play.google.com/console/u/0/developers/4772708594176030332/app/4974117289022654668/tracks/4701415604792469412/releases/43/details

## Android production submission — October 19, 2026

At 2:05 PM America/New_York, the user reported that the confirmation flow worked.
At 2:06 PM they requested the production push. The same tested **139 (12.0.1)**
bundle was promoted from internal testing into production release `8`, retaining
its release notes and targeting 100% of users in all existing targeted countries.
The production review reported no devices losing support.

The production change was saved and sent to Google Play for review. Publishing
overview shows **Changes in review**, with **Production — 139 (12.0.1) — Start
full rollout**. Google's quick checks were still running when verified. Managed
publishing is off, so successful approval is followed by automatic publication.
The production submission is complete; public availability is pending Google's
checks and review.

Publishing status:
https://play.google.com/console/u/0/developers/4772708594176030332/app/4974117289022654668/publishing

This action only promotes the Android build. The iOS build remains in its
separate TestFlight submission workflow.
