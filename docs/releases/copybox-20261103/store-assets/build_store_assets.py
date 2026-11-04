#!/usr/bin/env python3
"""Build deterministic brand assets and package actual Flutter store captures.

No screenshot is synthesized, resized, padded, or relabeled as another device.
The feature graphic is a branded illustration, not a screenshot. Pillow is the
only dependency. DejaVu Sans is used for its reproducible, locally supplied fonts.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import html
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[4]
SOURCE_ICON = ROOT / "apps/korlix_copy_box/assets/copybox_icon.png"
APPLE_ICON = (
    ROOT
    / "apps/korlix_copy_box/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    / "Icon-App-1024x1024@1x.png"
)
CAPTURE_PROFILES = {
    "play-phone": ("google-play/phone", (1080, 1920)),
    "apple-iphone": ("app-store/iphone", (1206, 2622)),
    "apple-ipad": ("app-store/ipad", (2064, 2752)),
}
STATES = (
    "01-workspace",
    "02-templates",
    "03-focus-editor",
    "04-dark-workspace",
)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save_png(image: Image.Image, path: Path, mode: str = "RGB") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if mode == "RGB" and image.mode == "RGBA":
        if image.getchannel("A").getextrema() != (255, 255):
            raise ValueError(f"Unexpected transparent pixels in {path.name}")
    image.convert(mode).save(path, "PNG", optimize=True)


class FeatureGraphic:
    """Render one layout to an opaque PNG and an editable SVG companion."""

    def __init__(self, font_dir: Path):
        self.scale = 3
        self.font_dir = font_dir
        self.image = Image.new("RGB", (1024 * self.scale, 500 * self.scale), "#E3EEDC")
        self.draw = ImageDraw.Draw(self.image)
        self.svg = [
            '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" '
            'viewBox="0 0 1024 500" role="img" aria-labelledby="title desc">',
            "<title id=\"title\">KORLIX COPY Box</title>",
            '<desc id="desc">Your words. Ready to reuse. A black-and-white KORLIX '
            "emblem with illustrated pastel cards for ideas, replies and templates.</desc>",
            '<rect width="1024" height="500" fill="#E3EEDC"/>',
        ]

    def rounded_rect(self, x, y, width, height, radius, color):
        s = self.scale
        self.draw.rounded_rectangle(
            (x * s, y * s, (x + width) * s, (y + height) * s),
            radius=radius * s,
            fill=color,
        )
        self.svg.append(
            f'<rect x="{x}" y="{y}" width="{width}" height="{height}" '
            f'rx="{radius}" fill="{color}"/>'
        )

    def text(self, x, y, text, size, *, bold=False, color="#161616", tracking=0):
        s = self.scale
        name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
        font = ImageFont.truetype(str(self.font_dir / name), size * s)
        pen_x = x * s
        if tracking:
            for character in text:
                self.draw.text((pen_x, y * s), character, font=font, fill=color)
                pen_x += self.draw.textlength(character, font=font) + tracking * s
        else:
            self.draw.text((pen_x, y * s), text, font=font, fill=color)
        ascent = font.getmetrics()[0] / s
        self.svg.append(
            f'<text x="{x}" y="{y + ascent:g}" font-family="DejaVu Sans,sans-serif" '
            f'font-size="{size}" font-weight="{700 if bold else 400}" '
            f'letter-spacing="{tracking}" fill="{color}">{html.escape(text)}</text>'
        )

    def logo(self, x, y, size):
        s = self.scale
        with Image.open(SOURCE_ICON) as source:
            resized = source.convert("RGB").resize(
                (size * s, size * s), Image.Resampling.LANCZOS
            )
        mask = Image.new("L", resized.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, size * s, size * s), radius=12 * s, fill=255
        )
        self.image.paste(resized, (x * s, y * s), mask)
        encoded = base64.b64encode(SOURCE_ICON.read_bytes()).decode("ascii")
        self.svg.append(
            '<defs><clipPath id="logo-clip">'
            f'<rect x="{x}" y="{y}" width="{size}" height="{size}" rx="12"/>'
            "</clipPath></defs>"
            f'<image x="{x}" y="{y}" width="{size}" height="{size}" '
            f'clip-path="url(#logo-clip)" href="data:image/png;base64,{encoded}"/>'
        )

    def write(self, output: Path):
        # A modest emblem keeps the feature art distinct from the adjacent icon.
        self.logo(72, 72, 48)
        self.text(136, 82, "KORLIX", 15, bold=True, tracking=3)
        self.text(72, 156, "COPY Box", 54, bold=True)
        self.text(72, 250, "Your words.", 29)
        self.text(72, 292, "Ready to reuse.", 29)
        self.text(74, 407, "WRITE. SAVE. REUSE.", 12, bold=True, tracking=1.5)

        cards = [
            (640, 88, "#EDE5F6", "IDEAS", "Keep a bright idea."),
            (612, 204, "#F6EDC6", "REPLIES", "Save your best reply."),
            (584, 320, "#F4E2D6", "TEMPLATES", "Make it yours again."),
        ]
        for x, y, color, label, sentence in cards:
            self.rounded_rect(x, y + 7, 304, 100, 22, "#D1DDCA")
            self.rounded_rect(x, y, 304, 100, 22, color)
            self.text(x + 24, y + 18, label, 10, bold=True, tracking=2)
            self.text(x + 24, y + 45, sentence, 18, bold=True)

        feature = self.image.resize((1024, 500), Image.Resampling.LANCZOS)
        save_png(feature, output / "google-play/feature-graphic.png")
        source_path = output / "source/feature-graphic.svg"
        source_path.parent.mkdir(parents=True, exist_ok=True)
        source_path.write_text("\n".join(self.svg + ["</svg>"]) + "\n")


def build(output: Path, captures: Path | None, font_dir: Path, source_commit: str | None):
    with Image.open(SOURCE_ICON) as source:
        icon = source.convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
    # Play asks for a 32-bit PNG. All pixels remain fully opaque; the RGB
    # companion is provided for pipelines that insist on three channels.
    save_png(icon, output / "google-play/icon-512.png", "RGBA")
    save_png(icon, output / "google-play/icon-512-rgb.png")
    with Image.open(APPLE_ICON) as apple:
        if apple.size != (1024, 1024):
            raise ValueError("Native Apple icon must already be 1024 by 1024")
        save_png(apple, output / "app-store/icon-1024.png")
    FeatureGraphic(font_dir).write(output)

    capture_records = []
    for profile, (folder, size) in CAPTURE_PROFILES.items():
        for state in STATES:
            raw_name = f"store-{profile}-{state}.png"
            relative = f"{folder}/{state}.png"
            record = {
                "file": relative,
                "raw_capture": raw_name,
                "required_dimensions": list(size),
                "status": "pending_capture",
            }
            if captures is not None:
                raw = captures / raw_name
                with Image.open(raw) as screenshot:
                    if screenshot.size != size:
                        raise ValueError(f"{raw_name}: expected {size}, got {screenshot.size}")
                    save_png(screenshot, output / relative)
                record.update(status="packaged", raw_sha256=digest(raw))
            capture_records.append(record)

    inventory = []
    for path in sorted(output.rglob("*.png")):
        with Image.open(path) as image:
            item = {
                "file": str(path.relative_to(output)),
                "dimensions": list(image.size),
                "mode": image.mode,
                "bytes": path.stat().st_size,
                "sha256": digest(path),
            }
            if image.mode == "RGBA":
                item["alpha_extrema"] = list(image.getchannel("A").getextrema())
            inventory.append(item)
    manifest = {
        "app": "KORLIX COPY Box",
        "bundle_id": "com.korlixdeveloper.copybox",
        "locale": "en-US",
        "capture_source_commit": source_commit,
        "capture_method": "Actual Flutter app widgets, controlled sample data, no network",
        "capture_fixture": "apps/korlix_copy_box/test/copybox_preview_test.dart",
        "native_device_acceptance": False,
        "source_icon_sha256": digest(SOURCE_ICON),
        "source_apple_icon_sha256": digest(APPLE_ICON),
        "feature_graphic_kind": "Branded illustration; not a screenshot or device mockup",
        "screenshots": capture_records,
        "files": inventory,
        "official_specifications": [
            "https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications",
            "https://support.google.com/googleplay/android-developer/answer/9866151?hl=en",
        ],
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"output": str(output), "pngs": len(inventory), "screenshots_packaged": captures is not None}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--captures", type=Path, help="Directory containing raw store-*.png CI captures")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--font-dir", type=Path, default=Path("/usr/share/fonts/truetype/dejavu"))
    parser.add_argument("--source-commit", help="Exact commit rendered in the capture CI run")
    args = parser.parse_args()
    build(args.output.resolve(), args.captures, args.font_dir, args.source_commit)


if __name__ == "__main__":
    main()
