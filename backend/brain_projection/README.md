# Brain+Voice Projection backend

Optional map and public-place research services for the existing Brain+Voice app. The original native voice session, account authentication, memories, training, purchases and home page remain separate. Closing the map destroys its renderer; it does not end a voice session.

## Configuration

The hosted view now uses **Google Maps JavaScript API, `maps3d`, `Map3DElement`, quarterly channel**. This is Google's supported website-key path for photorealistic 3D. The earlier direct Map Tiles/Cesium candidate is retired; its key and activation flag are intentionally ignored. The original app, account, voice and research contracts stay the same.

| Variable | Purpose | Exposure |
| --- | --- | --- |
| `BRAIN_PROJECTION_GEOCODING_KEY` | Google Geocoding API server key, restricted to that API and the backend's actual outbound IPs/CIDRs. | Backend only. Never included in API responses, renderer HTML, logs or frame messages. |
| `BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY` | Separate Google Maps JavaScript API key, restricted to the exact first-party HTTPS renderer website and Maps JavaScript API. | Public only after the verification switch is enabled. Reusing the private geocoding key is rejected. |
| `BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED` | Exact string `true` after real provider/browser restriction checks pass. Default is inactive. | Deployment assertion only; a configuration value is not evidence that Google accepted the connection. |
| `KORLIX_PUBLIC_BACKEND_URL` or existing `RENDER_EXTERNAL_URL` | Canonical first-party HTTPS origin with no path, credentials, query or fragment. The first variable takes precedence. | Public renderer origin; must match the installed native app's API origin. |
| Existing `OPENAI_API_KEY` | Existing Responses API web search. | Backend only. |

`BRAIN_PROJECTION_MAP_BROWSER_KEY` and `BRAIN_PROJECTION_MAP_BROWSER_RESTRICTIONS_VERIFIED` belong to the retired Tiles candidate and never enable this renderer. There is no Cesium dependency, ion token, Map Tiles key, or server tile proxy in the new map connection.

All capabilities default to unavailable unless configured. Invalid/restricted keys, provider failures, unsupported coverage or WebGL failures produce honest unavailable states. The automated browser tests use labeled SDK contract fixtures and block every external request; they do not prove that actual Google imagery has rendered.

### Activation sequence

