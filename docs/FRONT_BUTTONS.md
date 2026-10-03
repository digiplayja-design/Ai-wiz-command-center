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
