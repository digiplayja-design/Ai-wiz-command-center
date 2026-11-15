#!/usr/bin/env python3
"""Verify native Esha artifact identity, platform, and actual signing state.

Only public certificate data is inspected. Private keystores, passwords, and
App Store Connect credentials are never opened or printed by this program.
"""

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

BUNDLE_ID = "com.korlixdeveloper.esha"
SIGNATURE_MEMBER = re.compile(r"^META-INF/[^/]+\.(?:SF|RSA|DSA|EC)$", re.I)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command(*arguments, binary=False, input_data=None):
    return subprocess.run(
        arguments, check=True, input=input_data, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=not binary,
    ).stdout


def read_varint(data, offset):
    value = 0
    for shift in range(0, 70, 7):
        if offset >= len(data):
            raise ValueError("Truncated Android manifest protobuf")
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, offset
    raise ValueError("Invalid Android manifest protobuf varint")


def protobuf_fields(data):
    """Read wire fields, not generated code or untrusted executable content."""
    offset = 0
    fields = {}
    while offset < len(data):
        tag, offset = read_varint(data, offset)
        number, wire = tag >> 3, tag & 7
        if number == 0:
            raise ValueError("Invalid protobuf field number")
        if wire == 0:
            value, offset = read_varint(data, offset)
        elif wire in (1, 2, 5):
            length = {1: 8, 5: 4}.get(wire)
            if wire == 2:
                length, offset = read_varint(data, offset)
            if offset + length > len(data):
                raise ValueError("Truncated Android manifest field")
            value = data[offset:offset + length]
            offset += length
        else:
            raise ValueError("Unsupported Android manifest protobuf wire type")
        fields.setdefault(number, []).append(value)
    return fields


def single_bytes(fields, number, default=None):
    values = fields.get(number, [])
    if not values and default is not None:
        return default
    if len(values) != 1 or not isinstance(values[0], bytes):
        raise ValueError("Ambiguous or missing Android manifest field")
    return values[0]


def aab_manifest(data):
    # Field numbers are from AOSP tools/aapt2/Resources.proto, XmlNode,
    # XmlElement, and XmlAttribute. No bundletool download is necessary.
    node = protobuf_fields(data)
    element = protobuf_fields(single_bytes(node, 1))
    if single_bytes(element, 3) != b"manifest":
        raise ValueError("The bundle's root element is not an Android manifest")
    attributes = {}
    for raw in element.get(4, []):
        attribute = protobuf_fields(raw)
        namespace = single_bytes(attribute, 1, b"").decode("utf-8")
        name = single_bytes(attribute, 2).decode("utf-8")
        key = (namespace, name)
        if key in attributes:
            raise ValueError("Duplicate Android manifest attribute")
        attributes[key] = single_bytes(attribute, 3, b"").decode("utf-8")
    package = attributes.get(("", "package"))
    if package != BUNDLE_ID:
        raise ValueError("The AAB contains another app's package identity")
    android = "http://schemas.android.com/apk/res/android"
    return {
        "application_id": package,
        "version_name": attributes.get((android, "versionName")),
        "version_code": attributes.get((android, "versionCode")),
    }


