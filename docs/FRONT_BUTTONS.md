# Front-screen button design

The front-screen controls use `KorlixActionButton` from
`lib/theme/korlix_action_button.dart`. The design includes a solid lower edge,
layered face, thin upper reflection and raised icon inset. Live Convo uses a
theme-colored voice orb and K-Nova branding.

Applied to the language controls, character preview control, conversation menu,
chat/image modes and starters, send button, Live Convo, Camera Ask, Upload,
Voice, Locator, Music Studio, Utility and its tools, quick actions and older
conversation-result actions. Existing callbacks, access gates and busy states
remain connected to their original handlers.

- Colors derive from the selected KORLIX palette, including Pure White and
  Pure Black. Text is painted above the decorative surface.
- Native `TextButton` handles pointer, keyboard, focus and disabled behavior.
  Targets are at least 48 logical pixels in each direction. Labels wrap.
- Selected controls show a check and expose selection to assistive technology.
  Locked controls retain their access flow and show a lock.
- Hover lifts by one pixel; pressing depresses by two. Keyboard focus has a
  distinct two-pixel outline. Reduced-motion and accessible-navigation settings
  disable movement and transitions. There is no idle animation.
- The send control retains the busy indicator and cannot submit again while busy.

## Verification

Run `flutter test test/korlix_action_button_test.dart test/chat_workspace_test.dart
test/korlix_theme_test.dart test/camera_ask_test.dart`. The button suite covers
pointer and keyboard activation, disabled/busy and locked behavior, selection
semantics, pointer cancellation, reduced motion, all 12 themes at 320px with
200% text, and representative phone/desktop layouts.

To render the actual button widgets for visual review, set
`KORLIX_BUTTON_REVIEW` to an output directory and `KORLIX_FLUTTER_ROOT` to the
Flutter SDK when running the button suite. No account, AI request or camera
permission is needed for these visual fixtures.
