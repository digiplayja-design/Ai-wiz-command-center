#!/usr/bin/env python3
"""Assign the verified property-view 1.0.2 (19) upload to its existing internal group.

Manual, one-purpose delivery step. Before queuing it, verify the completed
Codemagic upload and BrainVoice-verification.json against SOURCE_UPLOAD below.
Apple identifies the app/version/build; it does not attest the source commit.
Uses the existing managed Apple integration. Read-only unless --assign is set.
The only permitted write adds this build to the fixed internal beta group.
The fixed reviewed-upload record is required; it is reviewed evidence, not a
cryptographic source attestation. Pending markers or mismatched records stop
execution before any Apple request. Workflow environment cannot override it.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
from urllib.parse import urlparse

APP_ID = "6829319523"
BUNDLE_ID = "com.korlix.brain"
GROUP_ID = "ae86d9a2-5bdf-4f3d-910b-aa532675951f"
GROUP_NAME = "KORLIX Brain Internal"
VERSION = "1.0.2"
# Exact-source CI 43278567990 passed; the IPA and successful Apple upload are bound by the reviewed record.
SOURCE_COMMIT = "8b25e22eb5fc5cbfbc871a24f14c372d2d37efc0"
SOURCE_TREE = "c8bec83694386beffeb3972cf7ec6510752aa6c1"
SOURCE_BUILD_FLOOR = 19
BUILD_NUMBER = "19"
VERIFIED_RECORD_RELATIVE_PATH = "docs/releases/brain-property-view-20261112/verified-upload.json"
VERIFIED_RECORD_PATH = Path(__file__).resolve().parents[1] / VERIFIED_RECORD_RELATIVE_PATH
VERIFIED_RECORD_SHA256 = "4b243a5c28f5300989c04f95249ce033faa478ddbcb495a8a1e699085b9e1e14"
EXISTING_TESTER = "ricardo@korlixdeveloper.com"
SOURCE_UPLOAD = {
    "codemagicBuildId": "6af606109679c85ac0af33c6",
    "workflow": "korlix-brain-ios-testflight",
    "commit": SOURCE_COMMIT,
    "bundleId": BUNDLE_ID,
    "version": VERSION,
    "buildNumber": BUILD_NUMBER,
}
GROUP_PATH = f"/v1/betaGroups/{GROUP_ID}"
ASSIGNMENT_PATH = f"{GROUP_PATH}/relationships/builds"
USABLE_STATES = {"READY_FOR_BETA_TESTING", "IN_BETA_TESTING"}


class AssignmentError(RuntimeError):
    """A sanitized, actionable failure; never includes raw Apple responses."""


def require(condition, message):
    if not condition:
        raise AssignmentError(message)


def require_verified_source_upload():
    """Check fixed source pins against the separately reviewed artifact record."""
    require(isinstance(BUILD_NUMBER, str) and re.fullmatch(r"[1-9][0-9]*", BUILD_NUMBER),
            "The verified Apple build number is still pending; no Apple request was made")
    require(int(BUILD_NUMBER) >= SOURCE_BUILD_FLOOR,
            "The verified build is below the property-view source floor; no substitute is allowed")
    upload_id = SOURCE_UPLOAD.get("codemagicBuildId")
    require(isinstance(upload_id, str) and re.fullmatch(r"[a-f0-9]{24}", upload_id),
            "The verified Codemagic upload ID is still pending or invalid; no Apple request was made")
    require(SOURCE_UPLOAD.get("commit") == SOURCE_COMMIT
            and SOURCE_UPLOAD.get("workflow") == "korlix-brain-ios-testflight"
            and SOURCE_UPLOAD.get("bundleId") == BUNDLE_ID
            and SOURCE_UPLOAD.get("version") == VERSION
            and SOURCE_UPLOAD.get("buildNumber") == BUILD_NUMBER,
            "The source-upload metadata does not match this exact property-view candidate")
    require(isinstance(VERIFIED_RECORD_SHA256, str)
            and re.fullmatch(r"[a-f0-9]{64}", VERIFIED_RECORD_SHA256),
            "The reviewed upload record fingerprint is still pending; no Apple request was made")
    try:
        raw = VERIFIED_RECORD_PATH.read_bytes()
    except OSError:
        raise AssignmentError("The fixed reviewed upload record is missing; no Apple request was made") from None
    require(0 < len(raw) <= 65536 and hashlib.sha256(raw).hexdigest() == VERIFIED_RECORD_SHA256,
            "The reviewed upload record fingerprint does not match; no Apple request was made")
    try:
        record = json.loads(raw)
    except (ValueError, TypeError):
        raise AssignmentError("The reviewed upload record is invalid JSON") from None
    require(isinstance(record, dict) and record.get("schemaVersion") == 1,
            "The reviewed upload record has an unsupported schema")
    require(record.get("sourceUpload") == SOURCE_UPLOAD
            and record.get("sourceTree") == SOURCE_TREE
            and record.get("publishingStatus") == "uploaded",
            "The reviewed upload record does not match the exact successful source upload")
    apple_upload = record.get("appleUploadId")
    require(isinstance(apple_upload, str) and re.fullmatch(r"[A-Za-z0-9-]{1,128}", apple_upload),
            "The reviewed upload record lacks its observed Apple upload identifier")
    try:
        reviewed_at = datetime.fromisoformat(record.get("verifiedAt", "").replace("Z", "+00:00"))
        require(reviewed_at.tzinfo is not None, "The reviewed upload record requires a dated observation")
    except (TypeError, ValueError, AttributeError):
        raise AssignmentError("The reviewed upload record requires a dated observation") from None
    ipa = record.get("ipa")
    require(isinstance(ipa, dict) and isinstance(ipa.get("infoPlist"), dict),
            "The reviewed upload record lacks independent IPA observations")
    info = ipa["infoPlist"]
    require(info.get("CFBundleIdentifier") == BUNDLE_ID
            and info.get("CFBundleShortVersionString") == VERSION
            and info.get("CFBundleVersion") == BUILD_NUMBER
            and isinstance(info.get("CFBundleSupportedPlatforms"), list)
            and "iPhoneOS" in info["CFBundleSupportedPlatforms"],
            "The independently inspected IPA identity does not match this delivery")
    require(type(ipa.get("bytes")) is int and ipa["bytes"] > 0
            and isinstance(ipa.get("sha256"), str)
            and re.fullmatch(r"[a-f0-9]{64}", ipa["sha256"]),
            "The reviewed upload record lacks the inspected IPA size or checksum")
    return {
        "basis": "reviewed_local_artifact_record",
        "recordPath": VERIFIED_RECORD_RELATIVE_PATH,
        "recordSha256": VERIFIED_RECORD_SHA256,
        "verifiedAt": record["verifiedAt"],
        "sourceCommit": SOURCE_COMMIT,
        "sourceTree": SOURCE_TREE,
        "appleUploadId": apple_upload,
        "ipaSha256": ipa["sha256"],
        "ipaBytes": ipa["bytes"],
    }


def identifier(value):
    require(isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9-]{1,128}", value),
            "Apple returned an invalid resource identifier")
    return value


def resource(value, kind):
    require(isinstance(value, dict) and value.get("type") == kind,
            f"Apple returned an unexpected {kind} resource")
    identifier(value.get("id"))
    require(isinstance(value.get("attributes"), dict),
            f"Apple returned incomplete {kind} attributes")
    return value["attributes"]


class Apple:
    def __init__(self, session, auth_headers, assign=False):
        self.session, self.auth_headers, self.assign = session, auth_headers, assign

    @staticmethod
    def url(path):
        require(isinstance(path, str), "Apple returned an invalid pagination URL")
        url = "https://api.appstoreconnect.apple.com" + path if path.startswith("/") else path
        parsed = urlparse(url)
        require(parsed.scheme == "https" and parsed.netloc == "api.appstoreconnect.apple.com"
                and parsed.path.startswith("/v1/") and not parsed.fragment,
                "Unexpected Apple API URL")
        return url

    def request(self, method, path, params=None, body=None):
        if method == "POST":
            require(self.assign and path == ASSIGNMENT_PATH,
                    "Build assignment requires --assign and the exact internal group")
        else:
            require(method == "GET", "Unsupported Apple API operation")
        try:
            # A plain session has no CLI audit-file writes or automatic POST
            # retries. Never retry a timeout: the relationship may have committed.
            response = self.session.request(
                method, self.url(path), params=params, json=body,
                headers=self.auth_headers(), timeout=30, allow_redirects=False,
            )
        except AssignmentError:
            raise
        except Exception:
            raise AssignmentError(f"Apple {method} transport failed; rerun to inspect current state") from None
        expected = 204 if method == "POST" else 200
        require(response.status_code == expected,
                f"Apple {method} failed: HTTP {response.status_code}")
        if method == "POST":
            return None
        try:
            result = response.json()
        except Exception:
            raise AssignmentError("Apple returned invalid JSON") from None
        require(isinstance(result, dict) and "data" in result, "Apple returned incomplete data")
        return result

    def read(self, path):
        return self.request("GET", path)["data"]

    def all(self, path, **params):
        expected_path = urlparse(self.url(path)).path
        output, visited = [], set()
        while path:
            url = self.url(path)
            require(urlparse(url).path == expected_path and url not in visited and len(visited) < 20,
                    "Unexpected Apple pagination target or loop")
            visited.add(url)
            result = self.request("GET", path, params=params)
            require(isinstance(result["data"], list), "Apple returned a non-list collection")
            output.extend(result["data"])
            links = result.get("links", {})
            require(isinstance(links, dict), "Apple returned invalid pagination links")
            path, params = links.get("next"), {}
        return output

    def assign_build(self, build_id):
        self.request("POST", ASSIGNMENT_PATH,
                     body={"data": [{"type": "builds", "id": identifier(build_id)}]})


def check_app(api, path):
    app = api.read(path)
    attrs = resource(app, "apps")
    require(app["id"] == APP_ID and attrs.get("bundleId") == BUNDLE_ID,
            "Wrong Apple app or bundle; no substitute is allowed")


def check_group(api):
    group = api.read(GROUP_PATH)
    attrs = resource(group, "betaGroups")
    require(group["id"] == GROUP_ID and attrs.get("name") == GROUP_NAME
            and attrs.get("isInternalGroup") is True,
            "Wrong beta group identity or the group is not internal")
    check_app(api, f"{GROUP_PATH}/app")


def group_testers(api):
    testers = api.all(f"{GROUP_PATH}/betaTesters", limit=200, **{"fields[betaTesters]": "email"})
    matches, members = [], set()
    for tester in testers:
        attrs = resource(tester, "betaTesters")
        members.add(tester["id"])
        if str(attrs.get("email", "")).casefold() == EXISTING_TESTER.casefold():
            matches.append(tester["id"])
    require(len(matches) == 1 and len(members) == len(testers),
            "The expected tester must already be a unique member of the internal group")
    return members


def group_builds(api):
    builds = api.all(f"{GROUP_PATH}/builds", limit=200, **{"fields[builds]": "version"})
    for build in builds:
        resource(build, "builds")
    return {build["id"] for build in builds}


def check_build(api, build):
    attrs = resource(build, "builds")
    require(attrs.get("version") == BUILD_NUMBER, "Wrong build number; no latest-build fallback")
    require(attrs.get("processingState") == "VALID" and attrs.get("expired") is False,
            "The exact build is not processed and unexpired; nothing was assigned")
    build_id = build["id"]
    check_app(api, f"/v1/builds/{build_id}/app")
    version = resource(api.read(f"/v1/builds/{build_id}/preReleaseVersion"), "preReleaseVersions")
    require(version.get("version") == VERSION and version.get("platform") == "IOS",
            "Wrong prerelease version or platform; no substitute is allowed")
    return build_id


def internal_state(api, build_id):
    attrs = resource(api.read(f"/v1/builds/{build_id}/buildBetaDetail"), "buildBetaDetails")
    state = attrs.get("internalBuildState")
    require(state in USABLE_STATES,
            "The exact build is not eligible for internal testing; check processing or export compliance")
    return state


def run(api, assign=False, sleep=time.sleep):
    source_record = require_verified_source_upload()
    check_app(api, f"/v1/apps/{APP_ID}")
    check_group(api)
    builds = api.all("/v1/builds", limit=200,
                     **{"filter[app]": APP_ID, "filter[version]": BUILD_NUMBER})
    require(len(builds) == 1, "Expected exactly one matching build; absent or ambiguous upload")
    build_id = check_build(api, builds[0])
    state = internal_state(api, build_id)
    members_before = group_testers(api)
    builds_before = group_builds(api)
    already_linked = build_id in builds_before
    action = "already_linked" if already_linked else "validated_only"
    if assign and not already_linked:
        api.assign_build(build_id)
        action = "assigned"

    verified = False
    if assign or already_linked:
        # Read-only retries allow Apple's relationship/state propagation. A
        # subsequent run first inspects the existing link before doing any write.
        for attempt in range(4):
            check_group(api)
            require(group_testers(api) == members_before,
                    "Tester membership changed during delivery; inspect the group before continuing")
            current_builds = group_builds(api)
            require(builds_before.issubset(current_builds),
                    "Existing group builds changed during delivery; inspect the group before continuing")
            state = internal_state(api, build_id)
            verified = build_id in current_builds and state == "IN_BETA_TESTING"
            if verified:
                break
            if attempt < 3:
                sleep(2)
        require(verified, "Assignment read-back is pending; no further writes attempted; rerun to inspect")

    return {
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "expectedSourceUpload": SOURCE_UPLOAD,
        "reviewedArtifactRecord": source_record,
        "appId": APP_ID, "bundleId": BUNDLE_ID,
        "groupId": GROUP_ID, "groupName": GROUP_NAME, "isInternalGroup": True,
        "version": VERSION, "buildNumber": BUILD_NUMBER, "appleBuildId": build_id,
        "internalBuildState": state, "existingTesterCount": len(members_before),
        "action": action, "deliveryVerified": verified,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assign", action="store_true")
    parser.add_argument("--output", type=Path, default=Path("artifacts/brain-property-view-testflight-assignment.json"))
    args = parser.parse_args()
    try:
        require_verified_source_upload()
        from codemagic.apple.app_store_connect import AppStoreConnectApiClient
        from codemagic.tools.app_store_connect.arguments import Types
        import requests
        client = AppStoreConnectApiClient(
            key_identifier=Types.KeyIdentifierArgument(os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]).value,
            issuer_id=Types.IssuerIdArgument(os.environ["APP_STORE_CONNECT_ISSUER_ID"]).value,
            private_key=Types.PrivateKeyArgument(os.environ["APP_STORE_CONNECT_PRIVATE_KEY"]).value,
            log_requests=False, enable_jwt_cache=False,
        )
        with requests.Session() as session:
            report = run(Apple(session, client.generate_auth_headers, assign=args.assign), assign=args.assign)
    except AssignmentError as error:
        print(f"Brain+Voice internal delivery stopped: {error}", file=sys.stderr)
        return 1
    except Exception:
        print("Brain+Voice internal delivery stopped: managed Apple access or response unavailable", file=sys.stderr)
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
