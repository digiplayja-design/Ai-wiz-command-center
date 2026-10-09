# Camera Ask

The home Camera Ask button opens a dedicated visual-question workspace.

- Native camera capture and an in-browser preview, with camera switching. Browser capture requests video only. Leaving, hiding the tab, capture completion, account changes, and errors release camera tracks. Late permission results are discarded and their tracks stopped.
- The browser camera has explicit Turn light on/off actions when the selected camera exposes a controllable torch. The light can stay on while framing and capturing; releasing the camera also releases the light. Switching cameras starts with the flashlight off. Capture and camera switching wait for pending light changes. Light commands change only torch constraints and keep the same preview stream. Stale/missing flashlight settings are advisory; they never close the camera. A rejected light command shows a nonblocking warning while keeping photo capture available. If changing the light pauses playback, the same video element resumes. Unsupported cameras/browsers keep normal photo capture and show guidance to use the phone camera's flash and choose that photo. Native apps continue to use the system camera's own flash controls where available.
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

`test/camera_flashlight_test.dart` checks capability detection, on/off changes, stale/missing/unreadable settings, rejected requests, duplicate taps, and late operations after closing. Physical-device checks must cover rear-camera flashlight on/off, a lit photo, camera flip, back navigation, capture completion, and hiding/locking the app. Confirm the light is off after each exit and that unsupported hardware still captures normally. Browser torch behavior follows the [MediaStream Image Capture constraints](https://www.w3.org/TR/image-capture/#dom-mediatrackcapabilities-torch); support is detected per track, not inferred from the device name.

`test/web/camera_capture_browser_test.cjs` runs the production capture route in Chromium with a generated video stream and injected camera responses. It checks that stale/missing/unreadable/rejected flashlight responses preserve the live preview and allow capture, paused video resumes, on/off changes do not reopen the camera, and capture/back navigation release the track. Run with Playwright installed:

```bash
flutter build web --release --no-web-resources-cdn --base-href=/ --target=test/fixtures/camera_capture_browser.dart --output=build/camera_capture_browser
node --test test/web/camera_capture_browser_test.cjs
```

The browser fixture validates preview lifecycle, not a physical phone's flashlight. A known example of why settings cannot be treated as an immediate hardware confirmation is [WebKit issue 280970](https://bugs.webkit.org/show_bug.cgi?id=280970), which reported a stale torch value despite a successful light change.
