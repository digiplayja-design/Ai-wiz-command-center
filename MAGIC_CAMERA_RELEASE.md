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
5. Register signing/provisioning and publish the standalone app through the stores; release the new hub build separately.

## Build 2 continuation

- Native camera controllers close and temporary captures are removed before upload. Countdown cancels when backgrounded; overlapping resume/lens changes initialize one controller at a time.
- A lost upload response can be recovered by its original request key. `GET /api/magic-camera/requests/:key` is owner-bound and read-only: it cannot upload, render or spend a second credit. The ordinary private gallery remains the recovery path after closing or restarting the app.
- Finished-image download failure now shows a saved-result state with Refresh and Report. Refresh reloads the stored image; it never renders a replacement. Polling pauses in the background and resumes the existing job. Failed attempts can be removed from the gallery.
- Subscription screens include privacy/terms links and handle a failed subscription-management link explicitly.
- Android releases require all dedicated signing values and no longer fall back to a debug certificate. The manual `magic-camera-android-release.yml` workflow builds a verified AAB candidate using the `magic-camera-android-release` environment. Configure `KORLIX_MAGIC_ANDROID_KEYSTORE_BASE64`, `KORLIX_MAGIC_ANDROID_STORE_PASSWORD`, `KORLIX_MAGIC_ANDROID_KEY_ALIAS`, and `KORLIX_MAGIC_ANDROID_KEY_PASSWORD` there. A local build can use `android/key.properties` instead.
- Codemagic workflow `magic-camera-ios-candidate` uses `KORLIX_MAGIC_CAMERA_APP_STORE_PROFILE` with the existing distribution certificate. It requires the exact Magic Camera Apple app record, picks an unused build number and validates the IPA identity, permissions and signature. It produces a candidate without automatically uploading to TestFlight or publishing.
- The dedicated Apple profile `565WLJSXZP` is registered and imported into Codemagic as `KORLIX_MAGIC_CAMERA_APP_STORE_PROFILE`, using the existing Korlix distribution certificate. It expires June 22, 2027. No new signing key or certificate was created.
- Manual workflow `magic-camera-ios-testflight` inherits the candidate's tests and IPA verification, pins Apple app `6828697639`, and uploads through the existing Apple integration. It does not submit to external beta review, assign tester groups, or submit to the App Store.

Local validation: 11 shared camera tests, standalone authentication test, 12 Apple release verification tests and 74 backend/regression checks pass; shared and standalone analysis are clean. Backend checks include actual companion session registration, read-only recovery access, refresh/sign-out and independent hub sessions. Physical-device and live provider/purchase tests remain release gates. iOS signing is provisioned; the first signed candidate is running in Codemagic. Android release signing remains unconfigured.

GitHub validation passed for standalone Android/web, hub Android and the iOS simulator at app commit `d17ef65e52c7c26785b28ce65171a02431d7b3d2`. Download the [standalone Android/web review package](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40994493237/artifacts/12951013874), [hub Android review package](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40994493237/artifacts/12951198031), or [iOS simulator package](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40994493237/artifacts/12949884490). The Android APKs are debug test builds; the iOS package is not a physical-device IPA or TestFlight build. Artifacts expire on 2027-01-28.

## Deliberately not advertised as complete

The proposed 10-photo $6.99 top-up needs consumable purchase verification and refund accounting before it can be offered. Rici's voiced countdown, portable style links, Astra-assisted complex planning, and segmentation/compositing to preserve original face pixels are future extensions. The current Preserve my face option supplies explicit generation constraints; it cannot guarantee identical facial pixels or zero distortion. There is no custom identity recognition or gender inference.
