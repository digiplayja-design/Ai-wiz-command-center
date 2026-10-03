# VoiceScribe and Copy Box workspaces

VoiceScribe and Copy Box open the shared workspace in `lib/text_workspace` for every signed-in KORLIX account. As of October 3, 2026, neither tool requires a Custom Access code, a seven-day trial entitlement, or a Custom Access status request. Home and utility buttons remain usable while unrelated Custom Access requests are loading. Legacy Custom Access tiles show both tools as included without a code; paid add-on checks remain unchanged.

Sign-in, account/session isolation, third-party AI consent and the ordinary `/api/generate` usage limits still apply. This is a frontend access correction; no backend or database changes are needed.

## User workflows

- Named entries, searchable title/category/body, favorites and recent-first ordering.
- First-time users see an editable box immediately. New entry, templates and duplicate use IDs that work in both the web app and native apps.
- New, duplicate, delete with Undo, copy one entry or all filtered results.
- Meeting, interview and field-note starters for VoiceScribe; follow-up, project-update and support templates for Copy Box.
- `{{field}}` placeholders: fill once, preview, copy without changing the saved template.
- KORLIX actions: polish, summarize, action items, meeting notes, professional email, shorten. Uses existing authenticated `/api/generate` and its existing usage rules. Explicit third-party AI consent, review original and result, discard/apply/save-as-new. Applying rejects concurrent changes to the original.
- Up to ten prior text versions before AI replacement, dictation and restoration. Ordinary keystrokes autosave but do not create individual history entries.
- VoiceScribe device-language selection, interim transcript display, append dictation, explicit stop, automatic stop on app background/exit, session guards rejecting late speech results. Final speech results may follow `notListening`; they are accepted until done/stop.

## Data and privacy

Storage is local SharedPreferences, scoped by JWT issuer + account ID and tool. This is not encrypted storage or cloud sync. Device/browser speech services determine where speech is processed. Raw audio is not recorded by this feature. Selected text is sent to the existing AI endpoint only on a requested AI action after consent.

Older global keys remain untouched. Import is explicit, warns about shared-device content, copies nonempty entries and records an account/tool import marker. Invalid JSON fails closed without replacing stored data. Save errors are visible and offer retry/copy recovery. Writes are serialized using snapshots.

Account session changes clear the editor, close workspace dialogs, cancel dictation and reject late AI responses. Previously queued writes remain scoped to the original account. Clearing browser/site storage removes locally saved entries; use Copy results to keep an external text backup.

## Verification

`flutter test --no-pub test/text_workspace`

`DART_BIN=/path/to/dart node --test test/web/text_workspace_ids_test.cjs`

The compiled JavaScript regression covers the web-specific failure that previously prevented creating a box: `1 << 32` becomes zero in JavaScript and is not a valid random-number bound.

Covers account/tool isolation, explicit non-destructive import, corrupt-data preservation, templates, bounded history, autosave/search, AI review, signout/late AI responses, repeat dictation/late-result rejection, final-result ordering and narrow phone layout.

Real microphone/provider behavior requires a supported browser/device and microphone permission. This release does not add uploaded-audio transcription, speaker diarization, recording playback, or cloud sync.
