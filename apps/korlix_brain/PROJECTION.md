# KORLIX Brain+Voice — Projection Mode

## Current implementation

Projection is an optional view over the existing Brain workspace. Command Center
and Discovery Theater are two presentations of the same selected place, camera,
research answer and Rici conversation. Confirmed destinations open recorded
Street View facing the selected location; 3D Earth is an explicit alternative
on the phone or tablet screen. Physical room projection, head tracking, headset
stereoscopy and live camera connections are separate future integrations.

The original home remains mounted. Its brain, navigation, memory, training,
welcome, account, billing and conversation controls retain their existing roles.
A small **Project virtual reality** shortcut opens the new view. A spoken
**“Rici, project virtual reality”** command can open it during an existing Live
Conversation or Deep Think session. Opening, switching rooms and closing the
view do not start a new voice session or end the current one.

**“Rici, can you open projection mode?”** also opens the view from Home while
Live Conversation or Deep Think is listening. The native controller validates the
original transcript and acknowledges its actual result. A canceled speculative
Live reply is excluded from the visible transcript and saved conversation context.
After Stop, the home conversation dock keeps **Start Live Conversation** (or
**Start Deep Think** for that selected mode) available across screens. Projection
keeps its own **Talk to Rici** restart control. Restart always requires a user tap.

## Immersive entrance

Each newly opened native Projection screen plays a two-second decorative
entrance: **Awaken** (0–500 ms), **Enter** (500–1,500 ms), then **Arrive**
(1,500–2,000 ms). The hollow brain, cyan/violet orbits, five portal layers and
room lighting carry the approved motion concept into the real workspace.
The standalone mockup's synthetic property and simulated voice controls are
not bundled in the app. The current property, loading/error state and actual
Rici conversation remain authoritative.

The entrance starts once per native screen nonce, after the normal bridge and
renderer setup. Search, destination confirmation, camera controls and voice
dispatch remain immediately available. Voice updates, room changes, subsequent
addresses and repeated same-nonce connection messages do not replay it.
**Skip entrance** and **Close projection** take effect immediately. The
temporary Skip control returns keyboard focus to the Projection heading when
needed; automatic arrival never moves focus away from other controls or an
address being typed.

The scene's large illustrative portal is hidden as soon as the remote renderer
is active, including while imagery is loading. Active property views retain
their complete untransformed rectangle; moving accents stay in surrounding
room decoration and app-owned trim. The fixed microphone dock and provider
attribution stay outside the animated layer. Arrival means the room entrance
has finished, not that imagery or a live feed is available.

Reduced motion uses a 240 ms opacity-only treatment. Timed cleanup is independent
of CSS animation events. Close, a native `foreground:false` snapshot, page
visibility loss, page disposal or a motion-preference change completes the
effect and clears its timers. Foreground return does not replay it. A fresh
nonce invalidates earlier callbacks before its own entrance begins.

## Supported flow

1. Open Projection using the home shortcut or an explicit voice command, such as
   **“Rici, enter VR.”**
2. The voice controls show the current microphone/session state. If voice is
   off, tap **Talk to Rici** and wait for **Listening** before speaking. Viewing
   imagery or dictating into the keyboard's address field does not start Rici.
   Under **Explore a property**, type a destination and tap **Explore**, or say
   **“Go to [full address or place]”** or **“Search [full street address].”**
   While Projection is open, a complete standalone street address starts a
   lookup, including after another property has already been selected. From
   home, use an explicit search command to open Projection and search together.
   In the open view, **“The address is [full street address]”** also works.
   Follow-up requests can replace that property without reopening Projection:
   **“Now show me [full street address]”**, **“The next address is [full street
   address]”**, **“Switch the address to [full street address]”**, or **“Show me
   [full street address] instead.”** Each lookup keeps its own explicit result
   confirmation. A new address can also replace results awaiting confirmation.
   If a search request is not recognized, Rici asks for another spoken attempt
   using **“Go to [full street address, city and postal code]”**.
   Numbered street addresses also accept
   **“Show me [full address]”** and **“Show [full address] in 3D.”** These commands
   retain the original street, unit, city and postal code. Research requests and
   live-camera questions do not become address-display commands.
