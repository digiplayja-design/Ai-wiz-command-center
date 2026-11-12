# Brain + Voice 1.0.2 (15): approved iOS upload

## Approved scope and identity

On November 12, 2026, the owner explicitly approved starting the prepared Codemagic workflow to build and upload the reviewed Brain + Voice candidate to App Store Connect for TestFlight testing. The exact-commit option was selected and SSH/VNC access remained disabled.

| Item | Observed value |
| --- | --- |
| App | KORLIX Brain+Voice |
| Version and build | 1.0.2 (15) |
| Bundle identifier | `com.korlix.brain` |
| Apple app record | `6829319523` |
| Source commit | `b3476487253701bf50a99344afd92b518e9151c7` |
| Workflow | KORLIX Brain+Voice — TestFlight upload |
| Codemagic build ID | `6af536485475be6952098d42` |
| Codemagic build index | 20 |
| Build account | `support@korlixdeveloper.com` |
| Distribution type | App Store |

[Codemagic build](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6af536485475be6952098d42)

## Observed validation

- The Apple-record query returned the exact Brain + Voice app record above.
- The release preparer found build 14 for version 1.0.1 and selected version 1.0.2, build 15.
- The app validation step completed; its log reported all 164 tests passed.
- Welcome, ambience, voice handoff, and transcript layout checks completed.
- The signed IPA build and verification step completed. Codemagic listed `BrainVoice.ipa` at 33.24 MB.
- The publishing log identified the same app, bundle, version, build number, and App Store distribution type before starting the Apple upload.

## Upload result

Apple's uploader reported **UPLOAD SUCCEEDED with no errors** at `2026-11-12 03:52:44.018` in the publishing log. The delivery UUID is `3f8912c8-d8b7-4f06-af13-af48ebe4c170`; the uploaded archive contained 34,856,900 bytes. Codemagic reported that the build completed successfully after 7 minutes 29 seconds, with the publishing step taking 1 minute 27 seconds.

Codemagic's App Store Connect distribution post-processing finished successfully in 3 minutes 14 seconds. After three initial pending observations, its log found the uploaded build in Apple's account with ID `3f8912c8-d8b7-4f06-af13-af48ebe4c170`. It then successfully modified the `en-US` Beta Build Localization `142a21ff-089a-409f-ad23-f0b8603a661d`, attaching the candidate's "What to Test" notes. The overall Codemagic status is **finished**.

This confirms Apple receipt, recognition of the uploaded build, and the successful TestFlight metadata update. The log did not display the build's exact TestFlight availability/compliance state or its group assignments. The App Store Connect browser was signed out, so tester-group access and device installation were not independently verified. No group-assignment or tester-invitation action was performed by the assistant or configured in this workflow.

The [upload confirmation screenshot](brain-testflight-upload-success-20261112.jpg) shows the app identity, version/build, and Apple's successful delivery response. It was captured when delivery had completed; final post-processing results were verified afterward in the completed build's log.

Screenshot SHA-256: `0ee849adaaf599d5eefa6004aed42ba95354aedbb211c06cc512e6330473a5e6`.

## Device testing scope

The [candidate release notes](https://github.com/digiplayja-design/Ai-wiz-command-center/blob/b3476487253701bf50a99344afd92b518e9151c7/apps/korlix_brain/store/apple/testflight-notes.txt) cover Pause, Resume, Stop, PDF imports to Memory/Training/Both, Camera Ask, Directions for the support account, and Live Conversation repairs. These features still require physical-device checks.

After this build becomes available to the intended tester, verify Live Conversation microphone input and replies; Pause/Resume/Stop during speech and connection; PDF review and save for each destination; photo capture and follow-up in Camera Ask; and reviewed destinations in Apple and Google Maps. Include a brief network interruption, app switching, and sign-out to check cleanup and recovery.

This workflow does not configure a beta group or submit the app for public App Store review. Upload success alone does not establish TestFlight installability. The workflow also does not activate embedded Projection on the production backend or establish native 3D, headset, or live-camera acceptance.
