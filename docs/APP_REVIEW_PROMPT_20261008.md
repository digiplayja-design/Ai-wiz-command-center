# Active-use review requests and private feedback — October 8, 2026

This change adds a review opportunity after three cumulative hours of active
signed-in use and a separate private feedback route. Review eligibility does
not depend on satisfaction, feedback topic, complaint history or a predicted
rating. Positive and negative feedback are both accepted. There is no reward,
feature restriction or requirement to review the app.

## Timing and interruption controls

- Accumulate active use separately for each signed-in account on the current
  browser or device. Persist only the local duration and automatic-request
  state through SharedPreferences; do not upload this counter or add a new
  analytics event stream. Input content is not recorded for timing.
- Use a two-minute inactivity cutoff. Exclude hidden, background, locked and
  in-app screensaver time; do not count an overnight/open-tab clock jump as
  activity. Signed-out time does not qualify.
- Reaching three hours makes the account eligible; it does not interrupt the
  current action. Wait for a safe home-screen opportunity after tools, calls,
  forms and other active flows have finished.
- Make at most one automatic invitation/request per account on that local
  installation. Other browsers/devices have independent counters; clearing
  local storage or reinstalling can reset that state. This is not a global
  account-wide frequency guarantee.

## Platform behavior

- Supported native iOS/Android builds use the official store review API
  directly, with no custom love/hate, star prediction or rating screen before
  it. The store owns its interface, limits, eligibility and availability.
  Request completion is not evidence that the card appeared, a review was
  submitted or a particular rating was selected.
- Web presents a neutral invitation. Private feedback is available to all
  signed-in users; external review links may appear only for verified KORLIX
  store listings. A missing or unpublished listing must not become a guessed
  URL, a link to a different app, or a promise of review availability.
- Private feedback remains accessible separately from the automatic review
  timing. Its existence and content do not alter store-review eligibility.
- A web deployment does not publish the native review integration to TestFlight,
  App Store or Google Play. Native signed builds, store availability and device
  checks are separate release steps.

## Private feedback handling

The form reuses the existing authenticated `/api/report-output` support queue
with `contentType=app_feedback` and `appArea=app_feedback`. It accepts free text
and an optional topic: General feedback, Something I love, Problem or bug, Idea
or suggestion, or Privacy or safety concern. There is no numeric score.
General feedback is the default topic; a message is required and limited to
2,000 characters.

Feedback uses the backend's authenticated identity and existing diagnostic
metadata. `prompt` and `outputSummary` are empty; the app does not automatically
attach a conversation or screenshot to this form. Existing restricted support
access and retention apply. No feedback schema or new analytics store is
required. Submitting feedback does not post to either app store.

The form must explain its private support destination, discourage unnecessary
sensitive data, show success only after a confirmed accepted submission, and
retain an editable draft after a failed attempt. A sign-in/account change clears
the draft rather than handing one account's text to another. An authentication
failure requires sign-in again; the form does not fall back to a public post or
retry automatically. Endpoint behavior and authorization checks must be
verified before publication.

## Policy source updates

- `website/privacy-policy.html#app-feedback-and-store-reviews`: local active-use
  counter and reset behavior, voluntary private support records, and external
  store review handling.
- `website/terms.html#feedback-and-store-reviews`: voluntary participation,
  independent public-review choice, and store-controlled availability.

The pages retain their October 8, 2026 date and their existing Social, AI,
account-deletion and other disclosures. These source edits do not by themselves
change app-store privacy declarations or establish that a release is live.

## Official platform requirements checked October 8, 2026

- [Apple App Review Guidelines, 5.6.1](https://developer.apple.com/app-store/review/guidelines/#app-store-reviews)
  requires Apple's review API and disallows custom native review prompts.
- [Apple App Review Guidelines, 5.6.3](https://developer.apple.com/app-store/review/guidelines/#discovery-fraud)
  prohibits manipulation of reviews and other discovery mechanisms.
- [Google Play In-App Reviews: when to request, design and quotas](https://developer.android.com/guide/playcore/in-app-review)
  prohibits opinion or predicted-rating questions before or during its review
  card. The store can suppress display because of its quota and availability.
- [Google Play review completion behavior](https://developer.android.com/guide/playcore/in-app-review/kotlin-java#launch_the_in-app_review_flow)
  does not reveal whether a dialog appeared or a review was submitted. Continue
  normal app use after completion or failure; do not infer success.
- [Google Play testing requirements](https://developer.android.com/guide/playcore/in-app-review/test)
  distinguish real store distribution, internal testing and internal app
  sharing; a local/mock test cannot prove public review submission.

## Validation and release evidence

Implementation, automated checks, publication and live verification are separate
steps. Record their results here after they finish. No deployment, native-store
availability, real-device prompt display or review submission is certified by
this initial document.

Both edited HTML pages passed parsing, unique-anchor, local-link and
October 8 date checks. The existing third-party AI disclosure marker was
preserved, and `git diff --check` passed. These are document consistency checks,
not runtime or release verification.

### Source verification

The combined timing, host, store bridge, invitation, feedback, screensaver and
authentication suite passed 75 tests with one pre-existing opt-in screenshot
render test skipped. Targeted analysis of the new review modules, tests and
modified screensaver files found no issues. Main-app analysis found no errors;
its existing unused-code/deprecation warnings remain. No Dart dependency
versions changed. Android adds the official Play Review library 2.0.2.

Independent review caught and corrected delayed store-link navigation after
dismissal and a sign-in change before the web dialog's first frame. Regression
checks cover both. The Render release gate includes the review and feedback
checks. The production support endpoint contract was inspected; no real
feedback or public store review was sent during testing.

Google Play's public Korlix AI listing was verified on October 8, 2026:
https://play.google.com/store/apps/details?id=com.korlixdeveloper.korlixai
No verified Apple numeric listing ID was found, so no Apple browser link is
shown. Native StoreKit identifies the installed app and does not need that ID.

Local timing is conservative and best effort. Simultaneous browser tabs do
not share an atomic prompt claim; the persistent state prevents normal
repeat prompts, not a strict cross-tab or cross-device frequency guarantee.
Android/iOS native compilation and actual store dialog presentation are not
verified by these Flutter tests. Signed native builds and store/device tests
remain necessary. Public web deployment evidence is recorded after release.

### Published web release

Frontend commit `7b48b6d9b52bac534b2be8d6296b0b7553d2c7d7` was deployed by
Render release `dep-db417449v7es738nmd00`, which reached `live` at
2026-10-08 22:08:14 UTC (6:08:14 PM Eastern). The release gate passed 288 tests,
with the existing opt-in screenshot-render test skipped. The final invitation
suite also independently passed all 11 tests after the account-race fix.

The canonical `/app/` and compiled `/app/main.dart.js` returned HTTP 200; the
live bundle contains the invitation, Google Play action, Settings feedback
entry and local-counter namespace. Both updated policy pages returned 200
with their new disclosures from the Render hostname. The canonical terms
page also contained the new section. The canonical privacy URL initially
returned a previous CDN copy (the observed shared-cache lifetime is 300
seconds); a fresh release-query URL and the Render hostname returned the
updated policy. No additional deployment is needed for cache expiration.

No backend deployment or database migration was required. Real feedback was
not submitted and a store review was not posted during verification. The
native integrations are committed source only: Android/iOS compilation,
signed distribution and actual store-controlled review presentation remain
unverified and must accompany the next native release.
