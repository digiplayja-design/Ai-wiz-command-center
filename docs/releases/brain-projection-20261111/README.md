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

### Live wrong-origin denial observed

The new [wrong-origin test page](https://korlix-projection-denial-20261112.onrender.com/wrong-origin) was run in the connected cloud Chrome browser at `2026-11-12T02:54:24.252Z`. Its [unaltered sanitized report](cloud-browser-wrong-origin-v4-20261112.json) records `WRONG_ORIGIN_DENIAL_OBSERVED`, a renderer error, the sole provider code `RefererNotAllowedMapError`, and no current or previous steady scene. The SDK was 3.65.14a with the ordinary quarterly/async/origin loader contract and `strict-origin-when-cross-origin` policies. It recorded zero CSP violations. A [browser screenshot](cloud-browser-wrong-origin-v4-20261112.jpg) preserves the displayed result.

The origin-allowlist attestation was entered after comparing the new hostname with the owner's saved four-entry restriction screenshots reproduced as text above. Google Cloud settings were not changed. A separate HTTP comparison confirmed that the two isolated services serve the same public browser key; the value is not included in any evidence file. This is a real browser/provider denial observation from the cloud browser, distinct from the earlier iPad positive observation and from synthetic CI fixtures. It does not establish every possible unapproved origin or native WebView behavior, and it does not measure the iPad's no-referrer request headers.

Version 4 deployment provenance:

- Code commit: `d8ea91519e1fbb4557552ba4a462fd20f6e7f196`; tree: `2f5dd84a2654536424d82a20daa4d802aab671b5`.
- [PR 62](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/62) merged as `26d083c3987a45833f88f644c63e2049f63d4555`.
- [CI run 43144186610](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/43144186610), job `130938028126`, passed all 163 backend tests, the browser CSP enforcement fixture, and nine maps3d contract scenarios. Those fixtures forwarded no external provider requests. Artifact ID: `13910463373`.
- The approved acceptance service `srv-dbq3uo3rjlhs73b62qf0` deployed that commit as `dep-dbqik756e07s73fank4g`, reaching `live` at `2026-11-12T02:53:38.942199Z`.
- The new denial service `srv-dbqik4mc6qcc73fevdo0`, named `korlix-projection-denial-20261112`, uses Render's Free plan in Ohio, Node 22, and disabled auto-deploy. Its initial deploy `dep-dbqik4uc6qcc73fevf40` reached `live` at `2026-11-12T02:53:44.349537Z`. It runs only the isolated acceptance server; no database, private credential, production activation setting, or AI provider is configured.
- Post-deployment HTTP checks returned 200 for both health endpoints and relevant shell/frame/client resources. The no-referrer shell and frame send `no-referrer`; the wrong-origin shell and frame send `strict-origin-when-cross-origin`. The served client identifies acceptance version 4. Both health responses retain `productionActivation: false`.
- The production backend health remained healthy, and its public map document still contained no browser key. No production deploy or environment mutation occurred during this wrong-origin rollout.

The no-referrer runbook and offline preflight description now require actual header measurements and the observed result without assuming that header suppression on an approved origin must cause denial. Every offline verification status and the activation rule remain unchanged. The owner's failed v3 report remains preserved as supplied.

The allowed acceptance-origin rendering observation is complete and does not need to be repeated merely because `overallVerification` remains `NOT_ESTABLISHED`. That field intentionally does not certify the whole production rollout.

Unapproved-origin denial is now observed on the controlled host above, and disallowed-API rejection is recorded below. Remaining evidence under the [activation runbook](../../../backend/brain_projection/README.md) includes the approved production host, actual missing-referrer request behavior, and the applicable billing/usage review. Native iPhone/Android WebView rendering, closure/backgrounding, attribution links, and microphone continuity remain separate device checks. Private server-side geocoding configuration is independent of map rendering and the existing account-bound Directions entitlement.

### Initial API allowlist probes on November 12

Two read-only requests used the same existing public acceptance browser key, supplied only in the `X-Goog-Api-Key` header. Neither sent a Referer, Origin, OAuth credential, cookie or request body; redirects were rejected and no request was automatically retried. The key and raw provider response were not persisted.

| Request | Actual response | Interpretation |
| --- | --- | --- |
| [Geocoding v4, public Ferry Building coordinate](geocoding-api-restriction-20261112.json), completed `2026-11-12T03:07:03.886Z` | HTTP 403 / `PERMISSION_DENIED`; `SERVICE_DISABLED` for `geocoding-backend.googleapis.com` | That API is disabled for this request's project; the key's API restriction remains unproven. |
| [Public Identity Toolkit v1 configuration](identity-toolkit-api-restriction-20261112.json), completed `2026-11-12T03:09:58.620Z` | HTTP 403 / `PERMISSION_DENIED`; `API_KEY_HTTP_REFERRER_BLOCKED` for `identitytoolkit.googleapis.com` | Google denied the website-referrer check; this does not establish the separate API restriction. |

Both records remain `API_RESTRICTION_CHECK_INCONCLUSIVE`. No API was enabled and no key restriction or production setting changed. The isolated acceptance service now includes an explicit browser-only `/api-restriction` probe so the request can originate on the actual approved website with its natural browser referrer. Preparing that probe is not a passing live observation.

### Live disallowed-API denial observed

The [approved-origin browser check](https://korlix-projection-check-20261111.onrender.com/api-restriction) was run once in the connected cloud Chrome browser at `2026-11-12T03:21:55.651Z` and completed at `2026-11-12T03:21:55.935Z`. Its [unaltered sanitized report](cloud-browser-api-restriction-20261112.json) records `DISALLOWED_API_DENIAL_OBSERVED`: HTTP 403, error code 403, `PERMISSION_DENIED`, and the single Google `ErrorInfo` reason `API_KEY_SERVICE_BLOCKED` for `identitytoolkit.googleapis.com`, domain `googleapis.com`. The [displayed browser result](cloud-browser-api-restriction-20261112.jpg) preserves the observation.

The page made one GET fetch to Google's public project-configuration endpoint, using the existing public Maps browser key in `X-Goog-Api-Key`. It sent no OAuth credentials, cookies or request body, rejected redirects, and performed no automatic retries. The browser applied its normal `strict-origin-when-cross-origin` policy; the code did not override Referer or Origin. This page does not capture actual outgoing request headers, and its report explicitly retains `actualRefererHeader: NOT_CAPTURED_BY_PAGE`. Browser-generated CORS preflight is separate from the single fetch attempt.

This establishes a real API-allowlist denial for the tested Identity Toolkit endpoint from the approved website. It does not assert rejection for every Google API, validate a private Geocoding key, establish native WebView behavior, or enable production. The two earlier inconclusive raw-HTTP reports remain unchanged.

Probe provenance:

- Code commit: `30a52a45354e0e18df5dc79f5f1ef483933b31c1`; tree: `bd24b3845d1b3f08a2524ad681efffc4361a4914`.
- [PR 64](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/64) merged into the release branch as `255f9b02da312186ac6f31366ab0398c84ee8be7` with the same tree.
- [CI run 43146781882](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/43146781882), job `130946342559`, passed the required backend and browser regression checks; 24 focused acceptance tests also passed locally. These fixtures are separate from this live provider result.
- Acceptance Render deploy `dep-dbqiv38ae00c738hpf60` on service `srv-dbq3uo3rjlhs73b62qf0` reached `live` at `2026-11-12T03:16:56.866616Z`.
- Report SHA-256: `5620c4fd1a339022293339539157cbbb441d0537c3351341dd98d3084858d0ce`; screenshot SHA-256: `e1808a38b7a883716e06e1e9228bca799a4a6d9bf190b844d8fe351540917838`.

No Google settings, production environment variables or production deployment were changed during this check. `productionActivation` remains false and `overallVerification` remains `NOT_ESTABLISHED`.

### Bounded browser header audit

`backend/tools/capture_projection_live_headers.mjs` measures one fresh Chromium visit to the approved acceptance `/no-referrer` page and one explicit Load action. It records headers only from CDP `Network.requestWillBeSentExtraInfo`, reducing them immediately to Referer presence and a fixed allowlist of public origins. SDK bootstrap, authentication and 3D configuration endpoints are recognized by fixed path names; URL queries, credential values, cookies, arbitrary headers, request/response bodies, raw browser errors, HAR, tracing and video are not exported.

Redirect request IDs are correlated only when their extra-info expectations and event counts are complete. Missing or contradictory extra-info events, cached responses, unmatched recognized requests, truncation, capture failures and resource limits leave the header characterization inconclusive. The report preserves the observed scene state separately from the state after Close. It never changes the page's unchecked tester attestation, asserts overall verification, or modifies the production activation gate.

The browser uses a local HTTPS CONNECT boundary that allows only this acceptance hostname and Google resource domains on port 443. TLS stays end to end; the boundary does not inspect or rewrite HTTP headers or CORS preflights. QUIC is disabled for that boundary, and the transport difference is explicitly recorded. This is a Chromium diagnostic run, not a measurement of the owner's iPad or a substitute for native device acceptance.

The separate `brain-projection-live-headers.yml` workflow is limited to the dated test branch, with an explicit manual trigger and push paths restricted to its three audit files. Documentation/evidence commits do not trigger another provider run. It uses read-only repository permissions, pinned actions and Playwright 1.56.1, with bounded time, request, event and connection counts. The existing offline provider checks remain offline. Nineteen focused synthetic tests passed before any live execution; independent code review found no remaining blockers. A successful workflow alone is not a passing restriction result: review the sanitized report's actual observations.

### Native candidate audit

The native release branch `release/korlix-brain-store-20261101` was checked on November 12 and remains at `f2b339d89f910243c39b9920b1389a1e1b5290d6`, version `1.0.2+15`. Its app and workflow files match tested PR head `b3476487253701bf50a99344afd92b518e9151c7`. [PR 55](https://github.com/digiplayja-design/Ai-wiz-command-center/pull/55) records 164 passing Flutter tests, clean analysis, and successful signed Android and iOS candidates. The requested Pause/Resume/Stop, PDF Memory/Training review, Camera Ask, account-bound Directions and live-session repairs are in that candidate. This source/build evidence does not establish real-device microphone or speaker behavior.

The [Android debug APK artifact](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/42969561224/artifacts/13833401145) was confirmed unexpired through November 25. The GitHub iOS artifact is a simulator app. The separately [signed iOS candidate](https://codemagic.io/app/6a32198d2d0806059c3df062/build/6af405fe6f37641a0017a661) was built for App Store distribution; its current TestFlight availability was not verified. No store upload or tester notification occurred during this audit.

The existing `korlix-brain-ios-testflight` workflow was subsequently selected in Codemagic for the exact tested commit `b3476487253701bf50a99344afd92b518e9151c7`, with SSH/VNC disabled. The [prepared upload screenshot](brain-testflight-upload-prepared-20261112.jpg) records this selection. The final Start action was not executed; upload approval is pending. The selected workflow rebuilds and verifies the IPA, checks the exact `com.korlix.brain` Apple record, and chooses an available build number before uploading to App Store Connect. Its publishing configuration does not submit an App Store review or automatically assign a TestFlight group. This preparation is not evidence that a new build has been uploaded or is installable in TestFlight.

The installed native candidate accepts only the configured backend origin and exact `/brain-projection/earth.html` path with no query or fragment. It has no acceptance-host or ticket preview override. Its configuration is cached per workspace, so a future backend activation requires a full app restart to refresh the inactive response. A controlled native test before global activation requires an explicit test-build change; pointing the whole app's backend at the isolated acceptance server would break its authenticated API flow. No validation rule was relaxed and no pilot capability was added in this audit.

This result establishes interactive recorded 3D geography in the tested browser. It does not establish a live camera feed, headset/WebXR support, or production activation. Keep the production verification flag unset or false until the required production observations have been completed and reviewed.
