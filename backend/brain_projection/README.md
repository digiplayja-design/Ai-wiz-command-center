# Brain+Voice Projection backend

Optional map and public-place research services for the existing Brain+Voice app. The original native voice session, account authentication, memories, training, purchases and home page remain separate. Closing the map destroys its renderer; it does not end a voice session.

## Configuration

All capabilities default to unavailable unless their dependencies are configured. This change does not set production variables, deploy a service, create a Google project, enable billing, or create a subscription.

| Variable | Purpose | Exposure |
| --- | --- | --- |
| `BRAIN_PROJECTION_GEOCODING_KEY` | Google Geocoding API server key, restricted to that API and the backend's actual outbound IPs/CIDRs. | Backend only. Never included in API responses, renderer HTML, logs or iframe messages. |
| `BRAIN_PROJECTION_MAP_BROWSER_KEY` | Separate candidate Google Map Tiles API browser key. Its application and API restrictions must pass the activation checks below. | Public only after the verification switch is enabled. It must never be an unrestricted or server key. Reusing the geocoding key is rejected. |
| `BRAIN_PROJECTION_MAP_BROWSER_RESTRICTIONS_VERIFIED` | Set to the exact string `true` only after the configured provider accepts the authorized renderer and rejects unauthorized use. Default is inactive. | Deployment assertion; never a substitute for testing the actual provider restrictions. Without it the key is withheld and the map remains unavailable. |
| `KORLIX_PUBLIC_BACKEND_URL` or existing `RENDER_EXTERNAL_URL` | Canonical existing first-party HTTPS origin, with no path, credentials, query or fragment. | Public renderer URL. The first variable takes precedence. |
| Existing `OPENAI_API_KEY` | Existing Responses API web search. | Backend only. |

Source inspection found no existing Maps/geocoding key configuration to reuse, so the two explicit key names above were introduced. The existing OpenAI configuration is reused. No Cesium ion token or account is needed for direct Google tiles.

Configuration indicates a provider is configured, not that a paid live request has passed. Invalid keys, domain restrictions, quotas, unsupported coverage, unavailable WebGL and provider failures produce unavailable/error states. Automated checks use provider fixtures, including a generated test tile with the actual pinned SDK; they make no paid Google or OpenAI requests.

Google Map Tiles and Geocoding require their own enabled APIs and applicable Google Cloud billing/quotas. This implementation does not claim these services are free. Set appropriate Google project quotas before connecting the keys. Review the project's applicable Google Maps terms, including any EEA-specific behavior.

### Provider activation gate

