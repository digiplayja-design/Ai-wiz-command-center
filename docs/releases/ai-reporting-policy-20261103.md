# Korlix AI — AI-generated content reporting correction

The owner's November 3, 2026 Play Console screenshots identify the main app,
Korlix AI (`com.korlixdeveloper.korlixai`), and an AI-Generated Content policy
warning: users lack an in-app way to report or flag offensive content. The
warning gives November 6, 2026 as the deadline. This is separate from the
Brain+Voice release.

Google's current requirement is an in-app reporting or flagging mechanism that
does not require the user to leave the app:
https://support.google.com/googleplay/android-developer/answer/13985936?hl=en

## Correction

The signed-in app navigator now has a visible **Report AI content** footer.
It stays available on pushed routes, including live voice, podcast playback,
virtual closet, Baby Blend, and live studio. Existing selected-result controls
remain available for text/history, generated images, logos, edited photos,
portrait previews, music, and image-to-video results.

The footer opens a form inside the app. The user selects a reason and describes
or quotes the content, including the feature used. A description is required
because this general entry point does not silently capture screen content,
audio, or conversation history. Reports use the existing authenticated private
support endpoint. Account changes invalidate an open report; a late response
cannot report success under a new account. Submission is not retried
automatically, and a success confirmation requires the existing durable receipt
format. The footer reserves layout space and hides during keyboard input.

The owner's follow-up evidence identifies **BabyBlend** and **Image-to-Video**.
BabyBlend now has **Report portrait** beside the current result and on each
saved portrait. It fetches the selected generated image through the authenticated
API and attaches a bounded review copy plus that portrait's age/style options.
Adult reference photos and their identifiers are excluded. Image-to-Video's
existing **Report video** control is moved above the video preview to make it
prominent before the download, copy, and share controls.

## Reviewer path

1. Sign in using the existing review account.
2. Open **BabyBlend**, create a portrait or open a saved portrait, and tap
   **Report portrait**. The same action is available on each **My portraits** card.
3. Choose a reason, optionally describe the problem, and tap **Submit report**.
   Acceptance is shown only after the server returns a durable report reference.
4. Open **Image-to-Video**, generate a video, and tap **Report video** directly
   above the preview. Submit a reason; the selected clip and its original prompt
   accompany the report without leaving the app.
5. Other signed-in routes also have **Report AI content** at the bottom of the
   screen. This general form requires a description identifying the feature and
   content. Cancellation does not send a report.

For generated images, logos, picture edits, portrait previews, music, or videos,
the selected-result reporting button can additionally include that particular
result's context. Cancellation does not send a report.

## Validation and release boundary

Source is based on the last recorded CRM app branch at
`37d629b7e24d4765e29c3276ac6a3ac1b027d578`, preserving the CRM and prior reporting
changes. Pull request: https://github.com/digiplayja-design/Ai-wiz-command-center/pull/41

Workflow: https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41646037336

Validation completed successfully on November 3, 2026 against code commit
`240d45a96d00b990aa6d37bb8e45d1c56a83a685`. Static analysis reported no issues,
all **96 tests passed**, and Android debug compilation succeeded. These results
include the direct BabyBlend controls and the prominent Image-to-Video control.

The dedicated workflow analyzes support and BabyBlend code, tests the new
cross-route flow and existing reporting surfaces, and compiles the Android app.
Tests cover the selected older BabyBlend portrait and its creation options,
exclusion of adult reference photo identifiers, cancellation, required context,
durable receipts, unconfirmed responses, account changes during image retrieval,
duplicate taps, and narrow-screen layout. Submission tests exercise real image
decoding and the authenticated reporting transport with mocked HTTP responses.

The live `/api/report-output/health` endpoint returned HTTP 200, `ok: true`, and
`reportDeliveryVersion: v5`. This is a health check, not proof that a real report
or email was delivered. No real support report was sent during this work.

The saved workflow artifact, `korlix-ai-reporting-android-validation`
(artifact ID `13235647044`), is a **debug validation APK**, not a signed Google
Play release. Its archive SHA-256 is
`b41ac63c9471d26ffdaf33892d08a1a83c2abc7ecb19c382cce8b24e7131e357`;
GitHub retention expires November 17, 2026. Do not upload it or the source's
iOS-derived build number to Play.
The next signed Android version code must be verified against current uploaded
bundles, and the existing main-app upload key must be reused.

## Signed Android candidate

`KORLIX-12.0.4-144-babyblend-video-reporting-CANDIDATE.aab` was built on
November 3, 2026 from code commit `240d45a96d00b990aa6d37bb8e45d1c56a83a685`
using Flutter 3.47.7, the original main-app upload key, and the existing public
client configuration in an isolated Codespace checkout.

- Package: `com.korlixdeveloper.korlixai`
- Version: `12.0.4` / candidate version code `144`
- Size: `164996865` bytes
- SHA-256: `660d9e6a49e5204b5558928d0ff15511b20c293541fe00cbba74069646effad2`
- Upload certificate SHA-256: `c1d051456057e6d813f0d4e82892b856c3e67852b05cd78d302adc5da8162f7f`
- Android minimum SDK `24`, target SDK `36`, matching the previous main-app bundle 140.

