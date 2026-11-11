# KORLIX Brain+Voice — Projection Mode

## First implementation

Projection is an optional view over the existing Brain workspace. Command Center
and Discovery Theater are two presentations of the same selected place, camera,
research answer and Rici conversation. This phase provides an interactive 3D map
on the phone or tablet screen. Physical room projection, head tracking, headset
stereoscopy and live camera connections are separate future integrations.

The original home remains mounted. Its brain, navigation, memory, training,
welcome, account, billing and conversation controls retain their existing roles.
A small **Project virtual reality** shortcut opens the new view. A spoken
**“Rici, project virtual reality”** command can open it during an existing Live
Conversation or Deep Think session. Opening, switching rooms and closing the
view do not start a new voice session or end the current one.

## Supported flow

1. Open Projection using the home shortcut or an explicit voice command.
2. Say **“Go to [full address or place]”**, or type the destination.
3. Confirm a geocoder candidate, including a single result. Partial matches are
   flagged. Rici does not silently discard a street number, city or postal code.
4. Use closer/farther, rotate and reset controls, or their spoken equivalents.
5. Ask about building history, nearby places, mayor, population or area crime.
   Research returns numbered sources and the geographic scope/reference period.
6. Save an explicitly requested place note through the existing My Brain
   repository. Typed notes receive a native review dialog; a clear spoken save
   request supplies confirmation. Only the user's query/note and place ID are
   retained as the memory, not map imagery or copied geocoder details.
7. **Close projection** returns to home. **Stop conversation** stops the native
   conversation while leaving the view open.

Live-view requests currently return an honest unavailable response. Recorded 3D
imagery is never labeled live, and an unknown capture date stays unknown. This
implementation does not include Street View or infer occupancy from imagery.

