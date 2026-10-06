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

## Smoke screensaver

The app-wide smoke layer appears after 30 seconds without touch, mouse,
scrolling, keyboard or text-edit activity. It is enabled by default. The
appearance picker has a device-local switch and a Preview smoke action;
previewing does not change the saved switch. The preference is stored under
`korlix_smoke_screensaver_v1` with serialized writes and stale-restore protection.

The revised effect rises from the bottom over the unchanged live screen. Icons,
text and cards stay visible through the billows: there is no full-screen tint,
background blur, center wordmark or replacement screen. Only the smoke is
softened. Plumes expand, curl and dissipate as they rise; their combined opacity
is capped at 46%, including overlaps. Tablet plumes keep finer detail instead
of scaling into a broad fog.

The first tap, scroll or keypress wakes the app without activating the control
underneath. The existing navigator stays mounted, preserving drafts, podcast
playback and calls. Incoming social alerts and the active-call bar remain above
the smoke. Navigation, account changes and backgrounding clear it; returning
to the foreground starts a fresh idle interval. It does not override the
device's screen-lock settings.

Smoke is drawn locally with bounded particle and ribbon counts. Its ticker
exists only while visible and is capped at 25 updates per second. Reduced
motion uses a still image. Automatic activation is disabled when accessible
navigation is enabled, while the manual preview remains available with an
accessible dismiss action.

Validation: static analysis reported no issues; the combined screensaver,
appearance, podcast and remembered-login suite passed 100 tests, with one
unrelated optional appearance-image export skipped. Checks include exact idle
timing, held input, first-event swallowing, draft/focus restoration, lifecycle
and route changes, saved settings, reduced motion and continued playback for
two- and three-person podcasts. Phone and tablet smoke renders were reviewed.
These checks use Flutter test rendering and mocked media, not physical devices.

```bash
CI=true flutter test --no-pub test/korlix_smoke_screensaver_test.dart test/pod_screen_test.dart
```

Set `KORLIX_SMOKE_PREVIEWS` to export phone and tablet smoke review images.
Set `KORLIX_FLUTTER_ROOT` to load the SDK's Material icon font for those images.
The transparent rising-smoke revision passed 57 screensaver/podcast checks;
the final tablet density adjustment passed all 12 screensaver checks again.
The export captures the original screen and frames at 3, 8 and 14 seconds;
phone and tablet frames were reviewed in dark and light themes. Static
analysis reported no issues for the changed code.
