# Color themes, screen skins, and look templates

The appearance studio extends the earlier six-palette release with independent
color and wrapper selections. Open it from the home theme controls or Settings →
Themes & Screen Skins.

- **Color themes:** 12 palettes. Six additions are Pure White, Pure Black,
  Lavender Mist, Ocean Blue, Sunset Copper, and Mint Cloud. The six earlier
  palettes and saved aliases remain supported. Selecting colors keeps the skin.
- **Screen skins:** Classic, Glass, Glass Break, Bubbles, Aurora, and Prism.
  These wrap the main home/chat workspace. Selecting a skin keeps the colors.
- **Templates:** eight combinations: Pure & Simple, Ice Glass, Midnight Fracture,
  Bubblegum, Ocean Glass, Mint Bubbles, Northern Lights, and Golden Prism.
  A template selects both colors and wrapper.

The gallery previews changes without applying them. Apply look commits the pair;
closing cancels. Pure & Simple selects Pure White + Classic for a plain white
screen. All Pure White background, panel and input colors are `#FFFFFF`, with dark
text and actions. Core home buttons and the octagonal answer frame use white
fills instead of the earlier bevel/tint. Logos, pictures, and feature-specific
artwork keep their original colors.

## Persistence and behavior

`korlix_appearance_v2` stores the palette and screen skin together in device/browser
preferences. Existing `korlix_ui_theme` values migrate to the same color with
Classic. The previous key is also updated for compatibility. Saving is serialized,
late startup restoration cannot override a new selection, and malformed records
fall back safely. If storage fails, the appearance works for that session and the
UI reports that it was not saved.

The new looks are local to the device/browser; no cross-device synchronization is
promised. Existing server theme synchronization remains best effort for supported
legacy IDs and unchanged server policy. New IDs are not sent to an endpoint that
does not accept them. No migration or backend change is required.

Skins use bounded, deterministic CustomPainter paths and gradients, without
network images, continuous animation, or full-screen blur. Decoration is behind
the content, excluded from accessibility semantics and pointer input. The home
wrapper retains a stable widget structure when changing skins. The existing
octagonal answer frame and official KORLIX branding remain in place. Other feature
screens inherit colors where supported; decorative skins currently wrap the main
home/chat screen.

## Verification

- Shared palette contrast checks cover all 12 palettes.
- A pixel test confirms Pure White + Classic draws an entirely white backdrop.
- Tests cover all 72 palette/skin combinations, functional controls and preserved
  drafts, cancel/apply, template selection, independent color selection, phone
  layouts and enlarged text.
- Persistence tests cover legacy migration, reload, rapid selections, late
  restoration, corrupt records and unavailable storage.
- Local visual review covers the six skins, phone layout, enlarged text and the
  desktop template gallery. These are widget renders, not an authenticated
  production acceptance test.

```sh
flutter test test/korlix_theme_test.dart test/korlix_screen_skins_test.dart \
  test/picture_studio_test.dart test/chat_request_test.dart \
  test/chat_workspace_test.dart test/meeting_copilot
flutter build web --release --base-href /app/ --pwa-strategy=none
```

After deployment, refresh the app. Choose Templates → Pure & Simple → Apply look.
Then try Bubbles or Glass Break in Screen skins, change the color independently,
and refresh to check that the pair returns. A signed-in check on the user's device
remains the final visual acceptance step.
