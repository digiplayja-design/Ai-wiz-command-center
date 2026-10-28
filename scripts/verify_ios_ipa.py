#!/usr/bin/env python3
"""Check exported IPA identity and App Store profile before Apple upload."""

import argparse
import hashlib
import json
import plistlib
import subprocess
import tempfile
import zipfile
from pathlib import Path


def verify_info(info, bundle_id, version, build):
    expected = {
        "CFBundleIdentifier": bundle_id,
        "CFBundleShortVersionString": version,
        "CFBundleVersion": str(build),
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f"Exported IPA {key} does not match the requested release")
    if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise ValueError("The artifact is not an iPhoneOS device build")
    return expected


def verify_profile(profile, bundle_id):
    entitlements = profile.get("Entitlements", {})
    if entitlements.get("get-task-allow") is not False:
        raise ValueError("The exported profile permits debugging or omits its debug entitlement")
    if "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices"):
        raise ValueError("An App Store distribution profile is required")
    identifier = entitlements.get("application-identifier", "")
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    if identifier not in {f"{prefix}.{bundle_id}" for prefix in prefixes}:
        raise ValueError("The provisioning profile does not match the app bundle identifier")


def verify_signed_entitlements(entitlements, profile, info, require_push):
    allowed = profile["Entitlements"]
    if entitlements.get("application-identifier") != allowed.get("application-identifier"):
        raise ValueError("The signed app identity does not match the provisioning profile")
    if entitlements.get("get-task-allow") is not False:
        raise ValueError("The signed application permits debugging")
    if require_push and (
        entitlements.get("aps-environment") != "production"
        or allowed.get("aps-environment") != "production"
        or info.get("KorlixAPNsEnvironment") != "production"
    ):
        raise ValueError("Messenger requires matching production APNs configuration, profile, and signed entitlement")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--require-push", action="store_true")
    args = parser.parse_args()
    with zipfile.ZipFile(args.ipa) as archive:
        infos = [name for name in archive.namelist()
                 if name.startswith("Payload/") and name.endswith(".app/Info.plist")
                 and name.count("/") == 2]
        if len(infos) != 1:
            raise ValueError("Expected exactly one application in the IPA")
        info = plistlib.loads(archive.read(infos[0]))
        identity = verify_info(info, args.bundle_id, args.version, args.build)
        profile_data = archive.read(infos[0].replace("Info.plist", "embedded.mobileprovision"))
    with tempfile.TemporaryDirectory() as directory:
        profile_path = Path(directory) / "embedded.mobileprovision"
        profile_path.write_bytes(profile_data)
        decoded = subprocess.run(
            ["security", "cms", "-D", "-i", str(profile_path)],
            check=True, stdout=subprocess.PIPE,
        ).stdout
        profile = plistlib.loads(decoded)
        verify_profile(profile, args.bundle_id)
        subprocess.run(["ditto", "-x", "-k", str(args.ipa.resolve()), directory], check=True)
        app_path = Path(directory) / str(Path(infos[0]).parent)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app_path)], check=True)
        signed = subprocess.run(
            ["codesign", "-d", "--entitlements", ":-", str(app_path)],
            check=True, stdout=subprocess.PIPE,
        ).stdout
        verify_signed_entitlements(plistlib.loads(signed), profile, info, args.require_push)
    result = {
        **identity,
        "bytes": args.ipa.stat().st_size,
        "sha256": hashlib.sha256(args.ipa.read_bytes()).hexdigest(),
        "profile_type": "app_store",
        "signature_verified": True,
        "production_push_required": args.require_push,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
