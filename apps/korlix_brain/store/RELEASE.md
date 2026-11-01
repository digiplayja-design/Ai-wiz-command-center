## Native Live Conversation — build 9

The user selected Live + Deep Think after measured build-8 Sol Max first-text delays of 3,883 / 6,820 / 13,446 ms. Account preparation took 47 / 64 / 82 ms. Live is now the default and uses native `gpt-realtime-2.1` / low with Marin. It does not wait for ASR or Sol on ordinary replies. Deep Think retains `gpt-6.1-sol` / max. Mode changes require stopping the current conversation.

Direct memory commands are executed only against the original user transcript by the authenticated server. Tool-supplied content cannot replace it; acknowledged writes, ownership, idempotency and allowance remain enforced. Stop and barge-in suppress stale continuations. Live audio timing is content-free and explicitly marked client-reported. No claim of measured phone latency is made before device testing.

Validation: 53 Flutter tests, analysis, 34 Brain backend tests, 20 agent-studio tests, 13 shared-agent checks, 23 release checks and UI checks at 320 / 390 / 768 / 1024 pixels. **Version 1.0.1 (9) is uploaded and Apple processing is complete; internal distribution is pending.** The [signed pipeline](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6ae69eaca74da3772d1eab3a) completed at 2026-11-01T02:12:14Z; it repeated app and release checks, verified IPA identity, purpose strings, profile and signature, and uploaded successfully. Apple processing is verified; Apple build ID is `d681aa25-898b-4d77-b1b1-f67f45c1a087`.

App code: `bd6fae9f854786a323705cbe86061f672cc2e21a`. Release commit: `2803adee82ecde6798552efbcaef068426b9cf3c`. Production backend: `8dff4033d983cb10aafe3cb032b13fadaf18418d`, Render deploy `dep-dbj9sq7b9u1s73deb3a0`, verified live. The existing group retains its one tester and builds 8, 7, 6, 5 and 3. Automatic approval review rejected opening Add Build to Group because it did not recognize explicit authorization for this specific distribution change. Obtain explicit approval to assign build 9 to KORLIX Brain Internal, with no new testers or invitations. No invitations or public App Store submission were sent. Physical-device native audio timing remains pending.

## Sol 6.1 reasoning migration — build 8

Build 8 selects GPT-6.1 Sol (`gpt-6.1-sol`) with the user's previously requested
Max reasoning effort. Rici's Marin speech voice, protected identity, direct
memory saves and the persistent red Stop button are preserved. Streaming and
quick app phrases remain enabled. No automatic fallback or paid processing-tier
upgrade is introduced.

App code: `71af10143c640f614f01c22dd879f3c3332e894b`. Release commit:
`df692ff2c868c2c589635c242f0cd611f21115c6`. [Build-8 pipeline](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6ae68f72a74da3772d1e758e).
Production backend: `986d9d21c12c32c015d01c7bcdd55c449ef5fc19`, Render deploy
`dep-dbj8ui0473hc739nu67g`, verified live. OpenAI's model metadata endpoint
returned HTTP 200 with the exact Sol model for the existing server key. This is
model discovery, not a completed inference or latency benchmark.

Validation: 41 Flutter tests and clean analysis (also passed in signed CI),
29 Brain backend tests, 20 agent-studio tests, 13 legacy-agent checks, 23 release
checks and four viewport UI checks. The Sol protocol and output verification
reject Astra or another model; installed Astra builds retain their original
session profile. **Version 1.0.1 (8) is Testing in KORLIX Brain Internal.**
The signed pipeline completed at 2026-11-01T01:06:49Z. Apple processing and
existing-group assignment are verified; Apple build ID is
`f7244993-e1fd-448d-8fef-3dc0f1dcb63c`. The group retains its one existing tester
and builds 7, 6, 5 and 3. No invitations or public App Store submission were sent.
Physical-device speed and spoken quality still require verification; Max
reasoning can continue to add seconds.

