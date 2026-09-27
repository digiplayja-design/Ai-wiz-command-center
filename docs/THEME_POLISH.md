# KORLIX theme polish

The six existing theme IDs now use coordinated palettes with calmer backgrounds,
clearer text, and readable solid primary actions. Stored theme IDs and earlier
aliases remain compatible.

| Saved ID | Display name | Appearance |
| --- | --- | --- |
| `korlix_blue` | KORLIX Midnight | Navy, cyan, lavender |
| `matrix_green` | Matrix Forest | Forest, mint, violet |
| `ultra_gold` | Obsidian Gold | Warm charcoal and gold |
| `pink_white` | Rose Quartz | Light rose and berry |
| `dark_crimson` | Crimson Ice | Plum, crimson, icy blue |
| `white_gray` | Pearl Slate | Light pearl, slate, teal |

## Behavior

- The home palette shortcuts have 48-pixel targets, named tooltips, and a checkmark.
- Preview themes opens a scrollable palette gallery with sample conversation cards.
  Selecting a preview changes only the gallery. Apply theme commits the selection;
  closing the gallery discards the preview.
- The application theme listens to the existing theme notifier, so shared controls,
  menus, inputs, dialogs, and brightness update with the selection. Navigation and
  draft state remain intact.
- Local selection applies immediately. Existing local persistence and backend theme
  synchronization remain best effort, with a ten-second network timeout.
- The main composer uses a solid primary send action with a contrasting icon.
  Home surfaces use quieter borders and shadows. The logo and octagonal answer
  frame remain intact.
- Improve My Picture inherits the selected palette, including its cards, errors,
  and transparency preview. Its image processing behavior is unchanged.

## Verification

`test/korlix_theme_test.dart` covers all six palettes, saved aliases, route and draft
preservation, preview/cancel/apply, narrow screens, enlarged text, shortcut targets,
and theme inheritance in the picture workspace.

The shared palette tests require at least 4.5:1 contrast for the tested text and
accent colors against shared opaque surfaces and primary button labels, plus 3:1
for input focus cues. This is a component-level check, not a claim of application
wide WCAG compliance. Legacy screens with their own explicit colors may retain
their existing styling.

```sh
flutter test test/korlix_theme_test.dart test/picture_studio_test.dart \
  test/chat_request_test.dart test/chat_workspace_test.dart test/meeting_copilot
flutter build web --release --base-href /app/ --pwa-strategy=none
```

Local visual review covers six palette cards at desktop width, the phone theme
picker, and the Rose Quartz picture workspace. It does not substitute for a
signed-in production session. After deployment, refresh `/app/`, open Preview
themes, try a light and dark palette, and confirm the choice survives a refresh.

This is a frontend-only release. Backend services, AI model configuration, Nova
voice/recording behavior, and database configuration are unchanged.
