# COPY Box store visual assets

## Current status

The icons, feature graphic, and all twelve store screenshots are generated,
format-checked, and visually reviewed. The final screenshots come from COPY Box
validation run 10 at source commit
`d611bc6a1b5c8b6d7e3805725c6d7c5fe617f7e4`. `manifest.json` records that exact
capture source, the raw capture hashes, and every packaged file's dimensions,
color mode, byte count, and SHA-256 hash.

All sixteen PNG files were fully decoded and checked after the atomic packaging
process completed. Each screenshot preserves its raw capture's RGB pixels
exactly, with no alpha channel, resizing, padding, or cropping. The three final
focus-editor screenshots were inspected after the text alignment fix; the other
nine screenshots are pixel-identical to the previously reviewed captures. The
icon and feature-graphic hashes remain unchanged.

These are actual Flutter widget renders with sample content, not physical-device
acceptance. These assets have not been uploaded to either store.

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
| Apple iPhone with Dynamic Island, large display | `app-store/iphone/*.png` | 1260 × 2736, 24-bit RGB PNG |
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
`COPYBOX_PREVIEWS` and `KORLIX_FLUTTER_ROOT` and runs the new fixture with all tests.
To run just the capture fixture in that configured CI environment:

```sh
cd apps/korlix_copy_box
flutter test --no-pub --reporter expanded test/copybox_preview_test.dart
```

The fixture emits `store-play-phone-*.png`, `store-apple-iphone-*.png`, and
`store-apple-ipad-*.png` into `COPYBOX_PREVIEWS`. Its three capture sizes are
360 × 640 at 3×, 420 × 912 at 3×, and 1032 × 1376 at 2×. It checks exact physical
pixel sizes and reports any Flutter layout exception. The raw PNGs have an alpha
channel; packaging requires every pixel to be opaque and removes the channel.
Screenshots are not stretched, resized, padded, or cropped during packaging.

From the repository root, after downloading the CI screenshot artifact:

```sh
python3 docs/releases/copybox-20261103/store-assets/build_store_assets.py \
  --captures /absolute/path/to/copybox-previews \
  --source-commit THE_EXACT_CI_COMMIT
```

Without `--captures`, the script rebuilds only the icons/feature graphic and
marks the expected screenshots pending. The script requires Pillow and DejaVu
Sans; `--font-dir` selects another directory containing the same font files.
The manifest records source icon hashes, per-file dimensions, modes, byte sizes,
checksums, and capture provenance. Visually review each output before uploading.

## Official specifications checked

- [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications):
  this set supplies the large Dynamic Island display size; Apple requires the
  large Face ID fallback when a large Dynamic Island set is not provided. iPad
  support also needs a 13-inch iPad capture. Images must have no alpha channel.
- [Google Play preview assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en):
  a 512 × 512 32-bit app icon; 1024 × 500 feature graphic without alpha; opaque
  screenshots with a long side at most twice the short side. Four 1080 × 1920
  phone screenshots also meet the stated recommendation format.

These are rendered interface captures and format checks, not physical-device
acceptance, store approval, or evidence of a signed release.
