# Brain+Voice release handoff

## Dedicated identity

| Field | Value |
| --- | --- |
| App name | KORLIX Brain+Voice |
| Apple bundle ID / Android package | `com.korlix.brain` |
| Version / minimum source build | `1.0.1` / `2` |
| Apple team | `FJKJ9MUDZ4` |
| Suggested Apple SKU | `KORLIX-BRAIN-VOICE-IOS` |
| Primary language | English (U.S.) |
| Platforms | iPhone and iPad |
| Store icon | Purple, red, green and gold KORLIX emblem |

Apple app ID and Google Play listing ID are not yet verified. Never reuse another KORLIX app's store record or bundle identity.

## iOS build route

Codemagic application: `6a32198d2d0806059c3df062`. Source branch: `feature/korlix-brain-voice-20261031`.

1. Run `korlix-brain-ios-candidate`. A push trigger is configured for this branch; it requires the repository's Codemagic webhook to be active. The workflow imports the existing managed KORLIX distribution certificate, registers/selects `com.korlix.brain`, and installs its dedicated App Store profile. The original KORLIX profile is only used to import the certificate and cannot pass Brain+Voice artifact verification. No store upload occurs in this workflow.
2. In [App Store Connect](https://appstoreconnect.apple.com/apps), create the new iOS app record using the identity above, if it does not already exist. Select the dedicated `com.korlix.brain` bundle. Keep the existing account access policy. Apple assigns the numeric app ID; do not invent one.
3. Run `korlix-brain-ios-testflight` on the same source branch. It requires the exact Apple app record, chooses a build number above existing builds, verifies the signed IPA, and uploads to App Store Connect. It does not submit for external beta or App Store review, assign testers, or send invitations.
4. After Apple processes the build, complete the app's TestFlight information and add the build to the intended internal testing group. Verify an authenticated physical-device session before App Store submission.

The signing tools use the existing `Codemagic Korlix AI` integration and `KORLIX_APP_STORE_CERT` reference. No credentials are embedded in source. No certificate is created or revoked. Failed Apple lookups stop the build rather than resetting numbering.

GitHub validation independently compiles an unsigned iPhoneOS arm64 release binary as well as Android and simulator test builds. An unsigned app or simulator ZIP cannot be installed through TestFlight. A signed candidate IPA alone does not mean Apple has received or approved it.

## Store material

`listing-en-US.json` contains draft listing text, support and policy links. `apple/testflight-notes.txt` contains tester notes. `apple/app-icon-1024.png` and `google-play/app-icon-512.png` contain the requested four-color icon.

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
