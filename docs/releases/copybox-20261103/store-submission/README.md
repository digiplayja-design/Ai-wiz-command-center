# KORLIX COPY Box — submission content

Prepared November 3, 2026, for the independent app
`com.korlixdeveloper.copybox`, version `1.0.0`.

This package contains prepared text and evidence for the store forms. It does not
record a store upload, a completed privacy declaration, or approval. Store IDs,
signing credentials, reviewer credentials, pricing, and distribution choices are
not invented or stored here.

The store text is complete. A signed store release and store submission have not
been completed, and physical-device/live-account acceptance remains outstanding.
The separate build and asset records document the verification that has actually
run.

All twelve store screenshots are generated, packaged and visually reviewed from
the final app source. The Play feature graphic and upload icon are also prepared.
Use the paths and checksums in the [asset manifest](../store-assets/manifest.json)
when populating the store listings.

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

The final app source for this handoff is
`d611bc6a1b5c8b6d7e3805725c6d7c5fe617f7e4`, with verification recorded in
[run 10](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41844773126)
and the [release record](../README.md). That run passed 59 shared tests and 81 app
tests (140 total), reported no analyzer issues, and built the Android debug APK,
iOS simulator app and web preview. These are test/preview builds, not signed
store candidates. The backend evidence was inspected from
`origin/release/k135z-backend-render-20260919` at
`92cad91d290d4ac93d273960c1144798f3afd14f`. Reading that snapshot does not prove the
live server runs that commit. Confirm the deployed revision and actual provider
configuration before submitting final data-handling attestations.

The public privacy, terms, deletion, and support pages were retrievable on
November 3, 2026. The retrieved versions principally named KORLIX AI and
Messenger; the scoped additions in this folder have not been published.

## Remaining form inputs

- Verify the new Apple app record and Google Play app record for the exact ID.
- Upload the twelve prepared screenshots, Play feature graphic and Play icon
  to the corresponding listing slots. The
  [asset manifest](../store-assets/manifest.json) records their exact paths,
  dimensions and checksums. The earlier interface previews are not the upload set.
- Supply a dedicated, working KORLIX reviewer login with sufficient AI allowance
  and available device capacity through the consoles' private review fields. No
  reviewer account was created by preparing these files. Fill Apple's reviewer
  contact phone with the authorized account holder's actual number.
- Configure the COPY Box Android upload key and Apple provisioning profile,
  generate signed candidates, and complete physical-device/live-account
  acceptance before submitting the release.
- Complete the age/content questionnaires against the signed app. The account
  signup rule is 16+, but it does not determine the store rating automatically.
- Confirm operational retention, processor treatment, deletion fulfilment, and
  the final privacy answers using [privacy-evidence.md](privacy-evidence.md).
- Apply the user's actual price, availability, and release choices. This package
  introduces no subscription product, trial, paid price, or purchase promise.

## Official field references

- [Apple app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information): app name and subtitle, 30 characters each.
- [Apple platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information): promotional text, 170 characters; keywords, 100 bytes; description, 4,000 characters; contact-bearing support URL.
- [Google app setup](https://support.google.com/googleplay/android-developer/answer/9859152?hl=en): title, 30 characters; short description, 80 characters; full description, 4,000 characters.

Limits were checked against those official sources. Actual counts are recorded
in `metadata.en-US.json`.
