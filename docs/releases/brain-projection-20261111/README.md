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

## Production configuration prepared on November 11

The owner supplied Google Cloud screenshots showing the `KORLIX Brain Projection Web` key restricted to **Maps JavaScript API only** and **Websites**, then confirmed the corrected website entries were saved:

- `https://chee-chai-chee-backend.onrender.com`
- `https://chee-chai-chee-backend.onrender.com/*`
- `https://korlix-projection-check-20261111.onrender.com`
- `https://korlix-projection-check-20261111.onrender.com/*`

The owner also confirmed there were no `BRAIN_PROJECTION` variables on production service `srv-d8csvkkp3tds73emfikg`. The existing public browser key served by the successful acceptance environment was transferred into `BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY` on that production service. The same Maps JavaScript browser key is used for the two exact first-party hosts in this rollout; a private server geocoding credential remains separate. No credential value is stored in this record.

`BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED` was explicitly set to the string `false`. These two settings were merged into the service environment, preserving unrelated settings. No canonical-origin variable was added: the application can use Render's documented `RENDER_EXTERNAL_URL` when no explicit override is present. No Geocoding key was configured.

The environment update initiated Render deployment `dep-dbqi7kijnfac738p5pt0` at release commit `1b5fb96a8ed9296fbb0b6faa4ceaa412fa89adfb`, which reached `live` at `2026-11-12T02:27:02.029Z` (November 11 at 9:27 PM US Eastern). Its application code is unchanged from the tested CSP fix; the intervening release commit adds only the successful acceptance evidence.

Post-deployment HTTP checks returned 200 for `/api/health` and `/brain-projection/earth.html`. The health response reported a healthy backend. The map document retained an empty browser-key field, the inactive message, the tested map-style CSP allowance, and `strict-origin-when-cross-origin` referrer policy.

This prepares production configuration without asserting provider verification or activating the public map. The screenshots establish the owner's saved restriction settings, not the results of denied-request or production-device tests.

## Established scope and remaining work

### No-referrer observation and test limitation

The owner's next [version 3 report](ipad-no-referrer-v3-20261112.json) began at `2026-11-12T02:33:05.238Z` (November 11 at 9:33 PM US Eastern). It records a steady scene with no captured errors or CSP violations on the same approved acceptance origin, even though the frame and initial SDK loader were configured with `no-referrer`. The report retains `NEGATIVE_CHECK_FAILED_SCENE_RENDERED`; it is not changed into a passing restriction check. The unchecked network-header attestation means those headers were not verified, not that they were present or absent.

Inspection of the live HTTP responses confirmed an additional harness gap: version 3's outer `/no-referrer` page still sent `strict-origin-when-cross-origin`, although its inner frame sent `no-referrer`. The iframe navigation had no explicit policy. Version 4 applies `no-referrer` consistently to that outer page and iframe navigation. This corrects incoming navigation-referrer handling; it does not guarantee a Google authorization denial.

The [SDK source audit](no-referrer-source-review-20261112.md) found an explicit page-origin field in the versioned Maps JavaScript 3.65.14a authentication and 3D-configuration request builders. Removing the HTTP `Referer` header does not remove `location.origin` or that request field. Therefore rendering on an already approved origin is insufficient evidence that website restrictions are broken. This source finding does not establish the iPad's actual request bytes or Google's server-side decision.

Version 4 provides a separate wrong-origin scenario for a controlled HTTPS host absent from the saved key allowlist. Its denial observation requires a specific `RefererNotAllowedMapError`, no steady scene, the normal loader policies, and explicit confirmation that the tested origin is unapproved. It cannot convert a graphics, billing, quota, loader, or generic error into proof of a website restriction. Neither scenario activates production.

The allowed acceptance-origin rendering observation is complete and does not need to be repeated merely because `overallVerification` remains `NOT_ESTABLISHED`. That field intentionally does not certify the whole production rollout.

The production origin and key restrictions still require their own evidence under the [activation runbook](../../../backend/brain_projection/README.md): the approved production host, disallowed-origin and missing-referrer behavior, and the API allowlist. Native iPhone/Android WebView rendering, closure/backgrounding, attribution links, and microphone continuity remain separate device checks. Private server-side geocoding configuration is independent of map rendering and the existing account-bound Directions entitlement.

This result establishes interactive recorded 3D geography in the tested browser. It does not establish a live camera feed, headset/WebXR support, or production activation. Keep the production verification flag unset or false until the required production observations have been completed and reviewed.
