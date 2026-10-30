# Korlix Magic Camera — implementation and release gates

This change adds a shared Flutter Magic Camera module, a standalone Android/iOS/web app, and a hub entry. The server lives on the separate current backend branch; do not deploy the app branch's older backend directory.

## Implemented

- Orange/blue Korlix emblem; prompt-first native camera, no captured-original preview or before/after view.
- 30 embedded presets in six categories, custom text and device dictation, optional clothing collection, saved signature looks, Surprise Me, intensity and accent controls.
- Interactive orange/blue orbits, Stardust and Portal modes, pause and OS reduced motion, group countdown and haptics.
- Private durable jobs, final-only gallery, save/share, animated GIF reveal using only the final image, deletion, and a visible Report action on each result and gallery item.
- Account-bound lifetime allowance of two successful free standalone results. Hub Basic cannot generate. Pro: 10/month, max 2/day; Ultra/Enterprise: 40/month, max 5/day. Shared across hub and companion. No extra developer unlimited bypass.
- Standalone Starter: 15/month, proposed US $9.99; Plus: 40/month, proposed US $19.99. Real store prices take precedence. Verified App Store/Google Play purchases; restore and cancellation-management links. No activation from an unverified client receipt.
- Sunburst maximum quality, one render, no automatic provider retry or quality downgrade. Presets avoid an extra planning call. Explicit custom prompts go directly to the image editor too.

## Validation and operational details

`packages/korlix_magic_core` is the shared UI/client. `apps/magic_camera` owns companion authentication and store UI. The companion bundle/package ID is `com.korlixdeveloper.magiccamera`.

The backend PR adds `backend/magic_camera` and its service-only SQL migration. Worker leases are durable and fenced; source photos are stripped of metadata, privately stored, and removed after completion or expiration. Failed results do not consume credits. Generated files are stored before success is committed. Deleted successes remain in the allowance ledger. Reporting copies the actual generated result to the existing private Korlix support review queue.

Allowances use UTC calendar months/days, including standalone subscriptions. The purchase screen explains this. Source uploads expire after 3 minutes, queued jobs after 24 hours, processing leases after 10 minutes. The worker sweeps private files every 5 seconds while the service is running; storage outages delay deletion and are retried. The private gallery pages through older jobs and loads smaller previews only as cards become visible. Signature looks are stored per account on the current device.

Native camera 0.12.2 raises the hub's Android minimum from API 23 to API 24 (Android 7). Android 6 installations need their existing hub version or the web app. iOS camera use and optional dictation permissions are included. This change does not alter Improve My Picture tier rules.

## Before live release

1. Backend PR #32 is merged into `release/signup-plan-intent-20261021` and live on the existing Render service at runtime commit `b3715eaeb167779d3ca278554507ac323336f14b`. Migration `20261030031457_magic_camera_foundation` is applied. Health, namespaced account validation and unauthenticated route rejection were checked. The app branch must never replace that backend history.
2. Apple app `6828697639` is registered for `com.korlixdeveloper.magiccamera`. Create the dedicated Google app record and monthly `magic_camera_starter` / `magic_camera_plus` products at the approved prices. Apple's updated Paid Apps Agreement remains pending; billing is disabled. Set provider flags only after signed sandbox purchase/restore/cancel/refund checks. Existing hub store products are unchanged.
3. Review the provided Android and iOS build artifacts. Complete physical-device camera, background/reconnect, rotation, camera-denial, save/share, and group-portrait QA, plus representative real Sunburst quality/latency checks. No latency or perfect-face guarantee is claimed.
4. Confirm original-image retention against the service configuration and include this data flow in the published app privacy disclosures. Confirm the team monitors the existing report review queue.
5. Configure dedicated Android release signing. Complete internal iOS testing, store metadata and store review before public release; release the new hub build separately. Apple signing and the first TestFlight uploads are already prepared as recorded below.

## Build 2 continuation

