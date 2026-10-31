#!/usr/bin/env python3
"""Prepare Brain+Voice's dedicated profile using Codemagic's managed identity."""

import base64
import json
import os
import plistlib
import re
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path

from prepare_ios_release import next_build_number, run_cli, select_app, source_version
from verify_ios_ipa import verify_profile

BUNDLE_ID = "com.korlix.brain"
TEAM_ID = "FJKJ9MUDZ4"
CERTIFICATE_ID = "4635LCY72R"


def select_bundle(resources):
    if not isinstance(resources, list):
        raise ValueError("Apple bundle lookup did not return a resource list")
    matches = [item for item in resources
               if item.get("attributes", {}).get("identifier") == BUNDLE_ID]
    if len(matches) > 1:
        raise ValueError("Ambiguous Brain+Voice bundle identity")
    return matches[0] if matches else None


def validate_profile(profile, now=None):
    verify_profile(profile, BUNDLE_ID)
    if profile.get("TeamIdentifier") != [TEAM_ID]:
        raise ValueError("Brain+Voice profile belongs to a different Apple team")
    if profile.get("Entitlements", {}).get("com.apple.developer.team-identifier") != TEAM_ID:
        raise ValueError("Brain+Voice profile has an unexpected team entitlement")
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, datetime):
        raise ValueError("Brain+Voice profile has no valid expiration date")
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=timezone.utc)
    if expiry <= (now or datetime.now(timezone.utc)) + timedelta(days=1):
        raise ValueError("Brain+Voice profile is expired or expires within one day")


def resolve_release(apps, version_text, require_app_record, latest_build):
    version, build = source_version(version_text)
    app_id = select_app(apps, BUNDLE_ID) if apps else None
    if app_id:
        build = next_build_number(latest_build(app_id), build)
    elif require_app_record:
        raise ValueError("Create KORLIX Brain+Voice in App Store Connect with bundle ID com.korlix.brain before TestFlight upload")
    return app_id, version, build


