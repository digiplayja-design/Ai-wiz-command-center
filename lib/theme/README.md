# KORLIX appearance studio

The home shortcuts and account appearance action open the same picker. Color
themes and screen skins remain independent. The 18 curated templates select a
pair; the existing saved appearance record and legacy theme aliases still work.

There are 12 palettes and 10 skins (120 combinations). Color Mesh, Contour,
Orbit and Linen join Classic, Glass, Glass Break, Bubbles, Aurora and Prism.
Frames now vary their corners, edge treatment and shading with the selected
skin. Backdrops use bounded static drawing behind an IgnorePointer. They do
not add animations, network assets or an extra layer that intercepts controls.
Pure White + Classic remains entirely white.

The gallery shows two cards per row where width and text size allow. Enlarged
text switches to a single column. Search, light/dark filters and a Saved view
help find looks. The larger sample can preview Home or Chat; the eye control
returns to it from the gallery. Reset returns to the appearance present when
the picker opened. Closing discards the preview. Only Apply returns the choice
to the existing home appearance-saving flow.

Bookmarks use the device-local `korlix_saved_looks_v1` preference, separate from
the applied appearance. They can include any custom palette/skin combination.
Writes are serialized, stale restoration cannot overwrite a new bookmark,
invalid entries are ignored, and storage failures leave the current visit
usable with a visible notice. These favorites do not sync between devices.

Validation for the October 6, 2026 update: 36 Flutter tests passed, including all
120 combinations preserving typed drafts and working controls, theme contrast,
preview cancellation, Apply, reset, favorites reload, filtering and keyboard
clearance. Responsive checks cover 320px/390px phones, landscape and iPad-size
layouts, including 1.8x text. Four rendered review screens were inspected.
These are automated/rendered checks, not physical-device verification.

Run the appearance checks:

```bash
CI=true flutter test --no-pub test/korlix_screen_skins_test.dart test/korlix_theme_test.dart test/korlix_appearance_studio_test.dart
```

The optional visual-export case uses `KORLIX_APPEARANCE_PREVIEWS` for its output
directory and `KORLIX_FLUTTER_ROOT` to load the SDK's Material icon font. Without
those variables, that one export test is skipped. Existing installed mobile
apps need a new build to include the appearance update.
