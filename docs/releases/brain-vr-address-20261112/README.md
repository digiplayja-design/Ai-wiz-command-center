# Brain + Voice VR address follow-up — 2026-11-12

## Report and diagnosis

The owner confirmed that voice works in the delivered 1.0.2 (16) candidate, then reported that opening VR does not bring up the address view. The voice repair remains the base of this change.

The deployed Projection renderer was inactive. The prior production setup record explicitly configured the dedicated Maps JavaScript browser key with its verification switch set to `false`, and did not configure the separate `BRAIN_PROJECTION_GEOCODING_KEY`. The address resolver requires that private server key; the browser key cannot substitute for it. Current private environment values were not read during this investigation.

The native controller also cached its first capability response for the entire workspace, and its original-transcript parser did not recognize `open VR` or natural numbered-address commands beginning with `show me`. The `Live view?` chip was an availability question: its implementation returns that a live camera feed is not connected. It does not open an address view or provide real-time cameras.

## App correction

The candidate refreshes capabilities on a genuine closed-to-open transition, coalesces requests within that opening, and ignores late responses from a previous opening or disposed controller. It preserves the user's complete address text, requires a confirmed search result before changing the destination, and retains the existing renderer-origin validation and voice behavior.

The address control is labeled `Explore address in 3D`. The separate live-camera question is labeled `Live camera availability`. Missing map or address-search setup is distinguished from a failed availability check; an enabled capability is not described as proof that the renderer has loaded.

## Bounded production-origin map check

Existing evidence for the same dedicated browser key includes allowed-origin iPad imagery and camera controls, actual wrong-origin `RefererNotAllowedMapError`, and an API allowlist denial for a disallowed API. Those results supported a temporary production-origin check without claiming complete native acceptance.

- Target: `chee-chai-chee-backend`, service `srv-d8csvkkp3tds73emfikg` in the already selected workspace.
- Only `BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED` was temporarily merged as the string `true`; other environment settings were preserved.
- Render deployed release commit `a392eaac8a35fa2caa22aa4862c7e5ac7cb1771e` as `dep-dbqqoiei0phs73dff0ag`, live at **2026-11-12T12:09:25.195905Z**. Compared with the previous production commit, the intervening files were acceptance tooling, tests, and release documentation; the production Projection routes, core, renderer, entrypoint, and package files were unchanged.
- The actual production map document reached its unavailable state. The browser console reported `WebGL2 is not available on this browser`. This is an environment capability limitation, not evidence that the map key or the owner's device failed.
- Production-origin rendering and native rendering therefore remain **unverified**. No address lookup was attempted with a substitute credential.
- The switch was immediately restored to `false`. Deployment `dep-dbqqp8hsrm7s73dmovd0` reached live at **2026-11-12T12:10:57.512760Z**.
- Read-back: `/api/health` returned 200 and healthy; `/brain-projection/earth.html` returned 200, contained no browser key, and displayed `Geographic imagery is not connected yet.`

## Remaining setup

Google Cloud Console returned `Site Unavailable` in this workspace browser, including one retry at the console home page. The Render connector can manage the service, but it does not expose the service's outbound IP list or environment reads. No matching Google Cloud API-key-management connector was found. The owner must complete the provider-side credential setup or provide an appropriate authenticated control surface.

1. In the specific Render backend service, open **Connect → Outbound** and copy every displayed CIDR range. Do not use example ranges from documentation.
2. In the existing `korlix-ai` Google Cloud project, enable **Geocoding API** if it is not already enabled.
3. Create a separate key named **KORLIX Brain Address Search Server**, restricted to **Geocoding API** and the backend's actual outbound IP ranges. Keep the existing Maps JavaScript browser key separate.
4. Save that private key directly as `BRAIN_PROJECTION_GEOCODING_KEY` in the backend service's **Environment**, then choose **Save and deploy**. Do not put its value in chat, screenshots, source, or this record.
5. Verify a real address lookup, confirmation, and recorded 3D camera movement on the production origin and the native device. Review those results before completing the rollout. A successful map alone does not establish live camera support.

References: [Render outbound IPs](https://render.com/docs/outbound-ip-addresses), [Render environment settings](https://render.com/docs/configure-environment-variables), [Google Geocoding setup](https://developers.google.com/maps/documentation/geocoding/guides-v3/get-api-key), and [Google key restrictions](https://docs.cloud.google.com/api-keys/docs/add-restrictions-api-keys).

## Validation

- The focused Projection controller, voice, and navigation suites pass with Flutter 3.47.9 / Dart 3.13.7. They cover stale successes, stale failures and finalizers across close/reopen/dispose; request coalescing; refreshed disabled/enabled capabilities; full original-address preservation; and research/live-camera parsing boundaries.
- Full `flutter analyze --no-pub`, JavaScript syntax checks, and `git diff --check` pass.
- An independent review corrected counted-result and research-phrase parsing edge cases while preserving actual names such as Live Oak Road and Newport News.
- The existing shipped-UI browser harness includes new assertions for the address label, separate camera-availability label, service-check state and unavailable-service messaging. Local Chromium could not start because the runtime rejected its socket operation; GitHub CI is the execution path for those browser checks.

The candidate pull request records the final test count and CI result. This source correction has not been represented as a completed address-to-3D device test or as a new TestFlight delivery.
