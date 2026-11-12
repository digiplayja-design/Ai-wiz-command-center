# Brain Projection live acceptance evidence

## Successful iPad observation

The project owner supplied [this version 3 report](ipad-acceptance-v3-20261112.json) from the isolated HTTPS acceptance service. Its session began at `2026-11-12T00:51:12.919Z` (November 11 at 7:51 PM US Eastern). The report is preserved as supplied, including `productionActivation: false`, `overallVerification: NOT_ESTABLISHED`, and `closedAt: null`.

The report records `POSITIVE_OBSERVATION_COMPLETE` with a ready, steady Google Maps JavaScript 3.65.14a renderer. It contains 17 requested camera commands covering all six command types and 14 animation-end events. Animation counts are diagnostic; this record does not assert that every command produced an animation-end event. It records zero CSP violations, no map/loader/page errors, and no provider error codes. The owner confirmed geographic imagery and working controls, plus visible Google attribution and usable legal links including a narrow viewport.

This is user-supplied device evidence, not an independently instrumented or cryptographically signed device capture. The earlier screenshots identify an iPad browser; this JSON does not contain a user agent or native app build identifier. No credential value, authorization header, or raw provider request is included.

## Release provenance

- Acceptance origin: `https://korlix-projection-check-20261111.onrender.com`.
- Acceptance service: `srv-dbq3uo3rjlhs73b62qf0`; deployed version 3 commit: `56c4b97457e9ed86be98f71f5a61a61d3b3fa8c5`; Render deploy: `dep-dbqemvuc6qcc73f3pivg`.
- [PR 59](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/59) merged the tested map style compatibility change into `release/signup-plan-intent-20261021` as `021dd8bd04c906075bb08157a77d36c3d588b878`.
- The tested commit and release merge have the same tree: `14971a9ef840a07b4cd33c2d3cc85783783d0bc5`.
- [CI run 43111411773](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/43111411773) passed the backend regressions and browser contract/CSP fixtures for the tested commit. Those synthetic fixtures are separate from the owner's real Google rendering observation.

The service deployment identifies the code being served; the copied report itself does not carry a commit SHA. This documentation change does not modify the application, environment, credentials, or activation flag.

## Established scope and remaining work

The allowed acceptance-origin rendering observation is complete and does not need to be repeated merely because `overallVerification` remains `NOT_ESTABLISHED`. That field intentionally does not certify the whole production rollout.

The production origin and key restrictions still require their own evidence under the [activation runbook](../../../backend/brain_projection/README.md): the approved production host, disallowed-origin and missing-referrer behavior, and the API allowlist. Native iPhone/Android WebView rendering, closure/backgrounding, attribution links, and microphone continuity remain separate device checks. Private server-side geocoding configuration is independent of map rendering and the existing account-bound Directions entitlement.

This result establishes interactive recorded 3D geography in the tested browser. It does not establish a live camera feed, headset/WebXR support, or production activation. Keep the production verification flag unset or false until the required production observations have been completed and reviewed.