Google bundletool validation and JAR signature verification passed. The upload
certificate matches the existing main-app bundle 140. The release is not
debuggable. The compiled app contains the portrait, video, and general reporting
controls, plus the existing Supabase and backend client settings. The downloaded
file's SHA-256 matches the verified original exactly.

Flutter's normal build migration changed the isolated checkout's Android minimum
SDK declaration from `23` to `flutter.minSdkVersion` (`24`); the resulting minimum
matches the previous release. Existing source changes and signing files in the
original checkout were preserved. Only new download links were added under
`release_uploads`.

**Do not upload this version-144 candidate.** On November 3, authenticated Play
Console inspection confirmed that version code 144 was already uploaded on
October 30. It is the older 12.0.4 build available to internal testers; its
production release was rejected on November 3. The saved candidate has been
renamed `KORLIX-12.0.4-144-DO-NOT-UPLOAD-version-code-already-used.aab` to prevent
accidental use. The compiled source still has the separate iOS-derived pubspec
build number; Android bundles use an explicit build-number override.

## Authenticated Play Console follow-up

On November 3, the owner approved continuing submission. The existing browser
was on Google's public Play business page. Its visible **Go to Play Console**
link led to Google Accounts, and secure authentication succeeded for the KORLIX
developer account. The earlier navigation block is no longer preventing access.

The Console state before replacing the releases was inspected directly:

- Developer account: KORLIX, ID `4772708594176030332`.
- Main app ID: `4974117289022654668`.
- Production version 143 (12.0.2) is listed as available on Google Play.
- Version 144 (12.0.4) was uploaded October 30 and is available to internal
  testers. Its production release was rejected on November 3.
- Both the rejection and November 6 removal warning cite the missing in-app
  reporting feature under the AI-Generated Content policy.
- The production track currently covers all 178 selected countries/regions;
  managed publishing is off.

A new production release, ID `13`, was created with the name
`145 (12.0.5) AI content reporting`. Its saved English release notes describe
BabyBlend reporting on current/saved portraits, the prominent Image-to-Video
report action, and cross-route AI-content reporting.

The tested code commit was rebuilt successfully as **12.0.5 (145)** using the
same isolated toolchain, existing public client configuration, and original
upload key. No application source changes were made for this version-number
change. The release build completed in 382.7 seconds.

An internal-testing release, ID `49`, was also created because the
November 3 rejection cites version 144 on both production and internal testing.
The previous bundle is excluded from both new releases.

## Verified version 145 bundle

- Filename: `KORLIX-12.0.5-145-babyblend-video-reporting.aab`
- Package: `com.korlixdeveloper.korlixai`
- Version name/code: `12.0.5` / `145`
- Source commit: `240d45a96d00b990aa6d37bb8e45d1c56a83a685`
- Size: `164996867` bytes
- SHA-256: `16cf020092bc7ef1f27698dec8f702cc16ebef23bae366579ab2da25d01f6791`
- Upload certificate SHA-256: `c1d051456057e6d813f0d4e82892b856c3e67852b05cd78d302adc5da8162f7f`
- Minimum SDK `24`, target SDK `36`, non-debuggable.
- Verified on November 3, 2026 at `14:35:15 UTC`.

Bundletool validation and JAR signature verification passed. The compiled app
contains **Report portrait**, **Report video**, and **Report AI content**, plus
the existing public client settings. The downloaded copy matches the signed
original byte for byte by SHA-256. The 96-test passing CI result applies to the
unchanged app source in this bundle.

## Submission confirmed on November 3, 2026

Google Play accepted the signed version-145 bundle. The production release was
saved and **Send changes for review** was confirmed with the owner's existing
authorization. At `14:47 UTC`, Publishing overview lists
**145 (12.0.5) AI content reporting** under **Changes in review**, with
**Start full rollout**. Google's automatic quick checks are still running;
the Console says the changes will proceed to review when those checks succeed.
No further submit action is pending from the owner at this point.

- Production: release ID `13`, version code `145` only, **100% rollout** across
  all **178 selected countries/regions**. **Managed publishing is off**, so the
  approved release is configured to publish automatically.
- Internal testing: release ID `49` was saved and published. The track is active
  and now explicitly shows **145 (12.0.5) AI content reporting — Available to
  internal testers**. The older version 144 is no longer the latest release.
- Device coverage is unchanged from the previous release. The release review
  showed **Ready to release**, without upload errors or displayed warnings.
- The November 6 policy warning remains visible while Google evaluates the
  correction. Production approval, public availability of version 145, and
  removal of that warning have **not** yet been confirmed.

Verified Console pages:

- [Production submission](https://play.google.com/console/u/0/developers/4772708594176030332/app/4974117289022654668/publishing)
- [Internal testing release](https://play.google.com/console/u/0/developers/4772708594176030332/app/4974117289022654668/tracks/4701415604792469412?tab=releases)

The verified signed bundle was saved as
`KORLIX-12.0.5-145-babyblend-video-reporting.aab`. No real support report or
email was sent during validation.
