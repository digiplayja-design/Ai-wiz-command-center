# Korlix AI and Messenger iOS release preparation — October 28, 2026

The owner requested an updated Korlix AI App Store release after Apple approved the earlier submission, plus the latest KORLIX Messenger on the App Store. This authorizes preparing, uploading and submitting both apps. **Neither new iOS release has been uploaded or submitted during this task.** Browser access recovered. The existing Codemagic session and Apple API integration work. App Store Connect web sign-in reached two-factor verification, which the owner declined; no subsequent authentication method was attempted.

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

Korlix AI reuses the existing `Codemagic Korlix AI` integration and existing profile/certificate references. Messenger uses the same integration with signing-file lookup restricted to its own bundle ID and App Store distribution. Its Apple identifier, profile and signing capabilities must exist in Codemagic first. No credentials, profiles, certificates, permissions or Apple records were created or changed in this task.

Signing is restricted to the selected Runner project so the monorepo's other apps are not assigned the wrong profile. Exported packages are checked for the expected app, version, build number, iPhoneOS platform, App Store profile, distribution entitlements and valid code signature before entering the publishable artifact directory. Build metadata management during export is disabled so the verified build number is preserved.

Release notes are supplied separately for each app. Neither set of notes promises originating screen sharing from an iPhone. This release receives shared screens on iOS; it does not add a ReplayKit broadcast extension.

## Messenger notifications

Messenger Release/Profile configurations now select `RunnerPush.entitlements` and the production APNs environment; Debug keeps its existing base entitlements. The runtime reads the build setting through `KorlixAPNsEnvironment`. An exported Messenger IPA must contain matching production APNs configuration in its Info.plist, provisioning profile and actual signed entitlements, or upload preparation fails.

This source change is not proof that notification delivery works. Confirm that Apple's Messenger identifier has Push Notifications enabled, refresh its App Store provisioning profile in Codemagic, and verify the existing server APNs provider allows the Messenger bundle ID and preserves app/session isolation. No APNs key was created, copied or exposed. Check actual foreground/background notifications, taps/replies, account switching and logout on a physical iPhone before public release.

## Validation and remaining steps

Local validation passed: 210 targeted Korlix AI/shared calling checks, 27 standalone Messenger tests, nine release identity/signing guard tests, focused Korlix AI analysis and full Messenger analysis. Codemagic's current JSON schema, the new Bash scripts, the modified plist and `git diff --check` pass. Dependency lockfiles were preserved. Both native iOS simulator jobs passed in GitHub run [40772911905](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/40772911905) at commit `1303f07561c4648119605d9ce8ad6e9232821181`. This is not signed-device or App Store validation.

## Live release attempt

Codemagic build `6ae26d64206ce93970c705c7` resolved the existing Apple app and confirmed latest build 133, selecting **12.0.3 (134)**. Signing identities and all targeted checks succeeded. It stopped before archive/upload because direct `pod install` saw the old iOS 13 deployment target. The successful simulator job had migrated this automatically to iOS 15.

The release fix makes the root deployment target explicitly iOS 15, matching Flutter 3.47, and runs `flutter build ios --release --config-only --no-codesign` before profile application. This prepares the native dependencies for both the existing CocoaPods app and Messenger's Swift Package Manager/CocoaPods combination. CI now exercises that release configuration step before simulator compilation.

Codemagic's provisioning-profile inventory and its live Fetch profiles result both contain only the Korlix AI profile (`com.korlixdeveloper.korlixai`). No Messenger profile was available. No signing record was downloaded, generated, changed or removed. Messenger's App Store app record remains unverified; a missing provisioning profile does not establish whether that app record exists.

Remaining steps:

1. Inspect App Store Connect's actual Korlix AI version/release state and current builds. Prepare version 12.0.3 in the existing record, preserving approved purchases, review access and verified metadata. Check changed privacy answers against the current implementation.
2. Locate or create Messenger's separate record with the exact bundle ID. Complete its actual iPhone/iPad screenshots, privacy answers, age rating, support/privacy links, category and reviewer access; no new metadata is claimed saved yet.
3. Complete and verify Messenger signing/push setup and physical-device behavior. The Android call reported at 90 seconds was manually stopped; it is not an iOS device test.
4. Run the two named Codemagic workflows from the release branch. Verify the exported artifact identity, Apple processing and each review submission in App Store Connect. Resolve any new legal agreement or authentication challenge through the appropriate user action.
5. Record exact signed build numbers, Codemagic build IDs, artifact hashes and Apple submission states. Report an update as submitted or live only after the corresponding Apple state is observed.

References: [Codemagic signing](https://docs.codemagic.io/yaml-code-signing/signing-ios/), [Codemagic App Store publishing](https://docs.codemagic.io/yaml-publishing/app-store-connect/), [Apple new-version workflow](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version).
