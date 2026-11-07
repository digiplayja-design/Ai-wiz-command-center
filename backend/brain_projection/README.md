# Brain+Voice Projection backend

Optional map and public-place research services for the existing Brain+Voice app. The original native voice session, account authentication, memories, training, purchases and home page remain separate. Closing the map destroys its renderer; it does not end a voice session.

## Configuration

All capabilities default to unavailable unless their dependencies are configured. This change does not set production variables, deploy a service, create a Google project, enable billing, or create a subscription.

| Variable | Purpose | Exposure |
| --- | --- | --- |
| `BRAIN_PROJECTION_GEOCODING_KEY` | Google Geocoding API server key. Enable that API and apply appropriate server/API restrictions. | Backend only. Never included in API responses, renderer HTML, logs or iframe messages. |
| `BRAIN_PROJECTION_MAP_BROWSER_KEY` | Separate Google Map Tiles API browser key. Restrict it to the existing backend HTTPS origin and Map Tiles API. | Intentionally public in the map renderer document. It must never be an unrestricted or server key. Reusing the geocoding key is rejected. |
| `KORLIX_PUBLIC_BACKEND_URL` or existing `RENDER_EXTERNAL_URL` | Canonical existing first-party HTTPS origin, with no path, credentials, query or fragment. | Public renderer URL. The first variable takes precedence. |
| Existing `OPENAI_API_KEY` | Existing Responses API web search. | Backend only. |

Source inspection found no existing Maps/geocoding key configuration to reuse, so the two explicit key names above were introduced. The existing OpenAI configuration is reused. No Cesium ion token or account is needed for direct Google tiles.

Configuration indicates a provider is configured, not that a paid live request has passed. Invalid keys, domain restrictions, quotas, unsupported coverage, unavailable WebGL and provider failures produce unavailable/error states. This build was validated using injected provider fixtures; it did not make paid Google or OpenAI requests.

Google Map Tiles and Geocoding require their own enabled APIs and applicable Google Cloud billing/quotas. This implementation does not claim these services are free. Set appropriate Google project quotas before connecting the keys. Review the project's applicable Google Maps terms, including any EEA-specific behavior.

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

`rendererUrl` becomes the canonical backend origin plus `/brain-projection/earth.html` only when a separate browser key and HTTPS origin are configured. Private keys never appear here. The app displays the research cost before a sourced question is submitted.

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

The renderer has a restrictive CSP, no child frames, no forms, no object embedding, and no camera/microphone/geolocation permissions. It keeps a bounded in-memory GPU tile cache using Cesium's standard renderer; it does not download, export or persist map tiles or perform image analysis. Researched text is independent public-source research, not an interpretation of Google imagery. Save-place notes should preserve only the user's own query, an exempt provider place ID and user-authored note, not copied Google map content or imagery.

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

## Verification

Run from `backend/`:

```sh
node --test test/brain_projection.test.mjs test/brain_projection_renderer.test.mjs test/brain_voice.test.mjs test/brain_live.test.mjs test/brain_billing.test.mjs test/auth_session_security.test.mjs
```

The Projection suites cover input/output bounds, exact/partial/no-result address handling, fixed provider URL and redirects, private-key separation, required web-search evidence, malicious source URLs, missing reporting scope/date, existing auth status propagation, quota and retry behavior, free unavailable answers, pinned renderer assets/CSP, parent-message validation, camera actions and renderer disposal/failure races. Provider fixtures are explicit test-only data.

Before release with real credentials, validate first-party HTTPS embedding and key referrer restrictions on actual Android/iOS WebViews, Google coverage and attribution at narrow screen sizes, device WebGL performance, and a small approved live sourced-query smoke test. This source change alone is not a deployed or provider-connected release.

## Official implementation references

- [Google Photorealistic 3D Tiles](https://developers.google.com/maps/documentation/tile/3d-tiles)
- [Google Map Tiles policies and attribution](https://developers.google.com/maps/documentation/tile/policies)
- [Google API security best practices](https://developers.google.com/maps/api-security-best-practices)
- [Google Geocoding request/response](https://developers.google.com/maps/documentation/geocoding/requests-geocoding)
- [CesiumJS release downloads](https://cesium.com/downloads/)
- [Cesium Viewer reference](https://cesium.com/learn/cesiumjs/ref-doc/Viewer.html)
- [OpenAI Responses web search and source evidence](https://developers.openai.com/api/docs/guides/tools-web-search)
