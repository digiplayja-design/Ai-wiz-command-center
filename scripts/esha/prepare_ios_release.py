#!/usr/bin/env python3
"""Read-only preflight for the separately configured Esha Apple app and profile."""

import argparse
import json
import os
import plistlib
import re
import subprocess
from pathlib import Path

from verify_artifact import BUNDLE_ID, command, verify_profile


def app_store(*arguments):
    # The existing Codemagic integration supplies credentials in the build
    # environment. Never serialize those credentials or put them in arguments.
    return subprocess.run(
        ["app-store-connect", *arguments], check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    ).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment-file", required=True, type=Path)
    args = parser.parse_args()
    app_id = os.environ.get("ESHA_APP_STORE_ID", "")
    if not re.fullmatch(r"[0-9]+", app_id):
        raise ValueError("Configure ESHA_APP_STORE_ID with Esha's own existing App Store Connect record")
    profile_path = os.environ.get("ESHA_APP_STORE_PROFILE_PATH", "")
    if not profile_path or not Path(profile_path).is_file():
        raise ValueError("Configure the Esha-specific ESHA_APP_STORE_PROFILE in Codemagic")
    profile = plistlib.loads(command("security", "cms", "-D", "-i", profile_path, binary=True))
    verify_profile(profile, os.environ.get("ESHA_APPLE_TEAM_ID", ""))
    resources = json.loads(app_store(
        "apps", "list", "--bundle-id-identifier", BUNDLE_ID,
        "--strict-match-identifier", "--json",
    ))
    if not isinstance(resources, list):
        raise ValueError("The Apple app lookup did not return a list")
    matches = [app for app in resources if isinstance(app, dict)
               and app.get("attributes", {}).get("bundleId") == BUNDLE_ID]
    if len(matches) != 1 or str(matches[0].get("id")) != app_id:
        raise ValueError("ESHA_APP_STORE_ID must match the separate Esha bundle in the configured Apple account")
    pubspec = Path(__file__).resolve().parents[2] / "apps/esha/pubspec.yaml"
    version = re.search(r"(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$", pubspec.read_text())
    if not version or int(version[2]) < 1:
        raise ValueError("Esha pubspec must contain a release version and positive build number")
    latest = app_store("get-latest-build-number", app_id, "--platform", "IOS", "--all-versions").strip()
    if latest and not re.fullmatch(r"[0-9]+", latest):
        raise ValueError("Apple's latest build number could not be verified; review it manually")
    build = max(int(version[2]), int(latest) + 1 if latest else 1)
    with args.environment_file.open("a") as stream:
        stream.write(f"ESHA_IOS_VERSION={version[1]}\n")
        stream.write(f"ESHA_IOS_BUILD_NUMBER={build}\n")
    print(f"Verified the separate Esha Apple app and profile; candidate version {version[1]} ({build}).")


if __name__ == "__main__":
    main()
