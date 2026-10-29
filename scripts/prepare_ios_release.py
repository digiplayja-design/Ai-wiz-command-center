#!/usr/bin/env python3
"""Resolve the exact Apple app and a fresh build number before signing."""

import argparse
import json
import re
import subprocess
from pathlib import Path


def select_app(resources, bundle_id, expected_app_id=None):
    if not isinstance(resources, list):
        raise ValueError("Apple app lookup did not return a resource list")
    matches = [
        app for app in resources
        if isinstance(app, dict)
        and app.get("attributes", {}).get("bundleId") == bundle_id
    ]
    if len(matches) != 1:
        raise ValueError(f"Expected one existing App Store Connect record for {bundle_id}; found {len(matches)}")
    app_id = str(matches[0].get("id", ""))
    if not re.fullmatch(r"[0-9]+", app_id):
        raise ValueError("Apple returned an invalid app ID")
    if expected_app_id is not None and app_id != expected_app_id:
        raise ValueError("The Apple app ID does not match the existing release identity")
    return app_id


def source_version(text):
    match = re.search(r"(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$", text)
    if not match or int(match[2]) < 1:
        raise ValueError("pubspec.yaml must specify a release version and positive integer build number")
    return match[1], int(match[2])


def next_build_number(output, source_build, require_existing=False):
    output = output.strip()
    if not output:
        if require_existing:
            raise ValueError("No existing build was found for the previously published app")
        return source_build
    if not re.fullmatch(r"[0-9]+", output):
        raise ValueError("Apple's latest build number is not an integer; review it before releasing")
    return max(source_build, int(output) + 1)


def run_cli(*args):
    # CLI credentials remain in the existing Codemagic integration. Do not log
    # API calls, pass keys on the command line, or turn lookup failures into zero.
    return subprocess.run(
        ["app-store-connect", *args], check=True, text=True, stdout=subprocess.PIPE
    ).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--app-id")
    parser.add_argument("--pubspec", type=Path, default=Path("pubspec.yaml"))
    parser.add_argument("--environment-file", type=Path, required=True)
    parser.add_argument("--require-existing-build", action="store_true")
    args = parser.parse_args()
    version, source_build = source_version(args.pubspec.read_text())
    resources = json.loads(run_cli(
        "apps", "list", "--bundle-id-identifier", args.bundle_id,
        "--strict-match-identifier", "--json",
    ))
    app_id = select_app(resources, args.bundle_id, args.app_id)
    latest = run_cli("get-latest-build-number", app_id, "--platform", "IOS", "--all-versions")
    build = next_build_number(latest, source_build, args.require_existing_build)
    with args.environment_file.open("a") as stream:
        stream.write(f"KORLIX_IOS_APP_ID={app_id}\n")
        stream.write(f"KORLIX_IOS_VERSION={version}\n")
        stream.write(f"KORLIX_IOS_BUILD_NUMBER={build}\n")
    print(f"Verified Apple app {app_id} ({args.bundle_id}); preparing {version} ({build}).")


if __name__ == "__main__":
    main()
