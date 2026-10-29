#!/usr/bin/env python3
"""Provision only Receipt WIZ using an already-installed distribution identity."""
import base64
import json
import os
import re
import subprocess
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes
from codemagic.apple.app_store_connect import AppStoreConnectApiClient
from codemagic.tools.app_store_connect.arguments import Types
from prepare_ios_release import source_version, next_build_number, run_cli, select_app

BUNDLE_ID = "com.korlixdeveloper.receiptwiz"


def main():
    client = AppStoreConnectApiClient(
        key_identifier=Types.KeyIdentifierArgument(os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]).value,
        issuer_id=Types.IssuerIdArgument(os.environ["APP_STORE_CONNECT_ISSUER_ID"]).value,
        private_key=Types.PrivateKeyArgument(os.environ["APP_STORE_CONNECT_PRIVATE_KEY"]).value,
        log_requests=False, enable_jwt_cache=False,
    )

    def read(path, **params):
        result = client.session.get(f"{client.API_URL}/{path}", params=params)
        if result.status_code != 200:
            raise RuntimeError(f"Apple lookup failed: HTTP {result.status_code}")
        return result.json()["data"]

    def create(path, data):
        result = client.session.post(f"{client.API_URL}/{path}", json={"data": data})
        if result.status_code != 201:
            raise RuntimeError(f"Apple {path} creation failed: HTTP {result.status_code}")
        return result.json()["data"]

    # Match a public certificate to an identity whose private key is already
    # managed by Codemagic. Never generate, print or export any private key.
    identities = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning"], text=True)
    fingerprints = set(re.findall(r"\b[0-9A-F]{40}\b", identities))
    certificates = client.paginate(f"{client.API_URL}/certificates", page_size=200)
    matching = [c for c in certificates
                if c["attributes"]["certificateType"] in {"DISTRIBUTION", "IOS_DISTRIBUTION"}
                and x509.load_der_x509_certificate(base64.b64decode(c["attributes"]["certificateContent"]))
                .fingerprint(hashes.SHA1()).hex().upper() in fingerprints]
    if len(matching) != 1:
        raise ValueError("Expected exactly one existing distribution signing identity")
    certificate_id = matching[0]["id"]
    bundles = read("bundleIds", **{"filter[identifier]": BUNDLE_ID})
    bundles = [b for b in bundles if b["attributes"]["identifier"] == BUNDLE_ID]
    if not bundles:
        bundles = [create("bundleIds", {"type": "bundleIds", "attributes": {
            "identifier": BUNDLE_ID, "name": "KORLIX Receipt Wiz", "platform": "IOS"}})]
    if len(bundles) != 1:
        raise ValueError("Ambiguous Receipt WIZ bundle identity")
    bundle = bundles[0]
    profiles = client.paginate(f"{client.API_URL}/bundleIds/{bundle['id']}/profiles", page_size=200)
    matching_profiles = []
    for profile in profiles:
        if profile["attributes"]["profileType"] != "IOS_APP_STORE" or profile["attributes"]["profileState"] != "ACTIVE":
            continue
        certs = read(f"profiles/{profile['id']}/certificates")
        if certificate_id in {c["id"] for c in certs}:
            matching_profiles.append(profile)
    if matching_profiles:
        profile = read(f"profiles/{matching_profiles[0]['id']}")
    else:
        profile = create("profiles", {"type": "profiles", "attributes": {
            "name": "KORLIX Receipt Wiz App Store", "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
            }})
    profile_path = Path.home() / "Library/MobileDevice/Provisioning Profiles/receipt-wiz.mobileprovision"
    profile_path.parent.mkdir(parents=True, exist_ok=True)
    profile_path.write_bytes(base64.b64decode(profile["attributes"]["profileContent"], validate=True))
    profile_path.chmod(0o600)

    version, build = source_version(Path("pubspec.yaml").read_text())
    apps = read("apps", **{"filter[bundleId]": BUNDLE_ID})
    app_id = select_app(apps, BUNDLE_ID) if apps else None
    if app_id:
        build = next_build_number(run_cli("get-latest-build-number", app_id, "--platform", "IOS", "--all-versions"), build)
    elif os.environ.get("RECEIPT_REQUIRE_APP_RECORD") == "true":
        raise ValueError("Create the new Receipt WIZ app record in App Store Connect before TestFlight upload")
    with Path(os.environ["CM_ENV"]).open("a") as stream:
        stream.write(f"KORLIX_IOS_VERSION={version}\nKORLIX_IOS_BUILD_NUMBER={build}\n")
        if app_id:
            stream.write(f"KORLIX_IOS_APP_ID={app_id}\n")
    Path("artifacts").mkdir(exist_ok=True)
    report = {"bundle_id": BUNDLE_ID, "app_id": app_id, "version": version,
              "build": build, "profile_id": profile["id"], "certificate_id": certificate_id,
              "app_record_required": app_id is None}
    Path("artifacts/receipt-wiz-apple-setup.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Receipt WIZ {version} ({build}): dedicated profile ready; Apple app record: {app_id or 'not created yet'}")


if __name__ == "__main__":
    main()
