# Korlix AI and Messenger iOS release preparation — October 28, 2026

The owner requested an updated Korlix AI App Store release after Apple approved the earlier submission, plus the latest KORLIX Messenger on the App Store. This authorizes preparing, uploading and submitting both apps. **Korlix AI 12.0.3 (134) was signed and uploaded successfully at 22:15 UTC. Apple processing completed and review submission `cae973b9-318e-4a12-af42-52dac837cd82` is **WAITING_FOR_REVIEW**, submitted at 22:18:24 UTC. Release is configured for after approval; the update is not yet confirmed publicly live. Messenger has not been uploaded or submitted.** Browser access recovered. The existing Codemagic session and Apple API integration work. App Store Connect web sign-in reached two-factor verification, which the owner declined; no subsequent authentication method was attempted.

## Source and versions

Release branch: `release/ios-appstore-20261028`, based on Messenger frontend commit `e45e12c3712b97dc8e99dea8e262c765e1a419bd`. This includes the current shared Social core and call recovery fixes. The older `release/k135z-frontend-20260919` branch is not the candidate. Its email-confirmation implementation matches the integrated candidate; the newer backend/Auto-Email branch is a separate server deployment and is not a mobile source replacement.

| App | Bundle ID | Candidate | Apple record |
| --- | --- | --- | --- |
| Korlix AI | `com.korlixdeveloper.korlixai` | `12.0.3`, build floor `134` | Existing ID `6783100102` |
| KORLIX Messenger | `com.korlixdeveloper.messenger` | `1.0.2`, build floor `5` | Must verify or create the separate Apple record |

The owner's approval email refers to an October 13 submission; prior release evidence identifies Korlix AI 12.0.0 (131). Repository records also confirm subsequent TestFlight uploads 12.0.1 (132) and 12.0.2 (133). The live Apple record was not inspected in this task, so these are prior checkpoints rather than a claim that 133 is still the highest build.

`prepare_ios_release.py` resolves exactly one Apple record matching the bundle ID, additionally checks Korlix AI's known Apple ID, and asks Apple for the highest build across App Store and TestFlight versions. A fresh build is selected above Apple's value and at or above the source floor. Authentication failures, unexpected IDs, noninteger build numbers, and a missing existing Korlix AI build stop the release. Only a successful empty lookup for a new Messenger record can use the source floor.

## Build and submission workflows

`codemagic.yaml` now has explicit `korlix-ai-ios-appstore` and `korlix-messenger-ios-appstore` workflows. They retain Flutter 3.47.7 and Xcode 26.6, run the appropriate regression checks, create signed IPAs, and request App Store review with release after approval. They do not cancel existing submissions. Neither has an automatic trigger; do not confuse a GitHub simulator validation run with a signed Codemagic release.

Korlix AI reuses the existing `Codemagic Korlix AI` integration and existing profile/certificate references. Messenger uses the same integration with signing-file lookup restricted to its own bundle ID and App Store distribution. Its Apple identifier, profile and signing capabilities must exist in Codemagic first. No credentials, profiles, certificates, bundle identifiers or APNs permissions were created or changed in this task. The existing Korlix AI app now has a new App Store version and review submission, with its English release notes updated.

Signing is restricted to the selected Runner project so the monorepo's other apps are not assigned the wrong profile. Exported packages are checked for the expected app, version, build number, iPhoneOS platform, App Store profile, distribution entitlements and valid code signature before entering the publishable artifact directory. Build metadata management during export is disabled so the verified build number is preserved.

Release notes are supplied separately for each app. Neither set of notes promises originating screen sharing from an iPhone. This release receives shared screens on iOS; it does not add a ReplayKit broadcast extension.

## Messenger notifications

Messenger Release/Profile configurations now select `RunnerPush.entitlements` and the production APNs environment; Debug keeps its existing base entitlements. The runtime reads the build setting through `KorlixAPNsEnvironment`. An exported Messenger IPA must contain matching production APNs configuration in its Info.plist, provisioning profile and actual signed entitlements, or upload preparation fails.

This source change is not proof that notification delivery works. Confirm that Apple's Messenger identifier has Push Notifications enabled, refresh its App Store provisioning profile in Codemagic, and verify the existing server APNs provider allows the Messenger bundle ID and preserves app/session isolation. No APNs key was created, copied or exposed. Check actual foreground/background notifications, taps/replies, account switching and logout on a physical iPhone before public release.

## Validation and remaining steps

