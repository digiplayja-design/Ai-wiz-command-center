# Email Enhancer

The home business tile opens a dedicated, theme-aware email workspace. Mobile uses a single column and persistent primary action; desktop places source and settings side by side. Native vector envelope artwork, elevated controls and selected navigation states match KORLIX skins.

## User workflow

- Polish an existing email, create an email from notes, or reply to an incoming email with explicit reply instructions.
- Six tones, three length targets, original-language output or five selected languages, recipient context, goal and signature.
- Four editable starters, local UTF-8 text import and the existing Rici voice composer (voice-plan access applies).
- Three selectable subject suggestions; editable subject/body; original versus edited comparison; explanatory edit notes and items to confirm.
- Five recent AI versions in the open session. Switching versions or regenerating over manual edits requires confirmation.
- Up to 20 account-scoped drafts in device/browser storage, manual save, search, reopen and delete. These are not synchronized between devices. Another-window conflicts and corrupt storage do not silently overwrite drafts.
- Copy body or full email; export text or UTF-8 MIME .eml. EML marks the file as an unsent draft, with encoded/folded subject and base64 body. Compatibility depends on the email app. No recipient or sending action is added.

## Integration

`POST /api/email-enhancer` in the backend release uses existing server-side authentication, allowance checks and credit accounting. One successful enhancement costs one credit. It asks OpenAI for validated structured output, without web tools, email tools, chat history or long-term memory. Third-party AI consent is required. The server keeps only a bounded 15-minute in-process replay cache (not durable across restarts); the client retries a failed identical request with the same key and never automatically retries.

Draft/output state is cleared when the issuer, account or session changes; late responses cannot repopulate a different session. JWT parsing is solely a frontend lifecycle guard: authorization is performed by the existing server verifier.

## Verification

`flutter test --no-pub test/email_enhancer_test.dart test/korlix_action_button_test.dart`

`node --test backend/test/email_enhancer.test.mjs backend/test/resume_studio.test.mjs` in the backend checkout.

Provider responses, clipboard, imports and exports are mocked in automated workflow tests. Layouts are captured at phone and desktop sizes including 200% text. Live microphone/provider interaction and each email application's EML import behavior require physical-device review. No real emails are sent in testing.
