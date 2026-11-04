# COPY Box store visual assets

## Current status

The icons, feature graphic, and all sixteen store screenshots are generated,
format-checked, and visually reviewed. The original twelve screenshots come from
COPY Box validation run 10 at source commit
`d611bc6a1b5c8b6d7e3805725c6d7c5fe617f7e4`. Four medium iPhone screenshots were
added on November 4, 2026, by the
[focused capture run](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41872257288)
at `339e41f055882a24e35cd43ea39b273c1ff960a4`.

`manifest.json` retains the original capture commit as the default for records
without a source override. Each medium iPhone record supplies its own exact
capture commit and run URL. The manifest also records raw capture hashes and
every packaged file's dimensions, color mode, byte count, and SHA-256 hash.

All twenty PNG files are fully decoded and format-checked. Each screenshot
preserves its raw capture's RGB pixels exactly, with no alpha channel, resizing,
padding, or cropping. The additional four screens were visually inspected;
all sixteen original PNG files, including the icons and feature graphic, remain
byte-for-byte unchanged.

These are actual Flutter widget renders with sample content. Store uploads,
physical-device acceptance, and signed-release acceptance are recorded separately.

The feature graphic is a branded illustration built from the existing
black-and-white KORLIX emblem and COPY Box's pastel card colors. Its editable SVG
and deterministic renderer are included. It does not pretend to show app controls.
The screenshots render the actual shipping Flutter widgets with sample writing,
the app fonts, and the appropriate Android/iOS theme platform. They contain no
customer information, credentials, invented AI responses, device frames, or
operating-system status bars.

## Upload mapping

| Store slot | Prepared path | Dimensions / format |
| --- | --- | --- |
| Google Play app icon | `google-play/icon-512.png` | 512 × 512, opaque 32-bit RGBA PNG |
| RGB icon companion | `google-play/icon-512-rgb.png` | 512 × 512, 24-bit RGB PNG |
| Google Play feature graphic | `google-play/feature-graphic.png` | 1024 × 500, 24-bit RGB PNG |
| Google Play phone screenshots | `google-play/phone/*.png` | 1080 × 1920, 24-bit RGB PNG |
| Apple app icon reference | `app-store/icon-1024.png` | 1024 × 1024, 24-bit RGB PNG; matches native app icon |
| Apple iPhone with Dynamic Island, required medium display | `app-store/iphone-medium/*.png` | 1206 × 2622, 24-bit RGB PNG |
| Apple iPhone with Dynamic Island, optional large display | `app-store/iphone/*.png` | 1260 × 2736, 24-bit RGB PNG |
| Apple iPad 13-inch display | `app-store/ipad/*.png` | 2064 × 2752, 24-bit RGB PNG |

Each device set has these four screenshots in order:

1. `01-workspace.png`: Saved writing, folders, favorites and per-box actions.
2. `02-templates.png`: The actual reusable template collection.
3. `03-focus-editor.png`: The focused writing screen with explicit save/close.
4. `04-dark-workspace.png`: The same writing workspace in dark appearance.

Phone workspace captures are scrolled to the saved writing. iPad captures retain
the heading and navigation rail because the layout has more space. This is the
same UI a user reaches by scrolling, with no composited replacement UI.

## Reproduce

Use the existing isolated GitHub validation runner. Do not rerun the blocked
local Flutter bootstrap. The normal COPY Box validation workflow already sets
`COPYBOX_PREVIEWS` and `KORLIX_FLUTTER_ROOT`. To reproduce the original capture
fixture in that configured CI environment:

```sh
cd apps/korlix_copy_box
flutter test --no-pub --reporter expanded test/copybox_preview_test.dart
```

The original fixture emits `store-play-phone-*.png`, `store-apple-iphone-*.png`,
and `store-apple-ipad-*.png` into `COPYBOX_PREVIEWS`. Its three capture sizes are
360 × 640 at 3×, 420 × 912 at 3×, and 1032 × 1376 at 2×. It checks exact physical
pixel sizes and reports any Flutter layout exception. The raw PNGs have an alpha
channel; packaging requires every pixel to be opaque and removes the channel.
Screenshots are not stretched, resized, padded, or cropped during packaging.

From the repository root, after downloading the original CI screenshot artifact,
use a separate output directory so the combined manifest remains intact:

```sh
python3 docs/releases/copybox-20261103/store-assets/build_store_assets.py \
  --captures /absolute/path/to/copybox-previews \
  --output /absolute/path/to/rebuilt-original-assets \
  --source-commit THE_EXACT_CI_COMMIT
```

Without `--captures`, the script rebuilds only the icons/feature graphic and
marks the expected screenshots pending. The script requires Pillow and DejaVu
Sans; `--font-dir` selects another directory containing the same font files.
The manifest records source icon hashes, per-file dimensions, modes, byte sizes,
checksums, and capture provenance. Visually review each output before uploading.

### Additional medium iPhone captures

The medium profile and dedicated capture workflow are preserved at
[`339e41f055882a24e35cd43ea39b273c1ff960a4`](https://github.com/digiplayja-design/Ai-wiz-command-center/commit/339e41f055882a24e35cd43ea39b273c1ff960a4)
on `capture/copybox-medium-20261104`. That commit changes only the capture fixture
and adds a focused workflow; application behavior and native configuration are
unchanged from its parent `4dd07806ff471263b1fb82d593f300cfe9693a4d`.

In an isolated checkout of that capture commit, run only the additional profile:

```sh
cd apps/korlix_copy_box
flutter test --no-pub --reporter expanded test/copybox_preview_test.dart \
  --plain-name 'apple-iphone-medium store screenshots'
```

The configured workflow uses Flutter 3.47.7 and the committed dependency lockfile.
It sets the capture/font environment variables and emits the four
`store-apple-iphone-medium-*.png` files from a 402 × 874 logical viewport at 3×.
No unrelated tests or app builds run in this workflow.

The four files were appended using the existing `save_png`, `digest`, and
`atomic_write` helpers, after confirming exact dimensions and full opacity.
Packaging removed only the opaque alpha channel and verified equality of the
raw and packaged RGB pixels. Existing image hashes were checked before and after
the append. Do not run the full `build()` operation against this combined output
with only the four additional captures: it expects the original profiles and
replaces the manifest. Preserve the original manifest entries and use explicit
per-record source overrides when appending another capture batch.

## Official specifications checked

- [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications):
  the live App Store Connect Media Manager for app `6830765098`, observed on
  November 4, 2026, requires the medium Dynamic Island iPhone group and accepts
  1179 × 2556 or 1206 × 2622 portrait images. This package supplies 1206 × 2622.
  After the large group was uploaded, a follow-up console check showed
  “Using Existing Assets” in the medium well. The dedicated medium files are
  also available for direct upload. The existing 1260 × 2736 large group is
  optional. The 2064 × 2752 iPad 13-inch
  group remains suitable. Images have no alpha channel; the console's current
  size wells and validation determine upload acceptance.
- [Google Play preview assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en):
  a 512 × 512 32-bit app icon; 1024 × 500 feature graphic without alpha; opaque
  screenshots with a long side at most twice the short side. Four 1080 × 1920
  phone screenshots also meet the stated recommendation format.

These are rendered interface captures and format checks, not physical-device
acceptance, store approval, or evidence of a signed release.