Local validation passed: 210 targeted Korlix AI/shared calling checks, 27 standalone Messenger tests, nine release identity/signing guard tests, focused Korlix AI analysis and full Messenger analysis. Codemagic's current JSON schema, the new Bash scripts, the modified plist and `git diff --check` pass. Dependency lockfiles were preserved. Both native iOS simulator jobs passed in GitHub run [40772911905](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40772911905) at commit `1303f07561c4648119605d9ce8ad6e9232821181`. The corrected release-configuration step and both simulator jobs also passed in [40775904152](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40775904152). This is not signed-device or App Store validation.

## Live release attempt

Codemagic build `6ae26d64206ce93970c705c7` resolved the existing Apple app and confirmed latest build 133, selecting **12.0.3 (134)**. Signing identities and all targeted checks succeeded. It stopped before archive/upload because direct `pod install` saw the old iOS 13 deployment target. The successful simulator job had migrated this automatically to iOS 15.

The release fix makes the root deployment target explicitly iOS 15, matching Flutter 3.47, and runs `flutter build ios --release --config-only --no-codesign` before profile application. This prepares the native dependencies for both the existing CocoaPods app and Messenger's Swift Package Manager/CocoaPods combination. CI now exercises that release configuration step before simulator compilation.

Codemagic's provisioning-profile inventory and its live Fetch profiles result both contain only the Korlix AI profile (`com.korlixdeveloper.korlixai`). No Messenger profile was available. No signing record was downloaded, generated, changed or removed. Messenger's App Store app record remains unverified; a missing provisioning profile does not establish whether that app record exists.

A configuration transfer was truncated at commit `a59ab1d`; build `6ae2707f206ce93970c706d4` was canceled during source preparation before signing/upload. Commit `e65a6b548656766bbfdcbddab8e1d8f939f22fd0` restores the complete identity lookup and tests. All six follow-up files were compared byte for byte with GitHub after the restore. The app source, release configuration and simulator checks from run 40775904152 are unchanged by that repair.

Corrected Codemagic build: `6ae27102206ce93970c70704`, from `e65a6b5`. Its Apple lookup, regression checks, native configuration, signed archive and exported IPA verification passed. Apple accepted all 84,330,208 bytes with no upload errors at 22:15:01 UTC (delivery `86f4e8c1-54a8-4f91-a1f7-34c0ea82deeb`). The verified IPA SHA-256 is `4d26e9857db915ceb0450003910b8e67d34cb025dbb86af13fb5028b68f6d4f5`. Minimum iOS is 15.0. Apple finished processing build `86f4e8c1-54a8-4f91-a1f7-34c0ea82deeb`. Codemagic created App Store version `c1307383-13b9-4250-aaac-4e9241bf61ef` for 12.0.3, saved the release notes and submitted review `cae973b9-318e-4a12-af42-52dac837cd82`. Apple returned **WAITING_FOR_REVIEW** at `2026-10-28T22:18:24.938Z`. Release type is `AFTER_APPROVAL`; phased release is disabled. Codemagic finished successfully. This confirms submission, not Apple approval or public release.

The standalone Messenger listing copy is in `messenger-appstore-draft.json`; it is not saved in Apple's console. The live public privacy and deletion pages returned HTTP 200 and explicitly named Messenger on October 28. No reviewer credentials were copied into the draft.

Remaining steps:

1. Korlix AI: await Apple's review decision. The submitted update is set to release after approval. No repeat upload or submission is needed for 12.0.3 (134).
2. Messenger: complete App Store Connect sign-in, locate or create its separate record for `com.korlixdeveloper.messenger`, and complete actual iPhone/iPad screenshots, privacy answers, age rating, support/privacy links, category and reviewer access. The saved listing is draft copy only.
3. Complete Messenger signing/push setup and physical-device behavior checks, including its production APNs provider. The Android call reported at 90 seconds was manually stopped; it is not an iOS device test. Server APNs readiness remains unverified.
4. Run `korlix-messenger-ios-appstore` from the release branch only after its separate Apple app/profile and review metadata are ready. Verify its exported artifact identity, Apple processing and review submission. Do not reuse the Korlix AI provisioning profile.
5. Preserve the exact signed artifacts and Apple IDs in `release-status.json`. Future credential use, legal agreements or new security access must follow the appropriate user action; the declined Apple two-factor request was not retried.

References: [Codemagic signing](https://docs.codemagic.io/yaml-code-signing/signing-ios/), [Codemagic App Store publishing](https://docs.codemagic.io/yaml-publishing/app-store-connect/), [Apple new-version workflow](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version).