## Rici identity, response startup and Stop — build 7

**Version 1.0.1 (7) is Testing in KORLIX Brain Internal.** The signed pipeline completed at 2026-11-01T00:35:38Z, and Apple processing and existing-group assignment are verified. Apple build ID: `90e1d36f-3483-4d0d-a9c5-d197cc2711f2`. [Build-7 pipeline](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6ae68823a74da3772d1e5bed).

The shared runtime could promote a training alias such as Kim above the Brain identity. A dedicated system prompt now keeps the spoken name Rici, with existing training and memories supplied as lower-priority account data. The acoustic voice remains Marin. Exact standalone connection/name checks use metered app phrases without an Astra request; substantive and compound questions retain GPT-6 Astra with max reasoning. Direct memory capture has priority. First complete sentences can enter speech without the former 60-character minimum.

A fixed 58px red Stop conversation control remains visible on every app screen during connection, thinking and speech. Stop cancels pending starts and disables microphone/playback before cleanup; late events cannot restore the old conversation.

Validation: 39 Flutter tests, clean analysis, 45 Brain/agent-studio tests, 13 shared-agent checks, 23 release checks, and UI verification at 320, 390, 768 and 1024 pixels. Signed CI repeated the app and release checks and verified bundle identity, privacy-purpose strings, profile and signature. Build-6 first-text measurements were 2,234 / 5,363 / 7,955 ms; preparation was 50–59 ms. Build-7 spoken identity and end-to-end device timings still require verification. Max reasoning can still take seconds.

App-code commit: `cbfe964b46d419abe67370dae80a5ecf6da7939b`. Release commit: `bcb6a6da480602ac40fb8e138321f7544b2fd715`. Production backend: `c4fa44d14c35a65ecc4d11d0b5f850618645020b`, Render deploy `dep-dbj8jfgae00c73dgpsug`, verified live. Keep deploying the existing backend release branch, not the app branch. No new testers, invitations, public-review submission or service-tier change.

## Voice connection correction — build 6

The user reported “The server needs the Astra Max voice update” while the deployed server already advertised astra-max-v1 and returned a successful session. The native code inspected only session.created and immediately closed when the first event contained defaults or a different event layout. Build 6 sends one explicit speech-only session.update and keeps the microphone muted until session.updated acknowledges disabled automatic responses and the configured transcription model. It recognizes both nested and flat event serializers, treats nested fields as authoritative, ignores early conversation events, and stops on missing/unsafe acknowledgement or a 15-second setup timeout. No credentials, model, account checks, memory-save policy or backend release change is needed.

Validation: Flutter analysis and 37 app tests passed, including six regression scenarios for defaults, duplicate events, unsolicited acknowledgements, unsafe updates and serializer differences. All 23 release checks passed. Builds 5 and 6 are Testing in the existing internal group. The build-6 pipeline passed signing, IPA verification and Apple upload, which completed at 2026-10-31T22:58:49Z. Apple processing and group assignment are verified; Apple build ID is 62dfea86-1c40-4a05-90ce-1ab2c23dda60. Build 6 pipeline: https://codemagic.io/app/6a32198d2d0806059c3df062/build/6ae6700ba74da3772d1e02f4. Build-6 production conversation requests subsequently succeeded; build-7 device verification remains pending.

## Voice latency update — build 5

Three production requests on 2026-10-31 took 6,995 / 7,930 / 10,951 ms on the backend, excluding transcription and speech startup. Build 5 streams complete phrases to the existing speech-only Realtime session as Astra produces them. It preserves gpt-6-astra / max, direct memory-save authorization and interruption behavior. Speech chunks count as one turn while every audio token remains metered.

The paired backend retains the JSON route for build 3, enables semantic VAD high for Brain only, overlaps fresh memory reads with allowance checks, and logs timing fields without transcripts or account identifiers. No model or paid service-tier change is made. Max reasoning time remains; measured on-device improvement is pending.