- Native camera controllers close and temporary captures are removed before upload. Countdown cancels when backgrounded; overlapping resume/lens changes initialize one controller at a time.
- A lost upload response can be recovered by its original request key. `GET /api/magic-camera/requests/:key` is owner-bound and read-only: it cannot upload, render or spend a second credit. The ordinary private gallery remains the recovery path after closing or restarting the app.
- Finished-image download failure now shows a saved-result state with Refresh and Report. Refresh reloads the stored image; it never renders a replacement. Polling pauses in the background and resumes the existing job. Failed attempts can be removed from the gallery.
- Subscription screens include privacy/terms links and handle a failed subscription-management link explicitly.
- Android releases require all dedicated signing values and no longer fall back to a debug certificate. The manual `magic-camera-android-release.yml` workflow builds a verified AAB candidate using the `magic-camera-android-release` environment. Configure `KORLIX_MAGIC_ANDROID_KEYSTORE_BASE64`, `KORLIX_MAGIC_ANDROID_STORE_PASSWORD`, `KORLIX_MAGIC_ANDROID_KEY_ALIAS`, and `KORLIX_MAGIC_ANDROID_KEY_PASSWORD` there. A local build can use `android/key.properties` instead.
- Codemagic workflow `magic-camera-ios-candidate` uses `KORLIX_MAGIC_CAMERA_APP_STORE_PROFILE` with the existing distribution certificate. It requires the exact Magic Camera Apple app record, picks an unused build number and validates the IPA identity, permissions and signature. It produces a candidate without automatically uploading to TestFlight or publishing.
- The dedicated Apple profile `565WLJSXZP` is registered and imported into Codemagic as `KORLIX_MAGIC_CAMERA_APP_STORE_PROFILE`, using the existing Korlix distribution certificate. It expires June 22, 2027. No new signing key or certificate was created.
- Manual workflow `magic-camera-ios-testflight` inherits the candidate's tests and IPA verification, pins Apple app `6828697639`, and uploads through the existing Apple integration. It does not submit to external beta review, assign tester groups, or submit to the App Store.

Local validation: 11 shared camera tests, standalone authentication test, 12 Apple release verification tests and 74 backend/regression checks pass; shared and standalone analysis are clean. Backend checks include actual companion session registration, read-only recovery access, refresh/sign-out and independent hub sessions. Physical-device and live provider/purchase tests remain release gates. iOS signing is provisioned. Android release signing remains unconfigured.

Signed iOS candidate `1.0.0 (2)` completed in [Codemagic build 6ae4124eefa74786046ef4d4](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6ae4124eefa74786046ef4d4) at source `bdd3d600e73a62bfca35ed03a2d8fd7525d1d3a6`. The exact bundle, App Store profile, signed entitlements and deep signature verification passed. IPA SHA-256: `e9265774823597a63d8f84beff176b76607b6d3bc022b8841ae02bb9259e2d9a`. This candidate was not uploaded to Apple.

Build 3 replaces the default native launch image with the existing KORLIX emblem on the app's navy background. Its export metadata declares no non-exempt encryption: this client uses HTTPS transport and the platform keychain for session tokens, with no custom encryption feature. Reassess that declaration if cryptographic functionality or dependencies change. Apple's [encryption metadata guidance](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption) describes this flag.

Build `1.0.0 (3)` passed signed IPA verification and uploaded without errors in [Codemagic build 6ae4140fefa74786046ef532](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6ae4140fefa74786046ef532), at source `60f71a6f9a6a16d7155a505d7eea5a018aa6f91f`. IPA SHA-256: `91b2d2e43438309d9265cceaedf38650ea275d3420b6f013c23bf503fb3ab3b6`. No tester distribution or App Store submission was performed. The internal group `Magic Camera Internal` is created with automatic distribution disabled; beta description, feedback email and the existing privacy-policy URL are saved.

Build 4 adds photo-library usage descriptions for the bundled native media/export APIs. IPA verification now rejects missing or invalid photo-library purpose strings as well as camera, dictation and location purpose strings. The library is still accessed only through a user-selected system action; adding a purpose string does not grant permission or initiate a permission request.

Build `1.0.0 (4)` passed the shared-camera and standalone checks, signed IPA verification, and Apple upload in [Codemagic build 6ae41650efa74786046ef58a](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6ae41650efa74786046ef58a), at source `b7e2eb44dbcfd369c4821dc7f9f3ab871225d113`. Apple reported `UPLOAD SUCCEEDED with no errors` at 2026-10-30 04:06 UTC, delivery UUID `a862b9ae-e1cd-44d1-8b28-bac4f78c98e8`. The 32,859,277-byte IPA has SHA-256 `dd6bf05a7e443ed169e021aca1ee5399752719d23664a0e38ed02f36a44ad979`.

