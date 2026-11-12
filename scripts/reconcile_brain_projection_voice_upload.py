#!/usr/bin/env python3
"""Read Apple's exact build record to reconcile an ambiguous build-20 upload.

GET-only observation using the existing managed Apple integration. This helper
cannot upload, assign, invite, change compliance, submit review or release.
Apple build presence is not source attestation or TestFlight delivery.
The separate assignment helper's reviewed-upload guard is not imported or bypassed.
"""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import parse_qs, urlparse

APP_ID = "6829319523"
BUNDLE_ID = "com.korlix.brain"
VERSION = "1.0.2"
BUILD_NUMBER = "20"
GROUP_ID = "ae86d9a2-5bdf-4f3d-910b-aa532675951f"
GROUP_NAME = "KORLIX Brain Internal"
GROUP_PATH = f"/v1/betaGroups/{GROUP_ID}"
UPLOAD_CONTEXT = {
    "codemagicBuildId": "6af61eea10a05158d8122017",
    "codemagicIndex": 25,
    "workflow": "korlix-brain-ios-testflight",
    "sourceCommit": "6202cd06d94dae7eaf9fea097d63254de51a357e",
    "sourceTree": "68796631186a3c1c74a845625df6b742c50e4f9c",
    "observedAppleUploadId": "5963290e-11c2-486e-a723-05f931c43e5a",
    "observedAltoolResult": "UPLOAD SUCCEEDED with no errors",
    "observedCodemagicResult": "failed_publishing_after_Apple_500_errors",
    "inspectedIpaSha256": "294f224bb177ba38022e287be4bb76f020f3affb5701f0e2991e0a20d33151e2",
    "inspectedIpaBytes": 34887077,
}


class ReconciliationError(RuntimeError):
    """Sanitized failure without raw Apple payloads or credentials."""


def require(condition, message):
    if not condition:
        raise ReconciliationError(message)


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


class AppleGetOnly:
    def __init__(self, session, auth_headers):
        self.session, self.auth_headers = session, auth_headers

    @staticmethod
    def url(path):
        require(isinstance(path, str), "Apple returned an invalid URL")
        url = "https://api.appstoreconnect.apple.com" + path if path.startswith("/") else path
        parsed = urlparse(url)
        allowed = parsed.path in {
            f"/v1/apps/{APP_ID}", "/v1/builds", GROUP_PATH,
            f"{GROUP_PATH}/app", f"{GROUP_PATH}/builds",
        } or re.fullmatch(r"/v1/builds/[A-Za-z0-9-]{1,128}/(?:app|preReleaseVersion|buildBetaDetail)", parsed.path)
        require(parsed.scheme == "https" and parsed.netloc == "api.appstoreconnect.apple.com"
                and not parsed.fragment and allowed, "Unexpected Apple API URL")
        query = parse_qs(parsed.query)
        if parsed.path == "/v1/builds":
            for key, expected in (("filter[app]", APP_ID), ("filter[version]", BUILD_NUMBER)):
                require(key not in query or query[key] == [expected],
                        "Unexpected Apple pagination filter")
        return url

    def request(self, method, path, params=None):
        require(method == "GET", "Reconciliation permits GET only; no mutation is available")
        url = self.url(path)
        try:
            response = self.session.request(
                "GET", url, params=params, headers=self.auth_headers(),
                timeout=30, allow_redirects=False,
            )
        except Exception:
            raise ReconciliationError("Apple GET transport failed; no mutation was attempted") from None
        require(response.status_code == 200, f"Apple GET failed: HTTP {response.status_code}")
        try:
            result = response.json()
        except Exception:
            raise ReconciliationError("Apple returned invalid JSON") from None
        require(isinstance(result, dict) and "data" in result, "Apple returned incomplete data")
        return result

    def read(self, path):
        return self.request("GET", path)["data"]

    def all(self, path, **params):
        expected_path = urlparse(self.url(path)).path
        result_rows, visited = [], set()
        while path:
            url = self.url(path)
            require(urlparse(url).path == expected_path and url not in visited and len(visited) < 20,
                    "Unexpected Apple pagination target or loop")
            visited.add(url)
            result = self.request("GET", path, params=params)
            require(isinstance(result["data"], list), "Apple returned a non-list collection")
            result_rows.extend(result["data"])
            links = result.get("links", {})
            require(isinstance(links, dict), "Apple returned invalid pagination links")
            path, params = links.get("next"), {}
        return result_rows