def android_tool(name):
    executable = shutil.which(name)
    if executable:
        return executable
    for sdk in (os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT")):
        if not sdk:
            continue
        versions = sorted(
            (Path(sdk) / "build-tools").glob("*/" + name),
            key=lambda path: tuple(int(n) for n in re.findall(r"\d+", path.parent.name)),
            reverse=True,
        )
        if versions:
            return str(versions[0])
    raise ValueError(f"Android build tool {name} is required to verify the artifact")


def verify_jar_signature(path):
    # Upload certificates are normally self-signed. In strict mode code 4 can
    # describe that trust-chain warning; all other warning classes are rejected.
    # Certificate expiry is checked independently below.
    result = subprocess.run(
        ["jarsigner", "-J-Duser.language=en", "-J-Duser.country=US", "-verify", "-strict", str(path)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    if result.returncode not in (0, 4) or "jar verified" not in result.stdout.lower():
        raise ValueError("The AAB has an invalid signature or unsigned entries")
    pem_output = command("keytool", "-printcert", "-jarfile", str(path), "-rfc")
    certificates = re.findall(
        r"-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----",
        pem_output, re.S,
    )
    if not certificates:
        raise ValueError("No public signing certificate was found in the AAB")
    der = base64.b64decode(re.sub(r"\s+", "", certificates[0]), validate=True)
    fingerprint = hashlib.sha256(der).hexdigest().upper()
    expected = re.sub(r"[:\s]", "", os.environ.get("ESHA_ANDROID_UPLOAD_CERT_SHA256", "")).upper()
    if not re.fullmatch(r"[A-F0-9]{64}", expected) or fingerprint != expected:
        raise ValueError("The signed AAB does not match Esha's approved upload certificate")
    pem = "-----BEGIN CERTIFICATE-----\n" + certificates[0] + "\n-----END CERTIFICATE-----\n"
    command("openssl", "x509", "-checkend", "0", "-noout", input_data=pem)
    return fingerprint


def verify_android(path, kind):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(set(names)) != len(names):
            raise ValueError("Duplicate ZIP members are not accepted")
        if kind == "android-debug":
            if "AndroidManifest.xml" not in names or "classes.dex" not in names:
                raise ValueError("The debug artifact is not an Android APK")
            if not any(name.endswith("/libflutter.so") for name in names):
                raise ValueError("The APK is missing its native Flutter engine")
            badging = command(android_tool("aapt"), "dump", "badging", str(path))
            match = re.search(r"^package: name='([^']+)'", badging, re.M)
            if not match or match[1] != BUNDLE_ID or "application-debuggable" not in badging:
                raise ValueError("Expected the separately identified Esha debug APK")
            command(android_tool("apksigner"), "verify", str(path))
            return {"application_id": BUNDLE_ID, "platform": "android", "signing": "debug-test-only"}
        if "base/manifest/AndroidManifest.xml" not in names or "BundleConfig.pb" not in names:
            raise ValueError("The release artifact is not an Android App Bundle")
        identity = aab_manifest(archive.read("base/manifest/AndroidManifest.xml"))
        if not any(name.startswith("base/lib/") and name.endswith("/libflutter.so") for name in names):
            raise ValueError("The AAB is missing its native Flutter engine")
        if not any(name.startswith("base/lib/") and name.endswith("/libapp.so") for name in names):
            raise ValueError("The AAB is missing its compiled Flutter application")
        signature_files = [name for name in names if SIGNATURE_MEMBER.fullmatch(name)]
        if kind == "android-unsigned":
            if signature_files:
                raise ValueError("The unsigned release AAB unexpectedly contains a signing identity")
            return {**identity, "platform": "android", "signing": "unsigned-not-uploadable"}
        sf_files = [name for name in signature_files if name.upper().endswith(".SF")]
        block_files = [name for name in signature_files if not name.upper().endswith(".SF")]
        if len(sf_files) != 1 or len(block_files) != 1:
            raise ValueError("Expected exactly one Esha upload-key signature on the AAB")
    fingerprint = verify_jar_signature(path)
    return {**identity, "platform": "android", "signing": "verified-upload-key", "upload_certificate_sha256": fingerprint}


def verify_profile(profile, team_id):
    if not re.fullmatch(r"[A-Z0-9]{10}", team_id):
        raise ValueError("Configure ESHA_APPLE_TEAM_ID as the actual Apple Developer team")
    entitlements = profile.get("Entitlements", {})
    if entitlements.get("get-task-allow") is not False:
        raise ValueError("Esha's profile must not permit debugging")
    if "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices"):
        raise ValueError("Esha requires an App Store distribution profile")
    if team_id not in profile.get("TeamIdentifier", []):
        raise ValueError("Esha's profile belongs to a different Apple team")
    identifier = entitlements.get("application-identifier")
    allowed = {prefix + "." + BUNDLE_ID for prefix in profile.get("ApplicationIdentifierPrefix", [])}
    if identifier not in allowed:
        raise ValueError("The provisioning profile does not exactly match Esha's bundle identifier")
    expires = profile.get("ExpirationDate")
    if not isinstance(expires, dt.datetime) or expires.replace(tzinfo=dt.timezone.utc) <= dt.datetime.now(dt.timezone.utc):
        raise ValueError("The provisioning profile has expired or lacks an expiry date")
    return entitlements


def verify_ios(path, kind, version=None, build=None):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(set(names)) != len(names):
            raise ValueError("Duplicate ZIP members are not accepted")
        if any(PurePosixPath(name).is_absolute() or ".." in PurePosixPath(name).parts for name in names):
            raise ValueError("The iOS archive contains unsafe paths")
        depth = 2 if kind == "ios-signed" else 1
        infos = [name for name in names if name.endswith(".app/Info.plist") and name.count("/") == depth]
        if len(infos) != 1:
            raise ValueError("Expected exactly one main application in the iOS artifact")
        if kind == "ios-signed" and not infos[0].startswith("Payload/"):
            raise ValueError("The signed artifact is not an IPA")
        info = plistlib.loads(archive.read(infos[0]))
        if info.get("CFBundleIdentifier") != BUNDLE_ID:
            raise ValueError("The iOS artifact contains another app's bundle identity")
        if not any(name.endswith("/Flutter.framework/Flutter") for name in names):
            raise ValueError("The iOS artifact is missing its native Flutter engine")
        expected_platform = "iPhoneOS" if kind == "ios-signed" else "iPhoneSimulator"
        if expected_platform not in info.get("CFBundleSupportedPlatforms", []):
            raise ValueError("The iOS artifact was built for the wrong platform")
        identity = {
            "application_id": BUNDLE_ID,
            "version_name": info.get("CFBundleShortVersionString"),
            "version_code": info.get("CFBundleVersion"),
            "platform": "ios-device" if kind == "ios-signed" else "ios-simulator",
        }
        if kind == "ios-simulator":
            return {**identity, "signing": "simulator-only-not-an-ipa"}
        if info.get("CFBundleShortVersionString") != version or info.get("CFBundleVersion") != str(build):
            raise ValueError("The IPA version or build does not match the requested candidate")
        profile_data = archive.read(infos[0].replace("Info.plist", "embedded.mobileprovision"))
    with tempfile.TemporaryDirectory(prefix="esha-artifact-check-") as directory:
        profile_path = Path(directory) / "profile.mobileprovision"
        profile_path.write_bytes(profile_data)
        profile = plistlib.loads(command("security", "cms", "-D", "-i", str(profile_path), binary=True))
        team_id = os.environ.get("ESHA_APPLE_TEAM_ID", "")
        allowed = verify_profile(profile, team_id)
        command("ditto", "-x", "-k", str(path.resolve()), directory)
        app_path = Path(directory) / str(PurePosixPath(infos[0]).parent)
        command("codesign", "--verify", "--deep", "--strict", str(app_path))
        signed = plistlib.loads(command("codesign", "-d", "--entitlements", ":-", str(app_path), binary=True))
        if signed.get("application-identifier") != allowed.get("application-identifier"):
            raise ValueError("The code signature does not match Esha's provisioning profile")
        if signed.get("com.apple.developer.team-identifier") != team_id:
            raise ValueError("The code signature does not match Esha's configured Apple team")
        if signed.get("get-task-allow") is not False:
            raise ValueError("The signed IPA permits debugging")
    return {**identity, "signing": "verified-app-store-distribution", "profile_type": "app_store"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=("android-debug", "android-unsigned", "android-signed", "ios-simulator", "ios-signed"))
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--build")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if not args.artifact.is_file() or args.artifact.stat().st_size == 0:
        raise ValueError("The native artifact is missing or empty")
    if args.kind.startswith("android"):
        details = verify_android(args.artifact, args.kind)
    else:
        details = verify_ios(args.artifact, args.kind, args.version, args.build)
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    report = {
        "artifact": args.artifact.name, "artifact_kind": args.kind,
        "source_commit": revision, "bytes": args.artifact.stat().st_size,
        "sha256": sha256(args.artifact), **details,
        "submitted_to_store": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
