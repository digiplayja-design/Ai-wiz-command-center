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
  receives bounded camera/selected-place data and returns renderer status and
  bounded attribution height. The map, caption and controls reserve room for
  wrapped provider credits. During a conversation, the workspace scrolls above
  the pinned voice dock so Stop remains reachable without covering attribution.
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

The server's dedicated map renderer uses Cesium and Google Photorealistic 3D
Tiles. It is public map-only content and consumes no account credentials.
Configuration requires separate `BRAIN_PROJECTION_GEOCODING_KEY` and
`BRAIN_PROJECTION_MAP_BROWSER_KEY` values, plus the correct public backend
origin. Google currently documents IP restrictions for Map Tiles, so this
direct browser integration requires actual allowed-origin and denied-origin/API
tests before activation. The browser key stays withheld and the map unavailable
until `BRAIN_PROJECTION_MAP_BROWSER_RESTRICTIONS_VERIFIED=true` is set after those
checks. A server key is never substituted for the browser key.
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
- Voice tests cover legacy/new session negotiation, original item-bound
  transcripts, duplicate calls, interruption, source metadata, Deep Think
  passthrough and unchanged memory callbacks.
- `tools/check_projection.cjs` covers both rooms at five viewport sizes and the
  native/iframe contracts. The original home, welcome and ambience checks remain
  part of the same CI job.
- The existing mobile validation workflow is enabled for this isolated feature
  branch. It runs Flutter analysis/tests, builds an Android debug APK, builds an
  iOS simulator app and compiles an unsigned iPhone binary. It does not publish
  to either store or deploy the backend.

Before release, validate a configured map on physical iPhone/Android devices,
including WebGL memory use, microphone continuity, native Back, backgrounding,
address mismatch, source links, account changes and saving/reopening a note.
The ordinary welcome/audio handoff and Live/Deep modes must pass the existing
device checks. A store release needs a fresh build number after acceptance.