def main():
    # Credentials stay in the existing Codemagic integration; never log keys,
    # generate a replacement certificate, or export the managed private key.
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes
    from codemagic.apple.app_store_connect import AppStoreConnectApiClient
    from codemagic.tools.app_store_connect.arguments import Types

    client = AppStoreConnectApiClient(
        key_identifier=Types.KeyIdentifierArgument(os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]).value,
        issuer_id=Types.IssuerIdArgument(os.environ["APP_STORE_CONNECT_ISSUER_ID"]).value,
        private_key=Types.PrivateKeyArgument(os.environ["APP_STORE_CONNECT_PRIVATE_KEY"]).value,
        log_requests=False, enable_jwt_cache=False,
    )

    def read(path, **params):
        response = client.session.get(f"{client.API_URL}/{path}", params=params)
        if response.status_code != 200:
            raise RuntimeError(f"Apple lookup failed: HTTP {response.status_code}")
        return response.json()["data"]

    def create(path, data):
        response = client.session.post(f"{client.API_URL}/{path}", json={"data": data})
        if response.status_code != 201:
            raise RuntimeError(f"Apple {path} creation failed: HTTP {response.status_code}")
        return response.json()["data"]

    certificate = read(f"certificates/{CERTIFICATE_ID}")
    if certificate["attributes"]["certificateType"] not in {"DISTRIBUTION", "IOS_DISTRIBUTION"}:
        raise ValueError("The configured certificate is not an Apple distribution identity")
    public_certificate = x509.load_der_x509_certificate(
        base64.b64decode(certificate["attributes"]["certificateContent"], validate=True))
    teams = public_certificate.subject.get_attributes_for_oid(x509.NameOID.ORGANIZATIONAL_UNIT_NAME)
    if [team.value for team in teams] != [TEAM_ID]:
        raise ValueError("The configured distribution certificate belongs to a different team")
    if public_certificate.not_valid_after_utc <= datetime.now(timezone.utc) + timedelta(days=1):
        raise ValueError("The managed Apple distribution certificate is expiring")
    identities = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning"], text=True)
    fingerprint = public_certificate.fingerprint(hashes.SHA1()).hex().upper()
    if fingerprint not in set(re.findall(r"\b[0-9A-F]{40}\b", identities)):
        raise ValueError("The existing distribution private key is not installed by Codemagic")

    apps = read("apps", **{"filter[bundleId]": BUNDLE_ID})
    app_id, version, build = resolve_release(
        apps, Path("pubspec.yaml").read_text(),
        os.environ.get("BRAIN_REQUIRE_APP_RECORD", "false") == "true",
        lambda identifier: run_cli("get-latest-build-number", identifier, "--platform", "IOS", "--all-versions"),
    )
    bundle = select_bundle(read("bundleIds", **{"filter[identifier]": BUNDLE_ID}))
    if bundle is None:
        bundle = create("bundleIds", {"type": "bundleIds", "attributes": {
            "identifier": BUNDLE_ID, "name": "KORLIX Brain Voice", "platform": "IOS"}})
    if select_bundle([bundle]) is None:
        raise ValueError("Apple returned a different bundle after creation")

    profiles = client.paginate(f"{client.API_URL}/bundleIds/{bundle['id']}/profiles", page_size=200)
    candidates = []
    for profile in profiles:
        attributes = profile["attributes"]
        if attributes["profileType"] != "IOS_APP_STORE" or attributes["profileState"] != "ACTIVE":
            continue
        expires = datetime.fromisoformat(attributes["expirationDate"].replace("Z", "+00:00"))
        if expires <= datetime.now(timezone.utc) + timedelta(days=1):
            continue
        certificates = read(f"profiles/{profile['id']}/certificates")
        if CERTIFICATE_ID in {item["id"] for item in certificates}:
            candidates.append(profile)
    if candidates:
        candidates.sort(key=lambda item: item["attributes"]["expirationDate"], reverse=True)
        profile = read(f"profiles/{candidates[0]['id']}")
    else:
        profile = create("profiles", {"type": "profiles", "attributes": {
            "name": f"KORLIX Brain Voice App Store {datetime.now(timezone.utc):%Y%m%d%H%M%S}",
            "profileType": "IOS_APP_STORE"}, "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                "certificates": {"data": [{"type": "certificates", "id": CERTIFICATE_ID}]},
            }})
    encoded_profile = base64.b64decode(profile["attributes"]["profileContent"], validate=True)
    decoded = subprocess.run(["security", "cms", "-D"], input=encoded_profile,
                             stdout=subprocess.PIPE, check=True).stdout
    decoded_profile = plistlib.loads(decoded)
    validate_profile(decoded_profile)
    embedded_fingerprints = {
        x509.load_der_x509_certificate(value).fingerprint(hashes.SHA1()).hex().upper()
        for value in decoded_profile.get("DeveloperCertificates", [])
    }
    if fingerprint not in embedded_fingerprints:
        raise ValueError("The dedicated profile does not include the managed certificate")
    profile_path = Path.home() / "Library/MobileDevice/Provisioning Profiles/korlix-brain.mobileprovision"
    profile_path.parent.mkdir(parents=True, exist_ok=True)
    profile_path.touch(mode=0o600, exist_ok=True)
    profile_path.chmod(0o600)
    profile_path.write_bytes(encoded_profile)

    with Path(os.environ["CM_ENV"]).open("a") as stream:
        stream.write(f"KORLIX_IOS_VERSION={version}\nKORLIX_IOS_BUILD_NUMBER={build}\n")
        if app_id:
            stream.write(f"KORLIX_IOS_APP_ID={app_id}\n")
    Path("artifacts").mkdir(exist_ok=True)
    report = {"bundle_id": BUNDLE_ID, "team_id": TEAM_ID, "app_id": app_id,
              "version": version, "build": build, "profile_id": profile["id"],
              "certificate_id": CERTIFICATE_ID, "app_record_required": app_id is None}
    Path("artifacts/brain-apple-setup.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Brain+Voice {version} ({build}): dedicated profile ready; Apple app record: {app_id or 'not created yet'}")


if __name__ == "__main__":
    main()
