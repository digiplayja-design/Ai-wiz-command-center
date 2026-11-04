# COPY Box store assets

## Prepared upload set

The twelve screenshots render the real Flutter UI with nonsensitive fixture
text. They are packaged as opaque RGB PNGs at the exact dimensions below, with
native proportions and no stretched replacement layouts. Pixel dimensions below
describe the prepared upload files, not logical Flutter viewports.

| Destination | Final dimensions | Content |
| --- | --- | --- |
| Google Play phone | 1080 × 1920 | Workspace, templates, focus editor, dark workspace |
| Apple iPhone with Dynamic Island, large | 1260 × 2736 | Same four actual states in an iPhone layout |
| Apple iPad 13-inch | 2064 × 2752 | Same four states in the tablet layout |
| Google Play feature graphic | 1024 × 500 | Clean branded illustration with the KORLIX emblem and writing-card colors; no rank, price, download-count or availability claims |
| Google Play icon | 512 × 512 | The approved black-and-white KORLIX emblem; 32-bit PNG with an opaque alpha channel, under 1 MiB |
| Apple app icon | 1024 × 1024 | Existing opaque black-and-white icon in the iOS asset catalog |

Apple's required iPhone coverage is a large Dynamic Island set or a large Face
ID set. This package uses the large Dynamic Island size of 1260 × 2736. Universal
apps also require 13-inch iPad images; COPY Box targets both device families.
Apple accepts 1–10 images per size. Four images per family keep the same feature
sequence across all twelve captures.
[Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)

Google requires at least two screenshots, with dimensions from 320 to 3840 and
the longer side at most twice the shorter. Four 1080 × 1920 phone images also
meet its stated screenshot-format recommendation. Screenshots and feature
graphics cannot contain alpha; the upload icon uses the separate 32-bit icon
format. The feature graphic is 1024 × 500.
[Google preview assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)

The console's available size wells and validation remain authoritative at upload.
The iPhone layout was rendered at 420 × 912 logical pixels with a 3× output scale
to produce the selected 1260 × 2736 upload size without resizing the UI.

## Image sequence and accessible descriptions

These captions are metadata suggestions, not claims that text is overlaid on the
screenshots. Alt text is intentionally short and describes visible UI.

| Order | State | Optional caption | Alt text |
| --- | --- | --- | --- |
| 1 | Workspace | Keep useful words close | Colored writing boxes with titles, folders, favorite stars and per-box text controls. |
| 2 | Templates | Start with a useful draft | Reusable writing templates with named fields and Use template controls. |
| 3 | Focus editor | Make room for the next thought | Expanded text editor with a draft, character count and Save & close control. |
| 4 | Dark workspace | Choose your writing space | Dark writing workspace with saved text, folder labels, favorite stars and copying controls. |

The prepared states use fixture writing and do not show invented live AI results,
customer content or account credentials.

The [asset manifest](../store-assets/manifest.json) uses these exact packaged paths
relative to `../store-assets/`:

| Store group | Directory | Four image filenames |
| --- | --- | --- |
| Google phone | `google-play/phone/` | `01-workspace.png`, `02-templates.png`, `03-focus-editor.png`, `04-dark-workspace.png` |
| Apple iPhone | `app-store/iphone/` | The same four numbered filenames |
| Apple iPad | `app-store/ipad/` | The same four numbered filenames |

The generated Play assets are `google-play/icon-512.png` and
`google-play/feature-graphic.png`. The Apple reference icon is
`app-store/icon-1024.png`. `google-play/icon-512-rgb.png` is an RGB companion,
while the 32-bit `icon-512.png` is the designated Play upload icon.

## Earlier previews: unsuitable for direct store upload

Measured existing files in `../previews/`:

| File | Current properties | Gap |
| --- | --- | --- |
| `copybox-workspace.png` | 1170 × 2532, RGBA | Has an alpha channel; ratio exceeds Google's 2:1 limit; does not fill the required large iPhone screenshot well. |
| `copybox-templates.png` | 1170 × 2532, RGBA | Same gaps as the workspace image. |
| `copybox-desktop-dark.png` | 3840 × 2700, RGBA | A generic large-window layout, not a required iPad-size capture; has an alpha channel. |

The native Apple icon already exists at
`apps/korlix_copy_box/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`
as a 1024 × 1024 RGB image (601,158 bytes in the inspected source). The original
1254 × 1254 app-branding image is not itself a Play upload icon.

## Provenance and acceptance

The final screenshot source is
`d611bc6a1b5c8b6d7e3805725c6d7c5fe617f7e4`, captured in
[run 10](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41844773126).
All twelve screenshots are packaged and visually reviewed; the three focus
editor captures include the corrected top-aligned text. The manifest records
each file's dimensions, color mode, byte size and SHA-256 checksum. The separate
[asset record](../store-assets/README.md) describes reproduction and format checks.

These widget-rendered captures establish the implemented layouts. They do not
establish physical-device or live-account acceptance, native permission behavior,
or system share-sheet behavior. The prepared media has not been uploaded to
either store, and no signed release or store submission is claimed here.