3. A spoken search fills the address field, shows **Finding…**, and reveals the
   matching candidates without opening the keyboard. Confirm a geocoder
   candidate, including a single result: say **“Yes, that's it”** for one match
   or **“Choose the first result”** when several are shown. Partial matches are
   flagged. Rici does not silently discard a street number, city or postal code.
4. Use closer/farther, rotate and reset controls, or their spoken equivalents.
   Rici name variants and bounded polite phrasing are normalized before the
   original command is validated. **You said** and **View control** show the
   recognized words, interpreted action and result. **Stop zooming** stops the
   camera while leaving the conversation active.
5. Ask about building history, nearby places, mayor, population or area crime.
   Research returns numbered sources and the geographic scope/reference period.
6. Save an explicitly requested place note through the existing My Brain
   repository. Typed notes receive a native review dialog; a clear spoken save
   request supplies confirmation. Only the user's query/note and place ID are
   retained as the memory, not map imagery or copied geocoder details.
7. **Close projection** returns to home. **Stop conversation** stops the native
   conversation while leaving the view open.

## Landscape command center

Rotate the iPhone or iPad to either landscape direction to use the wide
Projection workspace. The app's native orientation settings already allow
landscape; the view adapts to the available viewport and safe area. The selected
property, provider iframe and current conversation stay mounted through rotation.
Returning to portrait restores the vertical layout without replaying the entrance.

The wide layout places the world surface beside a floating Explore/Rici console
and a nearby bank of labeled camera controls. On shorter phone screens, the
Explore/Rici console selectors keep the active form or conversation accessible
without moving the world out of view. Spoken searches reveal Explore and the
matching destination candidates. On larger screens the console can show both
sections. The microphone controls remain in a separate visible rail.

Cyan/violet ceiling ribs, sidewalls, a floor plane and luminous console edges
extend the approved Executive Bridge / Celestial Dome presentation. Projected
buttons retain readable labels, focus feedback and touch targets of at least
44 pixels. The depth treatment belongs to app-owned decoration and controls;
provider imagery and attribution keep their complete, untransformed rectangle.
Reduced-motion preferences continue to apply to the entrance and moving accents.

The **Live camera availability** control and spoken live-view requests currently
return an honest unavailable response. Street View is recorded imagery, not a
live camera connection; an unknown capture date stays unknown. Available
coverage and facade visibility vary by location. Unavailable Street View does
not silently switch to overhead imagery. This implementation does not infer
occupancy from imagery.

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
  The `destinationSearch` snapshot carries the current lookup sequence,
  complete user query, active state and typed/voice source. Unrelated voice or
  research snapshots preserve an unfinished address-field draft; a new lookup
  updates that field. Late completion cannot clear a newer lookup's progress.
  A genuine close/reopen refreshes server capabilities. Repeated open commands,
  room changes and searches share the current opening's check; late responses
  from an earlier opening cannot replace it. A failed check shows retry guidance,
  while a missing address or map service is identified separately.
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
  message is consumed. The workspace keeps voice activation and session status
  reachable while viewing imagery; active Pause/Resume/Stop controls retain the
  same native session. The voice dock must not cover the provider iframe.
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
  Both modes authorize direct controls from the item-bound original transcript.
  Missing Live transcription has a bounded diagnostic; stale or absent words
  cannot authorize a delayed camera action.

## Backend integration

Build 19's matching Street View renderer is deployed at backend revision
`31f763a812d6b5506918429e7a86d6ad976868b0` on the existing production service.
The subsequent voice-control repair is native/UI work and uses that renderer.
Its new signed build and device acceptance must be verified separately.

Historical integration baseline: this app branch starts at the mobile release baseline
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

The server's dedicated map renderer uses Google Maps JavaScript Street View
and optional `Map3DElement` on the quarterly channel. It is public map-only content and
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

The voice-control repair is a candidate pending its own CI, signed-build and
delivery evidence. Physical iPhone/iPad microphone and WebView acceptance is
still required; neither parser tests nor browser fixtures establish that check.
Follow `store/apple/testflight-notes.txt`, recording the installed build, voice
phase, **You said** text, **View control** and result for any failed command.

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
