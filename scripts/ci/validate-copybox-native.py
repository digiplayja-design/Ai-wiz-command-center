#!/usr/bin/env python3
"""Check Copy Box's independent native identity, permissions, and store assets.

Uses only Python's standard library; no network, SDK, or signing secrets needed.
"""
from __future__ import annotations

import json
from pathlib import Path
import plistlib
import re
import struct
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "apps" / "korlix_copy_box"
ANDROID = "{http://schemas.android.com/apk/res/android}"
TOOLS = "{http://schemas.android.com/tools}"
PACKAGE = "com.korlixdeveloper.copybox"
errors: list[str] = []


def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def png_size(path: Path) -> tuple[int, int]:
    try:
        header = path.read_bytes()[:26]
        if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
            raise ValueError("not a PNG")
        return struct.unpack(">II", header[16:24])
    except (OSError, ValueError, struct.error) as error:
        errors.append(f"Cannot read PNG {path.relative_to(ROOT)}: {error}")
        return (0, 0)


def read_plist(relative: str) -> dict:
    with (APP / relative).open("rb") as source:
        return plistlib.load(source)


manifest = ET.parse(APP / "android/app/src/main/AndroidManifest.xml").getroot()
permissions = {
    item.get(ANDROID + "name")
    for item in manifest.findall("uses-permission")
    if item.get(TOOLS + "node") != "remove"
}
require(permissions == {"android.permission.INTERNET"},
        f"Unexpected Android app permissions: {permissions}")
application = manifest.find("application")
require(application is not None, "Missing Android application")
if application is not None:
    require(application.get(ANDROID + "label") == "KORLIX COPY Box",
            "Incorrect Android display name")
    require(application.get(ANDROID + "allowBackup") == "false",
            "Snippet backups must be explicitly controlled")
    require(application.get(ANDROID + "usesCleartextTraffic") == "false",
            "Android cleartext traffic must stay disabled")

gradle = (APP / "android/app/build.gradle.kts").read_text()
require(f'namespace = "{PACKAGE}"' in gradle, "Wrong Android namespace")
require(f'applicationId = "{PACKAGE}"' in gradle, "Wrong Android application ID")
require('signingConfigs.getByName("debug")' not in gradle,
        "A release build must never use debug signing")
require("KORLIX_COPYBOX_ANDROID_STORE_FILE" in gradle,
        "Missing dedicated Copy Box Android signing configuration")
require("copyBoxSigningReady" in gradle, "Missing release signing guard")

project = (APP / "ios/Runner.xcodeproj/project.pbxproj").read_text()
identifiers = set(re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", project))
require(identifiers == {PACKAGE, PACKAGE + ".RunnerTests"},
        f"Unexpected iOS bundle identifiers: {identifiers}")
require("PrivacyInfo.xcprivacy in Resources" in project,
        "Privacy manifest is not included in the iOS app resources")
require(not re.search(r"PROVISIONING_PROFILE_SPECIFIER = \"?[^\";]+", project),
        "Remove fixed provisioning profiles from portable project source")

info = read_plist("ios/Runner/Info.plist")
require(info.get("CFBundleDisplayName") == "KORLIX COPY Box", "Wrong iOS display name")
require(info.get("CFBundleIdentifier") == "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "iOS bundle identifier must derive from the independent target")
require(not any(key.startswith("NS") and key.endswith("UsageDescription")
                for key in info), "Copy Box must not declare unused protected device access")
privacy = read_plist("ios/Runner/PrivacyInfo.xcprivacy")
require(privacy.get("NSPrivacyTracking") is False, "Copy Box must not declare tracking")
required_reasons = privacy.get("NSPrivacyAccessedAPITypes", [])
require(any(item.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryUserDefaults"
            and "CA92.1" in item.get("NSPrivacyAccessedAPITypeReasons", [])
            for item in required_reasons), "Missing UserDefaults required API reason CA92.1")

icons = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for item in json.loads((icons / "Contents.json").read_text())["images"]:
    size = round(float(item["size"].split("x")[0]) * float(item["scale"][:-1]))
    path = icons / item["filename"]
    require(png_size(path) == (size, size), f"Wrong iOS icon size: {item['filename']}")
    if path.is_file():
        require(path.read_bytes()[25] not in (4, 6),
                f"App Store icon must not contain an alpha channel: {item['filename']}")

for density, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                      ("xxhdpi", 144), ("xxxhdpi", 192)]:
    path = APP / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"
    require(png_size(path) == (size, size), f"Wrong Android {density} launcher icon")
for size in (192, 512):
    for prefix in ("Icon", "Icon-maskable"):
        path = APP / f"web/icons/{prefix}-{size}.png"
        require(png_size(path) == (size, size), f"Wrong web icon size: {path.name}")

for folder in (APP / "android", APP / "ios", APP / "web"):
    for path in folder.rglob("*"):
        if path.suffix in (".xml", ".plist", ".xcprivacy", ".storyboard"):
            try:
                ET.parse(path)
            except ET.ParseError as error:
                errors.append(f"Invalid platform XML: {path.relative_to(APP)}: {error}")

if errors:
    print("Copy Box native validation failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)
print("Copy Box native validation passed: independent IDs, dedicated signing, "
      "permissions, privacy manifest, platform XML, and icon dimensions.")