Validation: 31 Flutter tests, including incremental UTF-8, truncation, account changes, ordering, early speech, late response cancellation, and save acknowledgement; 39 backend tests; and 23 iOS release checks. Build 5 passed signing and upload, and Apple processing is complete. The user subsequently approved distribution, and build 5 is Testing in the existing internal group. The complete release status is recorded in release-status.json.

# Brain+Voice release handoff

## Dedicated identity

| Field | Value |
| --- | --- |
| App name | KORLIX Brain+Voice |
| Apple bundle ID / Android package | `com.korlix.brain` |
| Version / minimum source build | `1.0.1` / `9` |
| Apple team | `FJKJ9MUDZ4` |
| Apple app ID | `6829319523` |
| Apple SKU | `KORLIX-BRAIN-VOICE-IOS` |
| Primary language | English (U.S.) |
| Platforms | iPhone and iPad |
| Store icon | Purple, red, green and gold KORLIX emblem |

The dedicated [Apple app record](https://appstoreconnect.apple.com/apps/6829319523/distribution/info) is created. **Build 9 is processed and awaiting internal distribution approval. Version 1.0.1 (8) remains Testing in [KORLIX Brain Internal](https://appstoreconnect.apple.com/teams/f6169920-6326-4780-9d14-81013fac8eb0/apps/6829319523/testflight/groups/ae86d9a2-5bdf-4f3d-910b-aa532675951f/builds).** Builds 3, 5, 6 and 7 remain available in that group. The group has one approved existing tester. Automatic distribution is disabled. App Store review has not been submitted. The user reported slow voice and a conflicting name on build 6; build-8 logs confirmed Sol first-text delays, and build-9 native live audio verification remains pending.

Apple rejected build 2 during processing (ITMS-90683) for missing camera and photo-library descriptions and warned about a missing location description. Build 3 includes all three and checks the exported IPA before upload. Its four-color icon is visible in Apple's processed build. Apple listing text is saved in the version 1.0.1 draft. Google Play listing ID remains unverified. Never reuse another KORLIX app's store record or bundle identity.

## iOS build route

Codemagic application: `6a32198d2d0806059c3df062`. Development/candidate branch: `feature/korlix-brain-voice-20261031`. Explicit upload branch: `release/korlix-brain-testflight-20261031`.

The [final signed build-5 pipeline](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6ae66ba86a1999f83b5c8371) succeeded on October 31, 2026, including dedicated provisioning, analysis, 31 app tests, 23 release checks, IPA export, signature verification and Apple upload. [GitHub validation](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41247985018) passed Android, simulator and iPhoneOS arm64 compilation for the preceding build-4 code. Build 5 adds the final cancellation-order fix and was compiled in the signed pipeline. Its IPA remains in Codemagic; it has not been downloaded into this source archive. The superseded build-4 upload pipeline was canceled before IPA export/upload.

1. Run `korlix-brain-ios-candidate`. A push trigger is configured for this branch; it requires the repository's Codemagic webhook to be active. The workflow imports the existing managed KORLIX distribution certificate, registers/selects `com.korlix.brain`, and installs its dedicated App Store profile. The original KORLIX profile is only used to import the certificate and cannot pass Brain+Voice artifact verification. No store upload occurs in this workflow.
2. Use the existing Apple app record `6829319523` with bundle `com.korlix.brain`. Keep its account access policy; do not create a duplicate record.
3. Run `korlix-brain-ios-testflight`, or push the reviewed source to `release/korlix-brain-testflight-20261031`. That release branch alone triggers upload. It first queries Apple for the exact app record; a successful empty response produces a distinct “App Store Connect record is missing for com.korlix.brain” failed step. Authentication/API errors stop at the query step instead. With the app record present, it chooses a build number above existing builds, verifies the signed IPA, and uploads to App Store Connect. It does not submit for external beta or App Store review, assign testers, or send invitations.
4. Build 9 has completed processing but is not assigned to the internal group. Obtain explicit approval for that distribution step following the automatic approval review rejection. TestFlight beta information is saved. Builds 8, 7, 6, 5 and 3 are assigned to the existing `KORLIX Brain Internal` group under the user's distribution approval, and Apple shows Testing. Do not add testers or resend invitations. Automatic distribution remains disabled. Verify an authenticated physical-device session before App Store submission.

The previous privacy correction shipped as build 3 from release commit `2a4d2737b14222fde1d407d0da6d3fc043d9119e` and passed Apple processing. Final streaming build 5 uses app-code commit `816eee71abfecd2ebe4989fb8ce901af16bec83a` and release commit `afb7eed81fd032e914f28d208801cff12aa5816a`. Its upload completed at 2026-10-31T22:37:09Z; Apple build ID is `3a95a0e0-40ba-41f3-bffc-34cbdcb57d89`. All privacy-purpose checks remain in place. The iOS flow still imports documents and requests audio for voice; adding purpose strings does not itself request camera, photos or location.

The signing tools use the existing `Codemagic Korlix AI` integration and `KORLIX_APP_STORE_CERT` reference. No credentials are embedded in source. No certificate is created or revoked. Failed Apple lookups stop the build rather than resetting numbering.

GitHub validation independently compiles an unsigned iPhoneOS arm64 release binary as well as Android and simulator test builds. An unsigned app or simulator ZIP cannot be installed through TestFlight. A signed candidate IPA alone does not mean Apple has received or approved it.

## Store material

`listing-en-US.json` contains listing text, support and policy links. Apple listing text and the TestFlight beta description, feedback email, marketing URL and privacy URL have been saved. Google Play text remains a draft. `apple/testflight-notes.txt` contains tester notes. `apple/app-icon-1024.png` and `google-play/app-icon-512.png` contain the requested four-color icon.

Reviewer instructions: sign in using a working review account supplied privately in each store console. Accept the third-party AI notice, start Talk with Rici, grant microphone permission, and ask a question. Say “Rici, remember this: My preferred example color is purple.” Wait for the save acknowledgment, open My Brain, confirm the item, then delete it. Say “Rici, remember this instruction: Use short answers.” Confirm it appears as a removable instruction. Stop voice before signing out. Verify that the review account has sufficient allowance; never put reviewer credentials in this repository.

Before submission, capture real-device screenshots, verify the account review flow and both Live Conversation and Deep Think, and complete privacy, age-rating and microphone/background-audio declarations from the implemented data flows. The account offers age ranges starting at 16; store age-rating questionnaires must still be completed. Pricing and purchase arrangements are unchanged. Android store signing and a dedicated Play listing remain to be configured.

## Verification still requiring a signed-in device

- Native Live Conversation with measured speech-stop to first-audio timing, optional Sol Max Deep Think, and correct pronunciation of Rici (Ree-see).
- Direct save, persistence after reconnect, instruction use on the next turn, and deletion.
- No duplicate saves after repeated transcript events; ordinary conversation is not saved.
- Permission denial/recovery, interruption, Bluetooth output, quota errors, app switching, screen lock and Stop.
- Account deletion request and AI-response report acknowledgment.

Backend releases must use `release/signup-plan-intent-20261021`; this app branch retains an older backend snapshot. Do not deploy its backend. Build-9 default Live protocol is `rici-live-v1`, model `gpt-realtime-2.1`, effort `low`; Deep Think retains `sol-6.1-max-v1` / `gpt-6.1-sol` / `max`. Older app builds retain `astra-max-v1` / `gpt-6-astra`. Public health verifies configuration; the separate startup model-discovery check does not benchmark inference.

References: [Codemagic automatic builds](https://docs.codemagic.io/yaml-running-builds/starting-builds-automatically/), [Codemagic App Store publishing](https://docs.codemagic.io/yaml-publishing/app-store-connect/), [Apple app record creation](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).