def check_app(api, path):
    app = api.read(path)
    attrs = resource(app, "apps")
    require(app["id"] == APP_ID and attrs.get("bundleId") == BUNDLE_ID,
            "Wrong Apple app or bundle; no substitute is allowed")


def group_observation(api, build_id):
    group = api.read(GROUP_PATH)
    attrs = resource(group, "betaGroups")
    require(group["id"] == GROUP_ID and attrs.get("name") == GROUP_NAME
            and attrs.get("isInternalGroup") is True, "Wrong existing internal group")
    check_app(api, f"{GROUP_PATH}/app")
    builds = api.all(f"{GROUP_PATH}/builds", limit=200, **{"fields[builds]": "version"})
    for build in builds:
        resource(build, "builds")
    return {"groupId": GROUP_ID, "groupName": GROUP_NAME, "isInternalGroup": True,
            "buildLinked": any(build["id"] == build_id for build in builds)}


def run(api, check_group=False):
    check_app(api, f"/v1/apps/{APP_ID}")
    builds = api.all("/v1/builds", limit=200,
                     **{"filter[app]": APP_ID, "filter[version]": BUILD_NUMBER})
    report = {
        "schemaVersion": 1,
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "purpose": "reconcile_ambiguous_upload", "readOnly": True,
        "uploadContext": dict(UPLOAD_CONTEXT),
        "appId": APP_ID, "bundleId": BUNDLE_ID, "version": VERSION, "buildNumber": BUILD_NUMBER,
        "sourceAttestedByApple": False, "deliveryVerified": False,
        "returnedBuildCount": len(builds), "exactBuildPresent": False,
        "presenceStatus": "not_found" if not builds else "ambiguous",
        "processingVerified": False,
    }
    # Missing or ambiguous presence is a completed read-only observation, never
    # permission to retry an upload or select a different/latest build.
    if len(builds) != 1:
        return report
    build = builds[0]
    attrs = resource(build, "builds")
    require(attrs.get("version") == BUILD_NUMBER, "Wrong build number; no latest-build fallback")
    build_id = build["id"]
    check_app(api, f"/v1/builds/{build_id}/app")
    version = resource(api.read(f"/v1/builds/{build_id}/preReleaseVersion"), "preReleaseVersions")
    require(version.get("version") == VERSION and version.get("platform") == "IOS",
            "Wrong prerelease version or platform; no substitute is allowed")
    processing = attrs.get("processingState")
    require(processing in {"PROCESSING", "FAILED", "INVALID", "VALID"},
            "Apple returned an unknown processing state")
    require(type(attrs.get("expired")) is bool, "Apple omitted the build expiration state")
    report.update({"presenceStatus": "found", "exactBuildPresent": True,
                   "appleBuildId": build_id, "platform": "IOS", "processingState": processing,
                   "expired": attrs["expired"],
                   "processingVerified": processing == "VALID" and attrs["expired"] is False,
                   "observedUploadIdMatchesBuildId": build_id == UPLOAD_CONTEXT["observedAppleUploadId"]})
    if processing == "VALID":
        detail = resource(api.read(f"/v1/builds/{build_id}/buildBetaDetail"), "buildBetaDetails")
        state = detail.get("internalBuildState")
        require(isinstance(state, str) and re.fullmatch(r"[A-Z_]{1,80}", state),
                "Apple returned an invalid internal build state")
        report["internalBuildState"] = state
    if check_group:
        report["existingGroup"] = group_observation(api, build_id)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-group", action="store_true")
    parser.add_argument("--output", type=Path,
                        default=Path("artifacts/brain-projection-voice-upload-reconciliation.json"))
    args = parser.parse_args()
    try:
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
            report = run(AppleGetOnly(session, client.generate_auth_headers), check_group=args.check_group)
    except ReconciliationError as error:
        print(f"Brain+Voice upload reconciliation stopped: {error}", file=sys.stderr)
        return 1
    except Exception:
        print("Brain+Voice upload reconciliation stopped: managed Apple access or response unavailable", file=sys.stderr)
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
