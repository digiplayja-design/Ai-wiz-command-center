# Korlix AI — AI-generated content reporting correction

The owner's November 3, 2026 Play Console screenshots identify the main app,
Korlix AI (`com.korlixdeveloper.korlixai`), and an AI-Generated Content policy
warning: users lack an in-app way to report or flag offensive content. The
warning gives November 6, 2026 as the deadline. This is separate from the
Brain+Voice release.

Google's current requirement is an in-app reporting or flagging mechanism that
does not require the user to leave the app:
https://support.google.com/googleplay/android-developer/answer/13985936?hl=en

## Correction

The signed-in app navigator now has a visible **Report AI content** footer.
It stays available on pushed routes, including live voice, podcast playback,
virtual closet, Baby Blend, and live studio. Existing selected-result controls
remain available for text/history, generated images, logos, edited photos,
portrait previews, music, and image-to-video results.

The footer opens a form inside the app. The user selects a reason and describes
or quotes the content, including the feature used. A description is required
because this general entry point does not silently capture screen content,
audio, or conversation history. Reports use the existing authenticated private
support endpoint. Account changes invalidate an open report; a late response
cannot report success under a new account. Submission is not retried
automatically, and a success confirmation requires the existing durable receipt
format. The footer reserves layout space and hides during keyboard input.

## Reviewer path

1. Sign in using the existing review account.
2. Open any feature, such as Live Convo or The Pod and You.
3. Tap **Report AI content** at the bottom of the screen.
4. Select a reason and describe the feature and offensive AI content.
5. Tap **Submit report**. A successfully accepted report displays **Report
   received** and a reference. Closing the dialog returns to the same feature.

For generated images, logos, picture edits, portrait previews, music, or videos,
the selected-result reporting button can additionally include that particular
result's context. Cancellation does not send a report.

## Validation and release boundary

Source is based on the last recorded CRM app branch at
`37d629b7e24d4765e29c3276ac6a3ac1b027d578`, preserving the CRM and prior reporting
changes. Pull request: https://github.com/digiplayja-design/Ai-wiz-command-center/pull/41

Workflow: https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41633593786

The dedicated workflow analyzes the support implementation, tests the new
cross-route flow and existing reporting surfaces, and compiles the Android app.
Tests cover cancellation, required context, receipts, unconfirmed responses,
account changes during credential refresh, duplicate taps, and large text on a
narrow screen. Existing generated-media reporting tests are included.

The live `/api/report-output/health` endpoint returned HTTP 200, `ok: true`, and
`reportDeliveryVersion: v5`. This is a health check, not proof that a real report
or email was delivered. No real support report was sent during this work.

The workflow artifact is a **debug validation APK**, not a signed Google Play
release. Do not upload it or the source's iOS-derived build number to Play.
The next signed Android version code must be verified against current uploaded
bundles, and the existing main-app upload key must be reused.

The earlier conversation records a reporting fix in Android build 143, submitted
after rejected build 142. Its current Play review/production status has not been
reconfirmed. Browser automatic approval review blocked console access because
it reported the unexpected `google.play` origin instead of `play.google.com`.
No further attempt was made through that blocked browser route after the
owner's approval was also rejected. No new Google Play submission or approval
is claimed here; the current warning remains unresolved until the corrected
release is accepted by Google.
