# VoiceScribe and Copy Box workspaces

Both existing Custom Access routes now open the shared workspace in `lib/text_workspace`.
Existing trial/custom-access checks remain in `_openUtilityWorkspace` and the Custom Access menu.

## User workflows

- Named entries, searchable title/category/body, favorites and recent-first ordering.
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

Covers account/tool isolation, explicit non-destructive import, corrupt-data preservation, templates, bounded history, autosave/search, AI review, signout/late AI responses, repeat dictation/late-result rejection, final-result ordering and narrow phone layout.

Real microphone/provider behavior requires a supported browser/device and microphone permission. This release does not add uploaded-audio transcription, speaker diarization, recording playback, or cloud sync.
