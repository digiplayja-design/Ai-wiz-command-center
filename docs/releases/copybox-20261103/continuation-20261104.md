# COPY Box continuation — November 4, 2026

## Completed in this continuation

The COPY Box-specific additions to the public Privacy Policy, Terms of Use,
Delete Account and Data, and Support and Reports pages are implemented in
[pull request 43](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/43).
The candidate is `d810888cba620502e799a3022090e1a5f6748d9d` on
`fix/copybox-public-pages-20261104`. It changes exactly four HTML files from
the currently live website commit `e38d6b73a37ff812a29da3b64027a35e01979c34`.

The text covers local workspaces and readable backups, optional account and AI
use, remembered provider consent, stored account AI history, AI output reports,
shared-account deletion requests, and the exact Settings/support controls.
All four pages have balanced HTML structure and unique IDs. All 123 relative
links and fragment targets were checked. Existing styles and other files are
unchanged.

The core data-flow claims were also checked against the primary API's exact live
source, `bf830fd98fd2e1846fed8b00e5ad73b69cbad6cb`. See
[privacy evidence](store-submission/privacy-evidence.md). This does not establish
operational retention periods or prove live account/deletion acceptance.

## Website publication remains pending

The confirmed existing Render workspace is `tea-d8cskuf7f7vs73emq1p0` (Digiplay's
workspace). Website service `srv-d8ekf7t7vvec73dpar60`, `korlixdeveloper-website`,
publishes `website` and has automatic deployments disabled.

Its current live deploy is `dep-dbenft8m7kps73ef1td0` at `e38d6b7`, retained on
`release/messenger-store-policies-20261025`. Its configured source branch,
`release/k135z-frontend-20260919`, points to
`1ecc4044eda9b9b7bb21ab4130c008d35d3d6926` and diverges from the live release.
A generic latest-branch deployment would include unrelated source differences.

The currently exposed Render deployment operation cannot select a commit, and
no authenticated Render CLI/API credential is configured in this workspace.
No deploy was triggered and the service configuration was not changed.

Publish the exact reviewed candidate through the
[existing Render service](https://dashboard.render.com/static/srv-d8ekf7t7vvec73dpar60)
using **Manual Deploy → Deploy a specific commit**, or an authorized API/CLI
connection that supports `commitId`. Confirm the date in the scoped COPY Box
coverage notice if publication occurs after November 4. Verify the deploy is
live and fetch all four public URLs before marking this gate complete.

## Mobile signing and account access

The user requires an alternative to Cloud Browser. No browser automation was
used in this continuation. Signing in on the user's own iPad does not provide
this session with that browser's authentication.

The known
[Codemagic project](https://codemagic.io/app/6a32198d2d0806059c3df062)
contains the source-configured Apple integration `Codemagic Korlix AI`. The
repository has manual candidate/upload workflows, but no automatic Codemagic
trigger or GitHub-to-Codemagic bridge. No callable Codemagic connection or local
API credential is available in this session.

Required account-side work remains:

1. Open [App Store Connect](https://appstoreconnect.apple.com/) and verify/create
   the COPY Box app record for `com.korlixdeveloper.copybox`.
2. Configure `KORLIX_COPYBOX_APP_STORE_PROFILE` with the existing authorized
   `KORLIX_APP_STORE_CERT`. No COPY Box numeric Apple app ID is recorded yet.
3. Configure the dedicated Android upload key
   `KORLIX_COPYBOX_ANDROID_UPLOAD_KEY` and verify/create the separate
   [Google Play Console](https://play.google.com/console/) app record.
4. Run and verify signed candidates. The iOS upload workflow uses the existing
   integration but does not automatically submit beta/App Store review or
   distribute the build to tester groups. The Android candidate workflow has no
   Play publisher integration.
5. Complete physical-device/live-account acceptance, reviewer access, store
   declarations, and submission using the existing release checklist.

The previous 140 passing automated tests and debug/simulator builds remain the
latest app validation. No application code changed here, and those tests were
not rerun. No signing identity was created, exported, rotated or substituted.
No signed store build, TestFlight upload, store submission or public mobile
release occurred in this continuation.
