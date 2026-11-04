# COPY Box store assets

## Prepared upload set

The sixteen screenshots render the real Flutter UI with nonsensitive fixture
text. They are packaged as opaque RGB PNGs at the exact dimensions below, with
native proportions and no stretched replacement layouts. Pixel dimensions below
describe the prepared upload files, not logical Flutter viewports.

| Destination | Final dimensions | Content |
| --- | --- | --- |
| Google Play phone | 1080 × 1920 | Workspace, templates, focus editor, dark workspace |
| Apple iPhone with Dynamic Island, required medium | 1206 × 2622 | Same four actual states in the required iPhone layout |
| Apple iPhone with Dynamic Island, optional large | 1260 × 2736 | Same four actual states in the existing large iPhone layout |
| Apple iPad 13-inch | 2064 × 2752 | Same four states in the tablet layout |
| Google Play feature graphic | 1024 × 500 | Clean branded illustration with the KORLIX emblem and writing-card colors; no rank, price, download-count or availability claims |
| Google Play icon | 512 × 512 | The approved black-and-white KORLIX emblem; 32-bit PNG with an opaque alpha channel, under 1 MiB |
| Apple app icon | 1024 × 1024 | Existing opaque black-and-white icon in the iOS asset catalog |

The live App Store Connect Media Manager for app `6830765098`, observed on
November 4, 2026, requires **iPhone with Dynamic Island (medium display)** and
accepts 1179 × 2556 or 1206 × 2622 portrait images. This package now supplies four
1206 × 2622 images in `app-store/iphone-medium/`. The existing 1260 × 2736 large
Dynamic Island group is optional. COPY Box also supports iPad; the existing
2064 × 2752 13-inch iPad group remains suitable. Four images per group keep the
same feature sequence across all sixteen captures.
After uploading the large group, a follow-up console check showed “Using Existing
Assets” in the medium well. The dedicated medium captures are also available for
direct upload; the console's displayed fallback does not require altering the
original large images.
[Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)

Google requires at least two screenshots, with dimensions from 320 to 3840 and
the longer side at most twice the shorter. Four 1080 × 1920 phone images also
meet its stated screenshot-format recommendation. Screenshots and feature
graphics cannot contain alpha; the upload icon uses the separate 32-bit icon
format. The feature graphic is 1024 × 500.
[Google preview assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)

The console's available size wells and validation remain authoritative at upload.
The required medium iPhone layout was rendered at 402 × 874 logical pixels with
a 3× output scale to produce 1206 × 2622 pixels. The optional large layout uses
420 × 912 at 3× to produce 1260 × 2736 pixels. Neither layout was resized.

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
| Apple iPhone, required medium | `app-store/iphone-medium/` | The same four numbered filenames |
| Apple iPhone, optional large | `app-store/iphone/` | The same four numbered filenames |
| Apple iPad | `app-store/ipad/` | The same four numbered filenames |

The generated Play assets are `google-play/icon-512.png` and
`google-play/feature-graphic.png`. The Apple reference icon is
`app-store/icon-1024.png`. `google-play/icon-512-rgb.png` is an RGB companion,
while the 32-bit `icon-512.png` is the designated Play upload icon.

## Earlier previews: unsuitable for direct store upload

Measured existing files in `../previews/`:

| File | Current properties | Gap |
| --- | --- | --- |
| `copybox-workspace.png` | 1170 × 2532, RGBA | Has an alpha channel; ratio exceeds Google's 2:1 limit; does not fill the current required medium iPhone screenshot well. |
| `copybox-templates.png` | 1170 × 2532, RGBA | Same gaps as the workspace image. |
| `copybox-desktop-dark.png` | 3840 × 2700, RGBA | A generic large-window layout, not a required iPad-size capture; has an alpha channel. |

The native Apple icon already exists at
`apps/korlix_copy_box/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`
as a 1024 × 1024 RGB image (601,158 bytes in the inspected source). The original
1254 × 1254 app-branding image is not itself a Play upload icon.

## Provenance and acceptance

The original twelve screenshots have source
`d611bc6a1b5c8b6d7e3805725c6d7c5fe617f7e4`, captured in
[run 10](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41844773126).
Those twelve screenshots are packaged and visually reviewed; the three focus
editor captures include the corrected top-aligned text. The manifest records
each file's dimensions, color mode, byte size and SHA-256 checksum. The separate
[asset record](../store-assets/README.md) describes reproduction and format checks.

The four additional medium iPhone screenshots were rendered at
`339e41f055882a24e35cd43ea39b273c1ff960a4` in
[focused run 41872257288](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/41872257288).
The capture-only commit adds the medium viewport and a dedicated workflow without
changing app behavior. These four screens were visually checked and appended
with per-record capture provenance. All original sixteen PNG assets remain
byte-for-byte unchanged; the package now contains sixteen screenshots and twenty
PNG files in total.

These widget-rendered captures establish the implemented layouts. They do not
establish physical-device or live-account acceptance, native permission behavior,
or system share-sheet behavior. Store upload status and signed-release acceptance
are recorded separately; this asset package does not establish store submission.