Apple processing completed and build `1.0.0 (4)` is **Ready to Test** in the [Magic Camera Internal group](https://appstoreconnect.apple.com/teams/f6169920-6326-4780-9d14-81013fac8eb0/apps/6828697639/testflight/groups/55161f65-8fac-43c4-b3d9-0d56c3efbf9c/builds). The group contains one build and no testers; no invitations were sent. Automatic distribution remains disabled. Physical-device QA and App Store review are not complete. The updated Apple Developer Program License Agreement was accepted with the account holder's approval; the separate updated Paid Apps Agreement remains pending.

Full Android/web/hub and iOS simulator validation passed at build-3 source `60f71a6f` in [GitHub Actions run 40999554685](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40999554685), and again at build-4 source `b7e2eb44` in [run 41000390359](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41000390359). This includes all 12 release-verification tests, 11 shared-camera tests, the standalone authentication test, hub catalog checks and rejection of an Android release without dedicated signing.

Download the build-4 [standalone Android/web review package](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41000390359/artifacts/12953796385), [hub Android review package](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41000390359/artifacts/12953343334), or [iOS simulator package](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41000390359/artifacts/12953113296). The Android APKs are debug test builds. The simulator package is separate from the signed physical-device TestFlight build above. These GitHub artifacts expire on 2027-01-28.

## Build 5: upright camera and natural portrait finish

App source `684fe94bbee2016685f14a7ed5a99666de3b7d2e` synchronizes native preview and capture orientation with the visible camera view. It reapplies orientation after opening, switching lenses and resuming, and waits for a pending native orientation change before the shutter. Portrait screens reject stale landscape sensor events; landscape capture remains supported. Web capture keeps its browser-managed orientation.

All 14 shared-camera tests, the standalone authentication test and 12 release-verification tests pass locally; shared and standalone analysis are clean. The new camera regressions cover both lenses, resume, both landscape directions, returning to portrait, and rotation during a countdown while the native update is pending.

Signed `1.0.0 (5)` passed IPA verification and Apple upload in [Codemagic build 6ae41f99efa74786046ef718](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6ae41f99efa74786046ef718). Apple reported `UPLOAD SUCCEEDED with no errors` at 2026-10-30 04:45 UTC, delivery UUID `03c05bf8-aff2-44f9-8b7b-d230159b966a`. The 32,862,510-byte IPA has SHA-256 `25fa548cdc833ae8a111a956ad5ba78ac05c67bea2b720e1867b559b341596e2`. Apple processing is **Complete**, and build 5 is assigned to the existing [Magic Camera Internal group](https://appstoreconnect.apple.com/teams/f6169920-6326-4780-9d14-81013fac8eb0/apps/6828697639/testflight/groups/55161f65-8fac-43c4-b3d9-0d56c3efbf9c/builds) with status **Testing**. The group has one approved tester and two builds; Apple lists build 5 as installed for that tester. The expired browser session was renewed through user-approved SMS verification. Automatic distribution remains disabled, and no public App Store submission was made.

[GitHub Actions run 41003976056](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41003976056) passed both jobs at the exact app source above: Android/web/hub builds and tests, rejection of an unsigned Android release, and the iOS simulator build. Review artifacts: [standalone Android APK and web bundle](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41003976056/artifacts/12955445616), [hub Android APK](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41003976056/artifacts/12954873294), and [iOS simulator package](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41003976056/artifacts/12954482449). Android APKs are debug test builds; artifacts expire on 2027-01-28.

The paired backend change is [PR #35](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/35), source `3487e19a21456ba5c905519c82647b02939be915`, targeting `release/signup-plan-intent-20261021`. It adds automatic conditional hair grooming, excess-shine reduction with natural skin texture, and cinematic lighting while preserving identity, hairline, hair texture and skin tone. Generated PNG orientation is baked into the pixels before metadata removal, and dimensions are recorded after rotation. All 92 backend checks pass, including 18 image/prompt checks for all eight EXIF transforms, mirrored photos, repeat normalization and the image-editor request.

Backend PR #35 is **not merged or deployed**. The Render connection has no selected workspace. The Render deployment skill requires the user to identify the workspace before resource access; the available workspace is `Digiplay's workspace` (`tea-d8cskuf7f7vs73emq1p0`). After confirmation, verify the existing backend service `srv-d8csvkkp3tds73emfikg`, its release branch and current deploy; merge only PR #35, deploy that resulting release commit and verify the live workload. Do not deploy the app branch's older backend. No database, model, entitlement or billing changes are needed.

Physical-device follow-up: take new portrait and landscape photos with both lenses, reopen after backgrounding, rotate during a countdown, then check final display/save/share orientation. After the backend update is live, test hair needing grooming versus already groomed hair and shiny versus balanced skin. The finish instructions are model guidance; device behavior and real-image quality still need this visual check. Existing saved photos are not regenerated.

## Build 6: sensor-aware front-camera orientation

The build-5 physical-device follow-up found a sideways front-camera live preview
on an iPhone 17 Pro Max, while the rear camera remained upright. The Dart view
orientation was already synchronized; the native camera plugin still translated
portrait into a fixed 90-degree rotation for every camera.

Build 6 vendors `camera_avfoundation` 0.11.1 with a focused front-camera patch.
AVFoundation's semantic orientation setter now resolves portrait/landscape for
both the front video and photo connections, including their different sensor
compensation. Rear-camera behavior and selfie mirroring retain upstream behavior.
All three Flutter package roots resolve the same patched plugin. See
`third_party/camera_avfoundation/KORLIX_PATCH.md` for provenance and removal criteria.

Seven native iOS regressions exercise the production helper for different front
sensor/output baselines, all orientations, repeated updates, lens switching,
mirroring and unsupported connections. The iOS validation job runs these tests
on a simulator in addition to building the app. All seven native tests passed
with zero failures in [GitHub Actions run 41008061582](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41008061582)
at source `ae144786f0cabcb6d232974e3afa2e61ba13c9ff`. Both iOS and Android jobs
passed, including Android/web/hub builds, 14 shared-camera tests, standalone
and hub tests, all 12 release-verification checks and rejection of an unsigned
Android release. Shared and standalone local analysis are clean.

Signed `1.0.0 (6)` passed IPA verification and Apple upload in
[Codemagic build 6ae429e2efa74786046ef904](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6ae429e2efa74786046ef904),
using that exact source. Apple reported `UPLOAD SUCCEEDED with no errors` at
2026-10-30 05:30:16 UTC, delivery UUID `d1e67275-9ff2-4f54-ae28-e8833075bf52`.
The 32,862,558-byte IPA has SHA-256
`4307dccdb3881affd483d170fd06bf078aa73a6a03fc676eaff6721788478057`.
Apple processing is **Complete**, and build 6 is assigned to the existing
[Magic Camera Internal group](https://appstoreconnect.apple.com/teams/f6169920-6326-4780-9d14-81013fac8eb0/apps/6828697639/testflight/groups/55161f65-8fac-43c4-b3d9-0d56c3efbf9c/builds)
with status **Testing**. The group contains the same one approved tester and
three builds (4, 5 and 6). Automatic distribution remains disabled. No new testers
were added and no public App Store submission was made.

Review artifacts: [iOS simulator](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41008061582/artifacts/12957025798),
[native XCTest results](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41008061582/artifacts/12956881498),
[standalone Android/web](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41008061582/artifacts/12956108361)
and [hub Android](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41008061582/artifacts/12956752666).
Android APKs are debug test builds. Artifacts expire on 2027-01-28.

Physical front-camera preview and final photo orientation still need confirmation
on the affected device. Backend PR #35 remains separate and undeployed as
described above.

## Deliberately not advertised as complete

The proposed 10-photo $6.99 top-up needs consumable purchase verification and refund accounting before it can be offered. Rici's voiced countdown, portable style links, Astra-assisted complex planning, and segmentation/compositing to preserve original face pixels are future extensions. The current Preserve my face option supplies explicit generation constraints; it cannot guarantee identical facial pixels or zero distortion. There is no custom identity recognition or gender inference.
