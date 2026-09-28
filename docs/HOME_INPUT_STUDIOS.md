# Home input studios and account welcome

## Upload

`KorlixUploadStudio` stages up to eight supported files, each no larger than
15 MiB, matching the existing document endpoint's limits. Files, photo-library
selection and Camera Ask's existing camera capture are available. Users can
review file names, types and sizes, zoom photo previews, remove files or clear
the selection. Duplicate file names with identical bytes are skipped. Invalid
batches do not replace the previous selection. Summarize, Compare, Extract
details and Ask a question presets populate an editable prompt.

Attach returns a local draft to the original conversation. It does not start
an AI request. Send retains the existing upload, authentication and consent
flow. Back discards changes to the studio's copy of the selection. Account
changes close previews and the studio and discard pending picker results.

## K-Nova voice input

`KorlixVoiceComposer` starts with an editable copy of the conversation draft.
Dictation starts only on an explicit tap. The device/browser speech service
provides available languages and partial/final transcription. Users can
append to a draft, replace it, undo the last recording and review/edit the text.
Use this text returns it without sending. Open Live Convo returns the draft and
opens the existing conversational voice route.

Unsupported or denied dictation keeps the typing fallback available. Backgrounding
cancels recording; leaving disposes it; account changes discard the private
draft. Recording epochs reject stale transcription. The speech_to_text singleton's
status/error listeners are restored on exit so existing voice surfaces retain
their callbacks. No new speech service, dependency, or backend endpoint is added.

## Signup confirmation

Successful signup without a session displays the themed Welcome to KORLIX AI
card, submitted email, Supabase inbox instructions and three confirmation steps.
It explicitly states that the email must be confirmed before login. Back to
sign in preserves the email and clears the password; changing email clears both.
The known email-not-confirmed signin error opens the same instructions. A missing
signin session remains an error. Supabase continues to enforce confirmation;
the client does not invent a session or claim the email has been verified.

## Verification

Run the following focused suites:

```
flutter test --no-pub test/home_input_flows_test.dart test/auth_welcome_test.dart test/home_input_visual_test.dart test/korlix_action_button_test.dart test/chat_workspace_test.dart test/korlix_theme_test.dart test/camera_ask_test.dart
```

These cover uniform two-column dimensions, narrow and desktop layouts, large
text, upload validation/deduplication/cancellation, draft-only handoff, partial
speech results, final transcription, append/replace/undo, lifecycle cancellation,
late results, account changes and mocked signup/signin responses. Tests send no
signup emails or AI requests. Set `KORLIX_BUTTON_REVIEW`, `KORLIX_INPUT_REVIEW`
and `KORLIX_FLUTTER_ROOT` to render shipping widgets for visual inspection.

Real browser/device camera and microphone permission prompts require a device
smoke check; automated tests inject pickers and dictation results. No auth
configuration or database migration is required.
