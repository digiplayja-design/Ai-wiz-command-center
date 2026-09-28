# Camera Ask

The home Camera Ask button opens a dedicated visual-question workspace.

- Native camera capture and an in-browser preview, with camera switching. Browser capture requests video only. Leaving, hiding the tab, capture completion, account changes, and errors release camera tracks. Late permission results are discarded and their tracks stopped.
- Gallery selection, previews, enlargement, retakes, removal, and up to three photos (8 MB each, 16 MB total). Photos remain local until the explicit Ask action.
- Understand, read text, translate, compare, solve, and troubleshoot modes; optional custom questions; English/Spanish/French answer language; brief, detailed, or step-by-step answers.
- Follow-ups use the same photos and the last four bounded turns in this workspace. A new photo session clears that context. It does not import global chat history.
- Answers render in the workspace, with copying and text export. The Saved to History label appears only when the API returns a generation ID.

## Existing services

The client uses the existing authenticated /api/analyze-documents endpoint, existing OpenAI consent flow, account allowances, and generation history. Each answer uses one generation credit under the existing endpoint. No new provider, database table, migration, or backend release is needed.

There is no automatic submission or retry. An ambiguous timeout or interrupted connection directs the user to History before retrying because server work may still finish. The same photos remain available for a deliberate retry.

The workspace binds to the signed-in issuer, user, and session; normal token refresh remains valid. Different accounts, sign-out, expired authorization, and late responses invalidate access and clear private content, including open image previews and camera routes. Nothing is persisted in local browser storage by this feature.

## Verification

test/camera_ask_test.dart covers multipart request content, bounds, comparison prerequisites, duplicate request prevention, consent, real pending-versus-complete UI state, account isolation, follow-up scoping, export, new sessions, and narrow/wide light/dark layouts with enlarged text.

The existing Agent Studio and Live Voice workspace tests are navigation regression gates. Run targeted analysis and a production Flutter web build. The browser-specific capture module also needs a physical-device camera/permission smoke check; Flutter widget fixtures do not establish camera hardware behavior or real provider answer quality.
