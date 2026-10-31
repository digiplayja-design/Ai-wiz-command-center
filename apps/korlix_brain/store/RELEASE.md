# Brain+Voice release handoff

## Dedicated identity

| Field | Value |
| --- | --- |
| App name | KORLIX Brain+Voice |
| Apple bundle ID / Android package | `com.korlix.brain` |
| Version / minimum source build | `1.0.1` / `3` |
| Apple team | `FJKJ9MUDZ4` |
| Apple app ID | `6829319523` |
| Apple SKU | `KORLIX-BRAIN-VOICE-IOS` |
| Primary language | English (U.S.) |
| Platforms | iPhone and iPad |
| Store icon | Purple, red, green and gold KORLIX emblem |

The dedicated [Apple app record](https://appstoreconnect.apple.com/apps/6829319523/distribution/info) was created on October 31, 2026. Its name, subtitle, Productivity category, version 1.0.1 draft, description, keywords and support URL are saved. Access is limited to the existing authorized account users. The earlier missing-record blocker is resolved; the [new TestFlight upload](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6ae6612f6a1999f83b5c5925) succeeded from commit `13692038da1db765afd4860f8dc62f514a46cc8e`; Apple subsequently rejected build 2 during processing (ITMS-90683) for missing camera and photo-library usage descriptions, with a location-description warning. Build 3 adds all three descriptions and verifies them in the exported IPA before upload. Google Play listing ID remains unverified. Never reuse another KORLIX app's store record or bundle identity.

## iOS build route

Codemagic application: `6a32198d2d0806059c3df062`. Development/candidate branch: `feature/korlix-brain-voice-20261031`. Explicit upload branch: `release/korlix-brain-testflight-20261031`.

The [signed candidate build](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6ae65911a74da3772d1da5c1) succeeded on October 31, 2026, including dedicated provisioning, app tests, IPA export and signature verification. [GitHub validation](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41242264204) passed Android, simulator and iPhoneOS arm64 release builds. The candidate IPA remains in Codemagic; it has not been downloaded into this source archive. The build service's authenticated artifact API is not available in this session.

1. Run `korlix-brain-ios-candidate`. A push trigger is configured for this branch; it requires the repository's Codemagic webhook to be active. The workflow imports the existing managed KORLIX distribution certificate, registers/selects `com.korlix.brain`, and installs its dedicated App Store profile. The original KORLIX profile is only used to import the certificate and cannot pass Brain+Voice artifact verification. No store upload occurs in this workflow.
2. Use the existing Apple app record `6829319523` with bundle `com.korlix.brain`. Keep its account access policy; do not create a duplicate record.
3. Run `korlix-brain-ios-testflight`, or push the reviewed source to `release/korlix-brain-testflight-20261031`. That release branch alone triggers upload. It first queries Apple for the exact app record; a successful empty response produces a distinct “App Store Connect record is missing for com.korlix.brain” failed step. Authentication/API errors stop at the query step instead. With the app record present, it chooses a build number above existing builds, verifies the signed IPA, and uploads to App Store Connect. It does not submit for external beta or App Store review, assign testers, or send invitations.
4. TestFlight beta information is saved, and the `KORLIX Brain Internal` group exists with automatic distribution disabled. After Apple processes the build, add it to this group. The owner explicitly approved the testing invitation and the chosen existing account was added; the group has one tester. Verify an authenticated physical-device session before App Store submission.

The signing tools use the existing `Codemagic Korlix AI` integration and `KORLIX_APP_STORE_CERT` reference. No credentials are embedded in source. No certificate is created or revoked. Failed Apple lookups stop the build rather than resetting numbering.

GitHub validation independently compiles an unsigned iPhoneOS arm64 release binary as well as Android and simulator test builds. An unsigned app or simulator ZIP cannot be installed through TestFlight. A signed candidate IPA alone does not mean Apple has received or approved it.

## Store material

`listing-en-US.json` contains listing text, support and policy links. Apple listing text and the TestFlight beta description, feedback email, marketing URL and privacy URL have been saved. Google Play text remains a draft. `apple/testflight-notes.txt` contains tester notes. `apple/app-icon-1024.png` and `google-play/app-icon-512.png` contain the requested four-color icon.

Reviewer instructions: sign in using a working review account supplied privately in each store console. Accept the third-party AI notice, start Talk with Rici, grant microphone permission, and ask a question. Say “Rici, remember this: My preferred example color is purple.” Wait for the save acknowledgment, open My Brain, confirm the item, then delete it. Say “Rici, remember this instruction: Use short answers.” Confirm it appears as a removable instruction. Stop voice before signing out. Verify that the review account has sufficient allowance; never put reviewer credentials in this repository.

Before submission, capture real-device screenshots, verify the account review flow and live Astra access, and complete privacy, age-rating and microphone/background-audio declarations from the implemented data flows. The account offers age ranges starting at 16; store age-rating questionnaires must still be completed. Pricing and purchase arrangements are unchanged. Android store signing and a dedicated Play listing remain to be configured.

## Verification still requiring a signed-in device

- A two-way Astra Max conversation and correct pronunciation of Rici (Ree-see).
- Direct save, persistence after reconnect, instruction use on the next turn, and deletion.
- No duplicate saves after repeated transcript events; ordinary conversation is not saved.
- Permission denial/recovery, interruption, Bluetooth output, quota errors, app switching, screen lock and Stop.
- Account deletion request and AI-response report acknowledgment.

Backend releases must use `release/signup-plan-intent-20261021`; this app branch retains an older backend snapshot. Do not deploy its backend. Production Brain voice protocol is `astra-max-v1`, model `gpt-6-astra`, reasoning effort `max`; public health verifies configuration, not authenticated model access.

References: [Codemagic automatic builds](https://docs.codemagic.io/yaml-running-builds/starting-builds-automatically/), [Codemagic App Store publishing](https://docs.codemagic.io/yaml-publishing/app-store-connect/), [Apple app record creation](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).