Google-returned address labels stay visual in the candidate and selected-place
cards. Each Google card has a compact **Google Maps** source credit, including
when geocoding works but the map is unavailable; independently sourced research
remains separate. Rici gives generic spoken lookup/selection confirmations and
can speak the user's commands and independently sourced research. Provider
address labels are not passed into those spoken confirmations. See the
[Geocoding attribution policy](https://developers.google.com/maps/documentation/geocoding/policies)
and the Maps Content text-to-speech boundary in
[Google Maps Platform terms §3.2.3(a)(iv)](https://cloud.google.com/maps-platform/terms).

## Native boundaries

- `brain_projection.dart` owns ephemeral view state and validates all actions.
  New lookups, selection changes, Stop, close and account disposal invalidate
  stale results. The full original transcript authorizes voice actions.
- `brain_projection_screen.dart` hosts a separate bundled WebView. Its narrow
  channel requires an unpredictable per-view nonce. No account token, full
  `Korlix` bridge or memory repository is exposed to the remote map frame.
- The native controller accepts only the exact HTTPS renderer path on the
  configured API origin: `/brain-projection/earth.html`.
- The bundled parent validates both message origin and source. The iframe only
  receives bounded camera/selected-place data and returns loading/ready/error
  status. The provider owns the entire iframe, including its controls, logos,
  links and attribution. While loading and ready, KORLIX titles and badges stay
  above the iframe; the selected-place panel, camera buttons and imagery caption
  remain below it in normal document flow. App decorations never cover the map.
  No provider shadow DOM is inspected or altered, and no remote credit-height
  message is consumed. During a conversation, the workspace scrolls above the
  pinned voice dock so Stop remains reachable without covering the iframe.
- The iframe permits scripts, its own origin and provider popups that leave the
  iframe sandbox. It does not grant top-level navigation, forms, downloads,
  camera, microphone, geolocation or access to the local native bridge. A
  separate provider page must not replace the local workspace. Browser tests
  exercise a user-clicked external link and check that the popup has no opener,
  workspace data or native bridge.
- `brain_projection_navigation.dart` handles approved Google provider links
  before main/subframe routing, covering the different Android/WK popup flags.
  Exact HTTPS `www.google.com`, `maps.google.com` and `policies.google.com`
  map-view, Maps terms/legal-notice and terms/privacy path families open through
  the existing external launcher. Host credentials, unusual ports, malformed or
  oversized URLs, unrelated paths and redirect/search/account parameters are
  rejected. Concurrent launches and rapid repeated callbacks are suppressed.
  The local document never navigates to the external page, and the successfully
  loaded bundled asset URL is pinned before sending its nonce. Google HTTPS
  subframes are permitted separately to match the hosted renderer's CSP; on
  Android the plugin omits subframe navigation callbacks, so CSP enforces that
  boundary. The allowlist follows the
  [Maps URL map-view form](https://developers.google.com/maps/documentation/urls/get-started#map-action)
  and the provider's legal URLs; actual device link variants need acceptance.
- Source links open externally only when present in the current answer.
- Live Conversation appends `control_projection` to the acknowledged server
  configuration, preserving the original memory tool and account instructions.
  Legacy clients retain their original one-tool contract. Deep Think intercepts
  supported place commands and otherwise uses the existing reasoning pipeline.

## Backend integration

This app branch starts at the mobile release baseline
`217e19a5bb628a9673e143eaa305dca789fff831`. Its historical backend directory is not
the deployment baseline. The matching API change is isolated on
`feature/brain-projection-api-20261107`. It includes the shared voice-meter fix
from current backend release `65a660fcfcbaa3112584d353408aac6d6c7d4b12` so deploying
Projection cannot revert that repair. Always compare the API branch against the
latest deployed backend before release.

The API provides authenticated config, address resolution and sourced answers:

```text
GET  /api/brain-projection/config
POST /api/brain-projection/resolve   {query}
POST /api/brain-projection/answer    {question, place}
```

The server's dedicated map renderer uses Google Maps JavaScript
`Map3DElement` on the quarterly channel. It is public map-only content and
consumes no account credentials. Configuration requires separate
`BRAIN_PROJECTION_GEOCODING_KEY` and `BRAIN_PROJECTION_MAPS_JS_BROWSER_KEY`
values, plus the correct public backend origin. The browser key must have the
documented website and Maps JavaScript API restrictions. It stays withheld and
the map unavailable until `BRAIN_PROJECTION_MAPS_JS_RESTRICTIONS_VERIFIED=true`
is set after allowed-origin and denied-origin/API checks. The old Map Tiles
browser-key configuration names are ignored. A server key is never substituted
for the browser key.
Provider setup and tests are documented in `backend/brain_projection/README.md`
on the API branch. Unconfigured services are displayed as unavailable.

## Existing usage accounting

Projection research uses the application's existing typed-search allowance:
currently four credits for a successful sourced answer. Config supplies the
cost label displayed beside the question control. An unavailable, failed or
source-less answer does not incur a research charge. Local camera/room controls
do not invoke research. An active conversation continues using its existing
voice minute meter. This change creates no subscription product or price.

Google usage has its own provider billing/configuration; the build does not
enable a Google project, provision keys, or change production environment values.

## Validation and release

- Projection controller tests cover exact renderer origin, candidate
  confirmation, stale results, source allowlisting, honest unavailable states,
  original transcript authorization and bridge isolation.
- Pure navigation-policy tests cover allowed provider links, Android/WK popup
  routing, malicious URLs, exact main-document protection, CSP-aligned Google
  subframes, duplicate launch callbacks, disposal and launcher failures.
- Voice tests cover legacy/new session negotiation, original item-bound
  transcripts, duplicate calls, interruption, source metadata, Deep Think
  passthrough and unchanged memory callbacks.
- `tools/check_projection.cjs` covers both rooms at five viewport sizes and the
  native/iframe contracts. It verifies the entire provider iframe is clear of
  app-owned UI during loading and readiness, with and without an active voice
  session, and checks its corners and center remain reachable. It also verifies
  that retired geometry messages have no effect and that external provider
  popups stay separate from the local workspace. Google geocoding attribution
  is checked in both rooms at 320/390px with the map disabled, alongside the
  existing non-Google source cases. The original home, welcome and ambience
  checks remain part of the same CI job.
- The existing mobile validation workflow is enabled for this isolated feature
  branch. It runs Flutter analysis/tests, builds an Android debug APK, builds an
  iOS simulator app and compiles an unsigned iPhone binary. It does not publish
  to either store or deploy the backend.

Before release, validate a configured map on physical iPhone/Android devices,
including WebGL memory use, microphone continuity, native Back, backgrounding,
address mismatch, source links, account changes and saving/reopening a note.
Provider-owned attribution and control links also need device acceptance. The
iframe permits separate provider popups, and the native policy routes its
allowlisted destinations to the external launcher. A passing browser fixture
or pure policy test does not establish that a physical Android/iPhone WebView
can open every actual SDK link variant in its external application.
The ordinary welcome/audio handoff and Live/Deep modes must pass the existing
device checks. A store release needs a fresh build number after acceptance.
