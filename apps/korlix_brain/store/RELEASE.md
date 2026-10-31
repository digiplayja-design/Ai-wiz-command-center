## Voice latency update — build 5

Three production requests on 2026-10-31 took 6,995 / 7,930 / 10,951 ms on the backend, excluding transcription and speech startup. Build 5 streams complete phrases to the existing speech-only Realtime session as Astra produces them. It preserves gpt-6-astra / max, direct memory-save authorization and interruption behavior. Speech chunks count as one turn while every audio token remains metered.

The paired backend retains the JSON route for build 3, enables semantic VAD high for Brain only, overlaps fresh memory reads with allowance checks, and logs timing fields without transcripts or account identifiers. No model or paid service-tier change is made. Max reasoning time remains; measured on-device improvement is pending.

Validation: 31 Flutter tests, including incremental UTF-8, truncation, account changes, ordering, early speech, late response cancellation, and save acknowledgement; 39 backend tests; and 23 iOS release checks. Build 5 passed signing and upload, and Apple processing is complete. Automatic approval review blocked assigning this exact release to the existing internal group; that step awaits user approval. The complete release status is recorded in release-status.json.

# Brain+Voice release handoff

## Dedicated identity

| Field | Value |
| --- | --- |
| App name | KORLIX Brain+Voice |
| Apple bundle ID / Android package | `com.korlix.brain` |
| Version / minimum source build | `1.0.1` / `5` |
| Apple team | `FJKJ9MUDZ4` |
| Apple app ID | `6829319523` |
| Apple SKU | `KORLIX-BRAIN-VOICE-IOS` |
| Primary language | English (U.S.) |
| Platforms | iPhone and iPad |
| Store icon | Purple, red, green and gold KORLIX emblem |

The dedicated [Apple app record](https://appstoreconnect.apple.com/apps/6829319523/distribution/info) is created. **Version 1.0.1 (5) has completed Apple processing and awaits assignment to [KORLIX Brain Internal](https://appstoreconnect.apple.com/teams/f6169920-6326-4780-9d14-81013fac8eb0/apps/6829319523/testflight/groups/ae86d9a2-5bdf-4f3d-910b-aa532675951f/builds).** Build 3 remains Testing in that group. The group has one approved existing tester. Automatic distribution is disabled. App Store review has not been submitted. The user reported slow voice on build 3; a measured physical-device conversation with build 5 remains pending.

Apple rejected build 2 during processing (ITMS-90683) for missing camera and photo-library descriptions and warned about a missing location description. Build 3 includes all three and checks the exported IPA before upload. Its four-color icon is visible in Apple's processed build. Apple listing text is saved in the version 1.0.1 draft. Google Play listing ID remains unverified. Never reuse another KORLIX app's store record or bundle identity.

## iOS build route

Codemagic application: `6a32198d2d0806059c3df062`. Development/candidate branch: `feature/korlix-brain-voice-20261031`. Explicit upload branch: `release/korlix-brain-testflight-20261031`.

The [final signed build-5 pipeline](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6ae66ba86a1999f83b5c8371) succeeded on October 31, 2026, including dedicated provisioning, analysis, 31 app tests, 23 release checks, IPA export, signature verification and Apple upload. [GitHub validation](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41247985018) passed Android, simulator and iPhoneOS arm64 compilation for the preceding build-4 code. Build 5 adds the final cancellation-order fix and was compiled in the signed pipeline. Its IPA remains in Codemagic; it has not been downloaded into this source archive. The superseded build-4 upload pipeline was canceled before IPA export/upload.

1. Run `korlix-brain-ios-candidate`. A push trigger is configured for this branch; it requires the repository's Codemagic webhook to be active. The workflow imports the existing managed KORLIX distribution certificate, registers/selects `com.korlix.brain`, and installs its dedicated App Store profile. The original KORLIX profile is only used to import the certificate and cannot pass Brain+Voice artifact verification. No store upload occurs in this workflow.
2. Use the existing Apple app record `6829319523` with bundle `com.korlix.brain`. Keep its account access policy; do not create a duplicate record.
3. Run `korlix-brain-ios-testflight`, or push the reviewed source to `release/korlix-brain-testflight-20261031`. That release branch alone triggers upload. It first queries Apple for the exact app record; a successful empty response produces a distinct “App Store Connect record is missing for com.korlix.brain” failed step. Authentication/API errors stop at the query step instead. With the app record present, it chooses a build number above existing builds, verifies the signed IPA, and uploads to App Store Connect. It does not submit for external beta or App Store review, assign testers, or send invitations.
4. TestFlight beta information is saved. Build 3 is assigned to `KORLIX Brain Internal`. Build 5 has finished processing but is not assigned: automatic approval review rejected that action because it considered the exact release unauthorized. Once the user approves distribution of build 5, add it to the existing internal group and verify Testing. Do not add testers or resend invitations. Automatic distribution remains disabled. Verify an authenticated physical-device session before App Store submission.

The previous privacy correction shipped as build 3 from release commit `2a4d2737b14222fde1d407d0da6d3fc043d9119e` and passed Apple processing. Final streaming build 5 uses app-code commit `816eee71abfecd2ebe4989fb8ce901af16bec83a` and release commit `afb7eed81fd032e914f28d208801cff12aa5816a`. Its upload completed at 2026-10-31T22:37:09Z; Apple build ID is `3a95a0e0-40ba-41f3-bffc-34cbdcb57d89`. All privacy-purpose checks remain in place. The iOS flow still imports documents and requests audio for voice; adding purpose strings does not itself request camera, photos or location.

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
