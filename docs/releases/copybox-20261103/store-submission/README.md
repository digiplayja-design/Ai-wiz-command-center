# KORLIX COPY Box — submission content

Prepared November 3, 2026, for the independent app
`com.korlixdeveloper.copybox`, version `1.0.0`.

This package contains prepared text and evidence for the store forms. The
November 4 release checkpoint records Apple app **6830765098** and the successful
signed iOS 1.0.0 (1) upload. Public review, completed privacy declarations, and
physical-device/live-account acceptance remain outstanding. No reviewer
credentials or personal contact values are stored here. COPY Box price and
country availability have not been chosen.

See the [release status](../release-status.json) for verified console state and
evidence limitations. All twelve Apple screenshots and the verified public
listing fields are saved. The selected 1.0.0 (1) build persisted after reloading
the version tab, and App Information confirmed the subtitle and Productivity
category saved. The privacy URL is saved. The App Review section remains blank
after contact validation errors. All seven privacy categories are fully
configured in the saved draft: App Functionality, linked to user, and no tracking.
The source review supports no tracking; publication awaits the user's final
accuracy/compliance/update attestation. Age/content and content-rights answers
remain incomplete. This package does not establish that every required form is
complete.

All sixteen store screenshots are generated, packaged and visually reviewed.
The original twelve retain their final-app-source provenance; four additional
medium iPhone captures were produced in a focused run on November 4, 2026.
The Play feature graphic and upload icon are also prepared. Use the paths,
per-record capture sources, and checksums in the
[asset manifest](../store-assets/manifest.json) when populating the store listings.

## Files

| File | Use |
| --- | --- |
| [metadata.en-US.json](metadata.en-US.json) | Exact English listing fields, contact URLs, and field lengths |
| [description.txt](description.txt) | Shared plain-text full description for Google Play and Apple |
| [apple-review-notes.txt](apple-review-notes.txt) | App Review notes; supply the test account separately in secure review fields |
| [google-app-access.txt](google-app-access.txt) | Instructions for the restricted AI portion of the app |
| [google-app-access-short.txt](google-app-access-short.txt) | Compact additional-instructions field for the Play Console form |
| [testflight-what-to-test.txt](testflight-what-to-test.txt) | Concrete device acceptance instructions |
| [release-notes.txt](release-notes.txt) | Initial Android release notes; Apple does not request What's New for a first version |
| [privacy-evidence.md](privacy-evidence.md) | Source-backed data inventory and proposed store mappings |
| [public-page-additions.md](public-page-additions.md) | COPY Box-specific additions prepared for the existing public policy/support pages |
| [screenshot-plan.md](screenshot-plan.md) | Prepared upload assets, dimensions, alt text, and capture provenance |

The JSON points to the exact plain-text files rather than duplicating their
contents. Keep those files together when entering the forms.

## Evidence boundary

The source for the full automated-validation run is
`d611bc6a1b5c8b6d7e3805725c6d7c5fe617f7e4`, with verification recorded in
[run 10](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41844773126)
and the [release record](../README.md). That run passed 59 shared tests and 81 app
tests (140 total), reported no analyzer issues, and built the Android debug APK,
iOS simulator app and web preview. Those run-10 artifacts remain test/preview
builds. The later signed iOS candidate came from
`4dd07806ff471263b1fb82d593f300cfe9693a4d` in Codemagic build
`6aeb61e5004ce28f20edd5ba`; its successful upload is recorded separately in the
release status. The November 4 asset commit changes no app behavior or signing.

The original backend inventory at `92cad91d290d4ac93d273960c1144798f3afd14f` was
rechecked against the primary API's exact deployed revision,
`bf830fd98fd2e1846fed8b00e5ad73b69cbad6cb`, on November 4. This confirms the
inspected source's data-flow behavior; operational retention, provider terms,
live database migration state, and deletion fulfilment still require appropriate
confirmation before final data-handling attestations.

The public privacy, terms, deletion, and support pages were retrievable on
November 3, 2026. The retrieved versions principally named KORLIX AI and
Messenger. The scoped additions were merged in PR 43 as
`da283a8dfe7b51f68ad7b581b8555f017cac3c54`, with a tree matching reviewed source
`d810888cba620502e799a3022090e1a5f6748d9d`, but that exact commit has not been
deployed. The November 4 Render check still shows the October 25 live release.

## Remaining form inputs

- Verify/create the Google Play app record for the exact package. The separate
  Apple record is now verified as `6830765098`.
- Complete the blank Apple review section. The version build selection is saved
  and verified after reload. All twelve Apple screenshots are uploaded, with four images
  visible in each large-iPhone, medium-iPhone, and iPad well. Upload the Play
  screenshots, feature graphic, and icon after its app setup. The current Apple
  Media Manager requires the medium iPhone group; the large group is optional,
  and the prepared
  13-inch iPad group remains suitable. The
  [asset manifest](../store-assets/manifest.json) records their exact paths,
  dimensions and checksums. The earlier interface previews are not the upload set.
- Supply a dedicated, working KORLIX reviewer login with sufficient AI allowance
  and available device capacity through the consoles' private review fields. No
  reviewer account was created by preparing these files. Supply the authorized
  App Review business contact phone.
- Configure the COPY Box Android upload key and generate its signed candidate.
  Apple provisioning and the first signed upload are complete. Configure
  TestFlight testing and complete physical-device/live-account acceptance.
- Complete the age/content questionnaire after evaluating actual AI content
  frequency through a live account. The inspected questionnaire was cancelled
  without saving; the general generation route has no COPY Box topic/output
  filter. The 16+ signup rule does not determine the store rating. The content-
  rights form was inspected without submitting an answer.
- Obtain action-time user approval for the privacy publication attestation.
  All seven categories have saved App Functionality, linked-to-user, no-tracking
  details; the exact deployed-source review supports that tracking conclusion.
  Operational retention, processor treatment, and deletion fulfilment remain
  separate evidence questions in [privacy-evidence.md](privacy-evidence.md).
- Obtain COPY Box-specific price and availability choices, and resolve
  the updated Paid Apps Agreement with the account holder. Manual release is
  already saved for the Apple version. The November 2 free and worldwide
  approvals concerned Brain + Voice and were not applied here.
  This package introduces no subscription product, trial, paid price, or
  purchase promise.

## Official field references

- [Apple app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information): app name and subtitle, 30 characters each.
- [Apple platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information): promotional text, 170 characters; keywords, 100 bytes; description, 4,000 characters; contact-bearing support URL.
- [Google app setup](https://support.google.com/googleplay/android-developer/answer/9859152?hl=en): title, 30 characters; short description, 80 characters; full description, 4,000 characters.

Limits were checked against those official sources. Actual counts are recorded
in `metadata.en-US.json`.
