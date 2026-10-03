# Front-screen button design

The front-screen controls use `KorlixActionButton` from
`lib/theme/korlix_action_button.dart`. The design includes a solid lower edge,
colorful gradient face, thin upper reflection and raised icon inset. Live Convo
uses a violet face, teal voice orb and K-Nova branding in every theme.

Applied to the language controls, character preview control, conversation menu,
chat/image modes and starters, send button, Live Convo, Camera Ask, Upload,
Voice, Locator, Music Studio, Utility and its tools, quick actions and older
conversation-result actions. Existing callbacks, access gates and busy states
remain connected to their original handlers.

Home shortcuts now use `KorlixActionGrid` with exactly two equally sized tiles
per row, including the final incomplete row. Shared Upload, Voice, Camera Ask
and More tools controls appear under Start here. Operations and growth tools
are grouped under For business; everyday creative, learning and personal
tools are under For personal use. Enterprise-only entries keep their existing
visibility and access checks. Grid height expands for accessibility text sizes.

Upload and Voice open reviewable input studios described in
`docs/HOME_INPUT_STUDIOS.md`.

- As of October 3, 2026, enabled button faces have their own feature colors,
  independent of the selected page theme, including Pure White and Pure Black.
  Blue, teal, violet, coral, amber, rose, indigo, emerald and cyan identities live
  in `korlix_button_colors.dart`. Known aliases share their feature color; unknown
  labels use a deterministic fallback. Generic theme accents cannot turn these
  controls monochrome. Explicit danger, stop, delete and call-end actions remain red.
- Label and subtitle contrast is at least 4.5:1 across the gradient, with a dark
  foreground on amber and white on darker faces. Interaction overlays increase
  contrast. Disabled and busy controls are muted and cannot activate.
- Standard FilledButton and ElevatedButton defaults use blue and teal in every
  theme; standard text and outline actions use readable blue accents. Theme
  backgrounds, panels and saved selections remain intact. The theme picker
  previews the colorful send button and explains the consistent button colors.
- Native `TextButton` handles pointer, keyboard, focus and disabled behavior.
  Targets are at least 48 logical pixels in each direction. Labels wrap.
- Selected controls show a check and expose selection to assistive technology.
  Locked controls retain their access flow and show a lock.
- Hover lifts by one pixel; pressing depresses by two. Keyboard focus has a
  distinct outline and contrasting outer ring. Reduced-motion and accessible-navigation settings
  disable movement and transitions. There is no idle animation.
- The send control retains the busy indicator and cannot submit again while busy.

## Creation languages and October welcome

The creation workspace receives the active home language (`en`, `es`, or `fr`).
`KorlixChatCopy` supplies its heading, starter prompts, chat/image modes, image
options, composer hints, send label, progress messages and result controls.
Changing language updates the copy immediately while keeping existing user/AI
content and selected image options. Localized action buttons supply a stable
`colorIdentity`, so translating their label never changes their feature color.

During the device's local October, the login screen uses a friendly seasonal
background with smiling pumpkins, a ghost, moon and stars, plus a compact
greeting and warm sign-in button. `KorlixOctoberWelcome` automatically restores
the selected theme outside October. `AuthScreen.seasonalDate` is an optional
test/preview override; production uses the device's current date. Decorations
ignore pointer events and screen readers, and have no animations. The existing
authentication, signup and confirmation handlers are retained.

`test/chat_workspace_test.dart` checks live language changes, stable rendered
colors, translated starter behavior, unchanged image API values and narrow
French layouts. `test/october_login_test.dart` checks month boundaries and
decoration accessibility. `test/auth_october_integration_test.dart` exercises
the real sign-in/signup form with mocked HTTP, password visibility, small
screens, keyboard insets and increased text size. Set `KORLIX_AUTH_REVIEW` and
`KORLIX_FLUTTER_ROOT` to render its real-form phone/tablet screenshots.

## Remembered login and password-manager support

The login form has separate `Remember my email` and `Offer to save password`
choices. Email remembrance is opt-in; disabling it removes the email from the
device-local `korlix_login_preferences_v1` record. Only the email and these
boolean preferences are stored there, independently of the authenticated
session. Ordered writes prevent rapid checkbox changes from restoring an
opted-out email. Storage failures do not prevent sign-in, and delayed loading
cannot overwrite an email the user has already typed or autofilled.

One cancellable `AutofillGroup` groups username/email with password (or
`newPassword` during signup). A successful sign-in or accepted signup requests
the OS/browser save flow before navigation or clearing the form, according to
the user's preference. Failed attempts and abandoning the form never request
a save. Turning the save offer off still permits existing credentials to
autofill. Passwords are never saved by KORLIX in preferences; prompts and saved
credentials are managed by the user's password manager. Native iOS automatic
credential saving additionally requires associated-domain configuration and
device validation; this web release does not claim that native setup.

`test/login_preferences_test.dart` covers storage, opt-out, ordered writes and
failure handling. `test/auth_remember_login_test.dart` covers actual login-form
restoration, independent choices, autofill hints, successful/failed/cancelled
flows and user-input preservation using mocked HTTP and platform messages.

## Verification

Run `flutter test test/korlix_button_colors_test.dart test/korlix_action_button_test.dart test/chat_workspace_test.dart
test/korlix_theme_test.dart test/camera_ask_test.dart`. The button suite covers
pointer and keyboard activation, disabled/busy and locked behavior, selection
semantics, pointer cancellation, reduced motion, all 12 themes at 320px with
200% text, palette contrast at endpoints and intermediate gradient colors, stable
feature identities, and representative phone/desktop layouts. Standard buttons
are also checked in enabled, hovered, pressed, focused and disabled states.

To render the actual button widgets for visual review, set
`KORLIX_BUTTON_REVIEW` to an output directory and `KORLIX_FLUTTER_ROOT` to the
Flutter SDK when running the button suite. No account, AI request or camera
permission is needed for these visual fixtures.
