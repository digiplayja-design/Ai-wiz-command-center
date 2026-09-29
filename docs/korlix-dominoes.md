# KORLIX Social Dominoes

Open **Social → Dominoes · play with video**. Create a private two-player table or four-player partner table, invite accepted Social connections, and have each player select Ready. The host deals. Invitations also appear as a direct Social message; no address-book messages are sent automatically.

This is original free-play block dominoes with a double-six set, seven tiles per player, no drawing, and opposite-seat partners in four-player games. The highest dealt double opens (highest total tile if no double is dealt). Players must play if a move exists. An empty hand wins; a blocked table is decided by remaining team/individual pip totals. Ties award no points. Points have no monetary value. No wagers, wallets, purchases, or cash-out are implemented.

The backend owns shuffling, turns, tile legality, scoring, and private hands. Clients submit a revision and unique action ID; conflicts trigger a refresh. Each player sees only their own tiles. Tables expire after four hours. Leaving an active round or the host leaving closes the table.

Video is explicit opt-in through **Join video & audio**. One local capture feeds up to three WebRTC peer connections. Each remote participant has a separate audio output; video renderers contain video tracks only. Controls cover microphone, camera, camera switch, speakerphone where supported, resume sound, and reconnect. Browser speaker routing depends on the device/browser. Cameras remain beside the board in landscape and above it in portrait. Backgrounding or leaving stops local media; returning requires joining video again. Nothing records the call.

Video uses the existing authenticated `SOCIAL_ICE_SERVERS` / `SOCIAL_CALLS_ENABLED` configuration. TURN relay configuration is needed for reliable connectivity on restrictive networks. Four-player mesh video depends on participants' bandwidth and devices. Automated tests cover track handling, signaling epochs, cleanup, game actions, and responsive layouts; an actual four-device call remains a release follow-up.

Frontend checks:

```sh
flutter analyze --no-pub lib/social/domino lib/social/social_screen.dart test/domino_test.dart
flutter test --no-pub test/domino_test.dart test/social_test.dart test/social_call_audio_test.dart
flutter build web --release --no-pub --base-href /app/
```

Backend installation and private data rules are documented on the backend release branch in `docs/korlix-dominoes.md`. Apply its Supabase migration before exposing the feature.
