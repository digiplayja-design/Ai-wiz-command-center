#!/usr/bin/env python3
"""Check Esha's source identity and pinned SDK without accessing credentials."""

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "apps/esha"
BUNDLE_ID = "com.korlixdeveloper.esha"


def main():
    expected_flutter = (ROOT / "scripts/esha/flutter-version").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", expected_flutter):
        raise ValueError("scripts/esha/flutter-version must pin an exact stable version")
    actual = json.loads(subprocess.check_output(
        ["flutter", "--suppress-analytics", "--no-version-check", "--version", "--machine"],
        text=True,
    ))["frameworkVersion"]
    if actual != expected_flutter:
        raise ValueError(f"Esha requires Flutter {expected_flutter}; found {actual}")
    gradle = (APP / "android/app/build.gradle.kts").read_text()
    if not re.search(r'applicationId\s*=\s*"' + re.escape(BUNDLE_ID) + r'"', gradle):
        raise ValueError("Android applicationId must be the separate Esha identity")
    if re.search(r'signingConfig\s*=\s*signingConfigs(?:\.getByName\("debug"\)|\.debug)', gradle):
        raise ValueError("The release configuration must never fall back to a debug key")
    project = (APP / "ios/Runner.xcodeproj/project.pbxproj").read_text()
    identifiers = [value.strip().strip('"') for value in
                   re.findall(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);', project)]
    if BUNDLE_ID not in identifiers:
        raise ValueError("The iOS project does not include Esha's bundle identifier")
    if any(identifier not in {BUNDLE_ID, BUNDLE_ID + ".RunnerTests"} for identifier in identifiers):
        raise ValueError("The Esha Xcode project contains another app's bundle identifier")
    if (APP / "android/key.properties").exists():
        raise ValueError("Remove android/key.properties; Esha release signing must use its CI identity")
    if not (APP / "pubspec.lock").is_file():
        raise ValueError("Commit apps/esha/pubspec.lock before building")
    print(f"Verified Esha source identity and Flutter {expected_flutter}.")


if __name__ == "__main__":
    main()