1. Use an owner-confirmed Google Cloud project. Enable **Maps JavaScript API** and **Geocoding API**, and review its existing billing, usage and quotas. Do not repurpose the Play Billing service account or a different application's routing key.
2. Create separate credentials with the restrictions in the table. For the current native API origin, configure both browser website entries: `https://chee-chai-chee-backend.onrender.com` and `https://chee-chai-chee-backend.onrender.com/*`, never `*.onrender.com`. The loader's `auth_referrer_policy=origin` requires the literal origin without a trailing slash or path; [Google's browser restriction guidance](https://docs.cloud.google.com/api-keys/docs/add-restrictions-api-keys) recommends the exact-host pair, and the [Maps loader documentation](https://developers.google.com/maps/documentation/javascript/load-maps-js-api) explains the origin requirement. Restrict the browser key's API allowlist to Maps JavaScript API only, independently of which APIs are enabled in the project. The server key uses Render's actual outbound IP ranges. Neither key is entered in chat or committed to Git. In the current rollout, the [isolated acceptance service](acceptance/README.md) uses the same dedicated public Maps JavaScript key as production, with owner-saved exact-host entries for the production and approved acceptance hosts. The controlled wrong-origin host must remain absent from that key's website allowlist. The private server-side Geocoding key remains separate, and acceptance tests never activate production.
3. Set the canonical backend origin and keys through the service's secure environment settings. Keep `BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED` unset while preparing acceptance. The default native API origin is `https://chee-chai-chee-backend.onrender.com`; a custom native build must use the same explicit origin as the renderer configuration.
4. Run the offline configuration preflight from the repository root:

   ```sh
   node backend/tools/check_projection_provider.mjs
   ```

   It never contacts Google, exposes keys, changes settings, or asserts live verification. Exit 1 means structurally invalid/incomplete configuration; exit 2 means the configuration is structurally ready but external verification was not performed. The obsolete `--allow-provider-check` switch is rejected. A loader HTTP 200 or a generic provider 403 is not proof of restrictions.
5. Use an authorized non-production first-party HTTPS acceptance environment to test the actual SDK with the candidate key. Verify a complete 3D scene, correct attribution and camera controls from the allowed origin. Verify that a controlled HTTPS origin absent from the key's website allowlist produces `RefererNotAllowedMapError` without ever reaching a steady scene. Separately characterize missing-referrer behavior by capturing the actual relevant Google SDK and authorization request headers and recording the tested origin, SDK version, current website restrictions, and observed result. A configured `no-referrer` policy alone does not establish header omission. The SDK can also supply the page origin in authorization data, so a scene rendered on an approved origin does not establish failed website restrictions or satisfy the wrong-origin denial requirement. Confirm the Maps JavaScript-only API allowlist and denial when that key is used for another API. Never substitute an unrestricted key to make a test pass.

   The recorded version 3 iPad report remains `NEGATIVE_CHECK_FAILED_SCENE_RENDERED`; its unchecked header attestation leaves actual header omission unverified.

6. Verify the actual renderer in Android and iPhone WebViews, including the expected referrer, microphone continuity, lifecycle handling, provider links, narrow-screen credit visibility and source/save behavior. After successful evidence and a review of the applicable Google terms, enable the production verification switch and release the matching app/API pair.

A configured switch is not permission to enable paid Google billing. Real Google acceptance and any account/billing changes require the authorized project owner's setup. Google Cloud console access was unavailable in this workspace during preparation; no production provider values or billing were changed.

### Usage and cost boundary

Maps JavaScript 3D map loads use Google's **Immersive Maps** SKU; geocoding has its own usage charges. This implementation does not claim they are free. Review current [Maps JavaScript billing](https://developers.google.com/maps/documentation/javascript/usage-and-billing) and the project's applicable price list. Set conservative available request quotas and usage alerts before a pilot; budget notifications do not themselves stop spending.

The public map-only document can be opened outside an authenticated research request. Authentication and per-account budgets on the address/research API do not cap direct map loads. Keep the project-level cost controls and verification gate in place. Review the existing public Terms/Privacy links against [Google's Maps JavaScript requirements](https://developers.google.com/maps/documentation/javascript/policies) before activation.

## Authenticated API

Every `/api/brain-projection/*` endpoint calls the existing `requireUser(req)` boundary, preserving disabled-account and revoked-device behavior. Public responses are `Cache-Control: no-store`. Projection JSON has an 8 KiB limit before the application's general parser, with additional field, type and coordinate bounds.

### `GET /api/brain-projection/config`

```json
{
  "version": "projection-v1",
  "mapAvailable": false,
  "geocodingAvailable": false,
  "answersAvailable": false,
  "rendererUrl": null,
  "answerCredits": 4,
  "answerCostLabel": "4 credits per sourced answer"
}
```

`rendererUrl` becomes the canonical backend origin plus `/brain-projection/earth.html` only when a separate Maps JavaScript browser key, verified-restrictions switch and HTTPS origin are configured. Private keys never appear here. The app displays the research cost before a sourced question is submitted.

### `POST /api/brain-projection/resolve`

Body: `{ "query": "place or address" }` (2–300 characters).

Returns `candidates`, `requiresConfirmation: true` and a short `answer`. Each candidate contains `id`, `label`, `address`, `latitude`, `longitude`, `userQuery`, `provider: "google"` and `partialMatch`. At most five candidates are returned. Every candidate requires explicit user confirmation, including a single apparently exact result. Google partial matches and mismatched street numbers/US ZIPs get an additional warning. No result causes no invented coordinates or fallback city. The inconsistent example “14360 Jupiter Rd, Brooklyn, 10012” must be corrected or explicitly matched to a fully displayed provider result before navigation.

The native app keeps provider-returned address labels in the visual candidate/selected-place cards. Its spoken lookup and selection replies use generic confirmation text, rather than converting geocoder content into speech. Place research remains independently sourced.

Requests use one fixed Google HTTPS endpoint, disallow redirects, have a 12-second timeout and cap upstream body size. A URL supplied as a search query remains address text; it cannot change the destination of the server's fetch. There is no arbitrary URL fetch endpoint or geocoding result cache.

### `POST /api/brain-projection/answer`

Body: `{ "question": "question", "place": { ...confirmed candidate... } }`.

Question length is 2–1,200 characters. A normal research question requires the validated place fields above. Returns `text`, `sources: [{title,url,date?}]`, `scope`, `date`, and `creditsUsed`. Factual answers use numbered `[1]` citations matching the ordered source links; the app must display the links prominently beside the answer. Dates describe the source's reporting period, not an invented map capture date.

Research uses the existing Astra max text policy and required Responses web search, with up to four search tool calls. It receives only the question and selected public-place text, not account memories, native bridge credentials, map pixels or audio. All input and retrieved text is explicitly untrusted. Search must complete, source URLs must match actual retrieved/cited evidence, and answers must include a geographic scope. Crime, population and current-officeholder answers also require a source period/as-of date. Crime instructions distinguish counts from rates, name the area/category/period and prohibit invented building safety scores. Missing evidence produces an explicit unverified answer.

Live camera/view requests and imagery capture-date requests are answered locally without a model: live feeds are not connected; map imagery is recorded; capture date is not supplied by this 3D renderer. These availability replies do not require a selected address.

### Existing allowance behavior

`server.js` derives the research charge from the existing `calculateCredits({liveSearchNeeded: true, fileRequested: false})` path. At this baseline it is **4 existing credits and one existing `live_search_generations` entry per successful sourced answer**. Account profile/usage checks run before inference. The existing usage counter is updated after a valid sourced result; there is no new product, price, entitlement, purchase flow or database migration.

Brain voice minutes and typed research credits are separate existing counters. Projection does not call the voice reservation, turn, billing or end-session endpoints. If voice is already connected, its normal duration meter continues while a separate place-research request runs. Map/camera commands, direct availability answers, no-source answers and errors do not consume research credits.

One research request per account can be active in this process, with eight total in-flight requests. Identical concurrent requests are coalesced. An identical successful/no-source result can be replayed for 30 seconds for the same verified account without another charge; different accounts cannot access it. This is an in-memory retry safeguard, not a new durable billing system. Existing shared usage-counter concurrency semantics are preserved. Authenticated abuse budgets additionally cap research attempts at six/minute and geocoding at twenty/minute.

## Hosted renderer and app isolation

The public `/brain-projection/earth.html` document contains map-only UI. The bundled Projection shell embeds this first-party HTTPS page so Google receives a valid website referrer. No bearer token, refresh token, account data or native bridge nonce is sent to the map frame. The existing home does not gain map network access.

The renderer uses the supported **quarterly** Maps JavaScript channel and only the documented core `maps3d` APIs: `Map3DElement`, `SATELLITE` mode, camera fly/stop controls and lifecycle events. It does not embed the Google Earth website, implement Street View, or rely on alpha/beta features. Map imagery, logos, terms links and provider credits remain owned by the Google component. Application headings, buttons, selected-place cards and captions are placed outside the entire map rectangle; the active voice dock has its own scroll boundary. The app never inspects a provider's private DOM, copies its credit HTML, or estimates a credit-strip height.

Each HTML response has a fresh cryptographic nonce shared by its CSP, local module and style seed. Google inherits script/style nonces following its [strict CSP guidance](https://developers.google.com/maps/documentation/javascript/content-security-policy). There is no inline-script allowance or arbitrary HTTPS script allowlist. Google's required string evaluation and documented resource domains are limited to this isolated map document; camera, microphone, geolocation and payment permissions remain disabled. No researched HTML is inserted into the renderer.

The local module installs `gm_authFailure` and its SDK callback before inserting the Google loader. It requests the quarterly `maps3d` library with an origin-only referrer policy. Loading the script or constructing the custom element is insufficient for readiness: only the documented `gmp-steadychange` event with `isSteady === true` enables ready status. The older `gmp-steadystate` example is not used. A 30-second deadline covers SDK loading and first scene completion; authentication, initialization and import errors produce sanitized failures. Disposal stops camera animation, removes listeners and the map element, and prevents late callbacks from restoring readiness. Removing the containing iframe closes the document and its provider resources.

### Camera and status protocol

The parent sends `korlix-projection-camera` with an increasing nonnegative safe integer sequence and one of `flyTo`, `closer`, `farther`, `left`, `right`, or `reset`. Optional camera bounds remain latitude ±90, longitude ±180, legacy `height` 25–40,000,000 meters, heading ±360 and pitch −90..0. Selected-place data contains only public `id`, `label`, `latitude` and `longitude`.

`flyTo` and selected-place reset aim at the building as the camera center. The legacy height field is interpreted as an approximate vertical standoff hint and converted into a bounded range using the tilt; it is not a surveyed altitude. The target uses terrain-relative altitude. Relative zoom and orbit preserve the component's current center so a user's touch exploration is respected.

Commands must come from the actual parent window, with the opaque bundled origin `null` or the renderer's own HTTPS origin. Unsupported operations and malformed/stale messages are discarded. No URL, account context, executable code or native command channel is accepted.

The renderer returns only:

```js
{type: 'korlix-projection-status', status: 'loading' /* ready | error */, message: 'Public map status'}
```

The parent verifies both origin and source. The retired `korlix-projection-credits` height message is ignored; protecting the full provider surface replaces credit-height reservation. The SDK and iframe never receive access to account credentials or the native bridge.

Research remains independent public-source research, not image interpretation. The app does not export or persist map screenshots or tiles. Geocoder results stay in transient Projection state; a question sends the selected public-place fields to the authenticated research endpoint, which includes them as context for independent web research. Saved notes retain only the user's own query/note and the exempt provider place ID, not copied geocoder address details.

## Verification

Run from `backend/`:

```sh
node --test test/brain_projection.test.mjs test/brain_projection_renderer.test.mjs test/brain_projection_provider_check.test.mjs test/brain_voice.test.mjs test/brain_live.test.mjs test/brain_billing.test.mjs test/brain_billing_meter_fallback.test.mjs test/auth_session_security.test.mjs
```

The Projection suites cover input/output bounds, exact/partial/no-result address handling, fixed provider URL and redirects, private-key separation and activation gating, required web-search evidence, malicious source URLs, missing reporting scope/date, existing auth status propagation, quota and retry behavior, free unavailable answers, per-response nonce/CSP, retired-key rejection, parent-message validation, building-centered camera actions, genuine steady-state readiness and renderer disposal/failure races. Provider fixtures are explicit test-only data. The shared voice-meter fallback from release commit `65a660fcfcbaa3112584d353408aac6d6c7d4b12` is included and its regression suite runs alongside Projection.

`tools/check_projection_renderer.mjs` and the dedicated `brain-projection-api.yml` workflow exercise production renderer HTML, headers, SDK-loader parameters and lifecycle behavior in Chromium using clearly labeled public-API contract fixtures. Every external request is intercepted. Reports explicitly state that actual Google provider rendering was not verified. These fixtures are not substitutes for the first authorized Google SDK/WebGL acceptance run.

Before release with actual credentials, complete the activation sequence above and a small authorized sourced-query smoke test. Confirm native Back/backgrounding, account changes, memory saving, microphone continuity, provider links, Google coverage and device GPU performance. This source change alone is not a deployed or provider-connected release.

## Official implementation references

- [Google Maps JavaScript 3D overview](https://developers.google.com/maps/documentation/javascript/3d/overview)
- [Quarterly Map3DElement reference](https://developers.google.com/maps/documentation/javascript/reference/3.65/3d-map)
- [Google Maps key restriction guidance](https://developers.google.com/maps/api-security-best-practices)
- [Maps JavaScript CSP](https://developers.google.com/maps/documentation/javascript/content-security-policy)
- [Maps JavaScript attribution and policies](https://developers.google.com/maps/documentation/javascript/policies)
- [Maps JavaScript usage and billing](https://developers.google.com/maps/documentation/javascript/usage-and-billing)
- [Google Geocoding request/response](https://developers.google.com/maps/documentation/geocoding/requests-geocoding)
- [OpenAI Responses web search and source evidence](https://developers.openai.com/api/docs/guides/tools-web-search)
