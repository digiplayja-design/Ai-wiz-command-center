# K136S-F2 — Frontend Learning Panel

F2 gives the account manager the spoken-learning experience on the live-convo screen, driving K136S-B's state machine from the real events: a trigger phrase in the manager's own speech, the screen's mic mute, a typed-only vault field, capture, a preview with a diff, a voice or typed confirmation (elevated changes: typed only), and a context refresh. It talks to the `/k136s/*` routes F1 mounted on the backend, relaying the screen's existing auth headers.

## Flow (what the manager experiences)

1. Mid-call the manager says **"Nova, learn this"** (or "Nova, remember this"). The mic is muted and the panel asks for the **BRAIN VAULT password — typed, never spoken**. Nothing the manager types is spoken to OpenAI because the local audio track is disabled first.
2. The panel posts the password once to `POST /k136s/grant` (the backend forwards it to the existing vault route). On success the mic is unmuted and capture starts.
3. The manager says the change; the panel accumulates only **user** transcripts (`conversation.item.input_audio_transcription.completed`). "That's all" / "Nova, done" or the **Done** button ends capture.
4. `POST /k136s/preview` returns the normalized text, classification, policy decision, and a word-level diff, shown as chips + coloured spans.
5. **Approve…** requests a single-use approval (`POST /k136s/approve/request`). Then either say **"confirm"** (non-elevated only) or **type CONFIRM**. Elevated changes (profile, high sensitivity) accept typed confirmation only, and if the vault grant is older than ~55 s the panel re-prompts the vault first.
6. `POST /k136s/approve/confirm` → **VERIFIED** (Nova learned it) with a **Refresh Nova now** button that ends and restarts the session so the backend rebuilds the context with the new memory — or REJECTED / EXPIRED / CANCELLED, each with a Close button.

Every timeout (vault 2 min, capture 3 min, preview 10 min, approval 120 s, session 10 min), cancel, rejection, and expiry unmutes the mic.

## Files

| File | Change |
| --- | --- |
| `lib/live_convo/k136s_learning_panel.dart` | **new.** `K136sLearningApi` (thin `package:http` client, relays `headersBuilder()` headers, adds `x-k136s-grant`), `K136sLearningController` (`ChangeNotifier` mirroring B's states, injected clock for tests), `K136sLearningOverlay` (a `Stack` showing the panel only while a learning session is visible), `K136sLearningPanel` (the UI). |
| `test/k136s_learning_panel_test.dart` | **new.** 14 controller tests against a fake API + 2 widget tests. |
| `lib/live_convo/korlix_live_convo_test_screen.dart` | **edited, six anchored changes**, every added line tagged `// K136S-F2` (below). |

## The six screen edits (anchored, additive except one line)

| # | Anchor (must match exactly once) | Change |
| --- | --- | --- |
| 1 | `import 'korlix_live_convo_transcript_export.dart';` | add `import 'k136s_learning_panel.dart';` after it |
| 2 | `bool _muted = false;` | add the field `K136sLearningController? _k136sController;` after it |
| 3 | `super.initState();` inside `initState()` | add the controller wiring: `api: K136sLearningApi(baseUrl: widget.backendBaseUrl, headersBuilder: widget.headersBuilder)`, `agentId: widget.<agent field>`, `setMuted: (m) => if (_muted != m) _toggleMute()`, `refreshContext: () => _endSession(); _startSession()` |
| 4 | `_userTranscript = text;` | add `_k136sController?.onUserTranscript(text);` after it (user speech only) |
| 5 | the single `return KorlixLiveConvoCharacterStage(` in `build()` and its closing `);` | wrap in `K136sLearningOverlay(controller: _k136sController, child: …)` — the `return` line is the **only deleted line**, re-added as `child:` |
| 6 | `void dispose() {` | add `_k136sController?.dispose();` as its first statement |

The agent id is taken from the first widget field present among `agentId`, `agentProfileId`, `profileId`, `characterId` (the edit prints which; it stops if none). The edit script refuses if any anchor is missing or duplicated, and is idempotent (it stops if the marker is already present).

## Security posture

Password typed only, forwarded once, never retained on the controller, cleared from the field on submit; grants are short-lived and re-prompted when stale for elevated changes; voice confirmation is impossible for elevated changes; every state exit unmutes the mic; the panel never sends realtime events itself — it only mutes/unmutes and, on request, restarts the session through the screen's own methods.

## Validation

`flutter pub get` in the fresh worktree (`pubspec.lock` must come back unchanged), `dart analyze` on the touched files (errors fail the block), `flutter test test/k136s_learning_panel_test.dart` — with the screen reverted to the base version and a STOP on any failure.

## Left for F3 (live)

Confirm the chosen agent field is the id the backend's agent helpers resolve; confirm that restarting the session picks up the new memory (else switch the refresh hook to the client's `session.update` path); confirm `widget.headersBuilder()` yields the `Authorization` header the backend's `requireUser` expects.