The [Google Maps FAQ](https://developers.google.com/maps/faq#keysystem) and [API security guidance](https://developers.google.com/maps/api-security-best-practices) currently list Map Tiles among APIs using **IP address restrictions**. A direct browser key restricted to the renderer website is therefore an unverified integration candidate, not a guaranteed supported configuration. Keep the verification switch unset until real provider tests establish all of the following:

1. The allowed first-party HTTPS renderer can load actual 3D content with the candidate key restricted to Map Tiles API only.
2. Requests with an unrelated website referrer and with no referrer are rejected.
3. The same key cannot call a different Google API.
4. Actual Android and iOS WebViews preserve the allowed referrer and render the imagery with all required attributions.

If these checks fail, leave browser activation disabled and use a supported browser map integration or design an authenticated, narrowly scoped server proxy with an IP-restricted Tiles key. Do not make the browser key unrestricted or expose an IP-restricted server credential as a workaround.

The current mobile client's default API origin is `https://chee-chai-chee-backend.onrender.com`. Set `KORLIX_PUBLIC_BACKEND_URL` to the exact origin used by the installed app, including any intentional custom-domain override. The native client rejects a renderer on any different origin.

The renderer route is public and begins a root tileset request whenever activated; account authentication and account rate limits on research/geocoding do not limit direct renderer opens. Before a pilot, set and verify conservative Google request quotas and check existing usage on the billing account. Budget notifications alone do not stop spending. Do not enable paid billing, create keys, or change production values merely to run CI.

For an authorized provider check, supply the candidate browser key and canonical origin through environment variables, then run from the repository root:

```sh
node backend/tools/check_projection_provider.mjs --allow-provider-check
```

This manual diagnostic is not run against real credentials in CI. It makes at most three Map Tiles root requests and one basic Geocoding v4 request, any of which can be billable if restrictions are absent, and stops at the first failed or inconclusive check. It requires a valid root response plus restriction-specific denials for unrelated/missing referrers and the other API. Generic 403s, disabled services, billing errors and quota failures are not proof. Output is sanitized JSON; exit 0 means the four observations passed. It does not change environment variables or enable the map. Confirm the exact Map Tiles-only allowlist in Google Cloud as well, then complete browser/device acceptance before release.

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

`rendererUrl` becomes the canonical backend origin plus `/brain-projection/earth.html` only when a separate browser key, verified-restrictions switch and HTTPS origin are configured. Private keys never appear here. The app displays the research cost before a sourced question is submitted.

### `POST /api/brain-projection/resolve`

Body: `{ "query": "place or address" }` (2–300 characters).

Returns `candidates`, `requiresConfirmation: true` and a short `answer`. Each candidate contains `id`, `label`, `address`, `latitude`, `longitude`, `userQuery`, `provider: "google"` and `partialMatch`. At most five candidates are returned. Every candidate requires explicit user confirmation, including a single apparently exact result. Google partial matches and mismatched street numbers/US ZIPs get an additional warning. No result causes no invented coordinates or fallback city. The inconsistent example “14360 Jupiter Rd, Brooklyn, 10012” must be corrected or explicitly matched to a fully displayed provider result before navigation.

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

The public `/brain-projection/earth.html` document contains map-only UI. The native app's bundled offline Projection shell embeds this first-party HTTPS page so the browser key has a valid restricted origin. The original home page does not gain network access. No bearer token, refresh token, account data or native bridge nonce is sent to the map iframe.

CesiumJS **1.147** comes from its official pinned release directory. JavaScript and stylesheet use SHA-384 Subresource Integrity; worker/assets use the same pinned version. No Google Earth website iframe is used. The viewer disables the default basemap, geocoder, terrain/ion services and unrelated controls; it uses only Google Photorealistic 3D Tiles. Explicit Google Maps text, Google's logo, Cesium credit and viewport-specific data attribution remain visible along the bottom. The parent shell must leave this strip unobstructed. Renderer links cannot navigate the isolated frame or open windows in this phase. No Street View is implemented.

The renderer has a restrictive CSP, no child frames, no forms, no object embedding, and no camera/microphone/geolocation permissions. Its `script-src` permits `unsafe-eval` solely because the pinned full Cesium bundle initializes Knockout with JavaScript string evaluation before the Viewer starts. This exception is limited to the isolated renderer routes; inline scripts remain blocked, and API/original-home/voice policies are untouched. No researched HTML is inserted into this document. It keeps a bounded in-memory GPU tile cache using Cesium's standard renderer; it does not download, export or persist map tiles or perform image analysis. Researched text is independent public-source research, not an interpretation of Google imagery. Save-place notes should preserve only the user's own query, an exempt provider place ID and user-authored note, not copied Google map content or imagery.

Parent → iframe:

```js
{
  type: 'korlix-projection-camera',
  camera: {
    sequence: 1,
    operation: 'flyTo', // closer | farther | left | right | reset | flyTo
    latitude: 40.7, longitude: -73.9, height: 650, heading: 0, pitch: -50
  },
  place: {id: 'provider-place-id', label: 'Confirmed place', latitude: 40.7, longitude: -73.9}
}
```

Camera angles are degrees; height is meters (25–40,000,000), latitude ±90, longitude ±180, heading ±360, pitch −90..0. Sequences must be increasing nonnegative safe integers. Messages must come from the actual parent window with opaque local origin `"null"` or the renderer's same HTTPS origin. Unknown fields are discarded; unsupported operations and malformed/stale messages are ignored. The iframe does not receive `userQuery`, account context or a native command channel.

Iframe → parent:

```js
{type: 'korlix-projection-status', status: 'loading' /* ready | error */, message: 'Public map status'}
```

`ready` is emitted only after a Cesium viewer and actual Google tileset have initialized, never for the illustrative globe or absent credentials. Tile/provider/WebGL errors are sanitized. There is a 30-second initialization deadline. Page close/error destroys the viewer, clears listeners/timers, and destroys any tileset that resolves after disposal, preventing stale ready events. The native shell separately validates the source/origin of status messages.

The renderer also emits `{type: 'korlix-projection-credits', height: <integer CSS pixels>}` when its full attribution footer changes size. `ResizeObserver` measures wrapping; older viewers fall back to post-render updates. Height is bounded to 0–4096 and the renderer viewport, and the parent independently validates the source/origin and clamps reserved space to its own viewport. No credit HTML or URLs cross this channel. The parent moves lower controls/captions and decorations above the measured footer, and scrolls above the pinned active voice dock. Closing the renderer disconnects the observer and resize listener.

## Verification

Run from `backend/`:

```sh
node --test test/brain_projection.test.mjs test/brain_projection_renderer.test.mjs test/brain_projection_provider_check.test.mjs test/brain_voice.test.mjs test/brain_live.test.mjs test/brain_billing.test.mjs test/brain_billing_meter_fallback.test.mjs test/auth_session_security.test.mjs
```

The Projection suites cover input/output bounds, exact/partial/no-result address handling, fixed provider URL and redirects, private-key separation and activation gating, required web-search evidence, malicious source URLs, missing reporting scope/date, existing auth status propagation, quota and retry behavior, free unavailable answers, pinned renderer assets/CSP, parent-message validation, camera actions and renderer disposal/failure races. Provider fixtures are explicit test-only data. The shared voice-meter fallback from release commit `65a660fcfcbaa3112584d353408aac6d6c7d4b12` is included and its regression suite runs alongside Projection.

`tools/check_projection_renderer.mjs` and the dedicated `brain-projection-api.yml` workflow exercise the production renderer document, headers and exact pinned SDK in Chromium. All Google/Ion requests are intercepted before navigation and use generated fixtures. This verifies SDK/CSP/WebGL integration without real map credentials; it does not verify Google account access, coverage or key restrictions.

Before release with real credentials, validate first-party HTTPS embedding and key referrer restrictions on actual Android/iOS WebViews, Google coverage and attribution at narrow screen sizes, device WebGL performance, and a small approved live sourced-query smoke test. This source change alone is not a deployed or provider-connected release.

## Official implementation references

- [Google Photorealistic 3D Tiles](https://developers.google.com/maps/documentation/tile/3d-tiles)
- [Google Map Tiles policies and attribution](https://developers.google.com/maps/documentation/tile/policies)
- [Google API security best practices](https://developers.google.com/maps/api-security-best-practices)
- [Google Geocoding request/response](https://developers.google.com/maps/documentation/geocoding/requests-geocoding)
- [CesiumJS release downloads](https://cesium.com/downloads/)
- [Cesium Viewer reference](https://cesium.com/learn/cesiumjs/ref-doc/Viewer.html)
- [OpenAI Responses web search and source evidence](https://developers.openai.com/api/docs/guides/tools-web-search)
