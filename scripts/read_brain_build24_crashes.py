#!/usr/bin/env python3
"""Read existing TestFlight crash feedback for the reported Brain+Voice build.

Manual diagnostics only. Uses the existing managed Apple integration and GET
requests only. Never changes builds, tester membership, feedback or app settings.
Full crash text goes to private build artifacts, never build stdout.
"""

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sys

APP_ID = "6829319523"
BUNDLE_ID = "com.korlix.brain"
BUILD_ID = "0435ec43-7c84-4beb-bb6c-76c253be9c6b"
VERSION = "1.0.2"
BUILD_NUMBER = "24"
ORIGIN = "https://api.appstoreconnect.apple.com"
OUTPUT = Path("artifacts/brain-build24-crashes")


class DiagnosticError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise DiagnosticError(message)


def run(session, auth_headers):
    allowed_log_ids = set()

    def get(path, params=None, optional=False):
        fixed = {f"/v1/apps/{APP_ID}", f"/v1/builds/{BUILD_ID}",
                 f"/v1/apps/{APP_ID}/betaFeedbackCrashSubmissions"}
        log_match = re.fullmatch(r"/v1/betaFeedbackCrashSubmissions/([A-Za-z0-9-]{1,128})/crashLog", path)
        require(path in fixed or (log_match and log_match.group(1) in allowed_log_ids),
                "Unexpected diagnostic endpoint")
        response = session.get(ORIGIN + path, params=params, headers=auth_headers(),
                               timeout=30, allow_redirects=False)
        if optional and response.status_code == 404:
            return None
        require(response.status_code == 200, f"Apple diagnostic GET failed: HTTP {response.status_code}")
        require(len(response.content) <= 8_000_000, "Apple diagnostic response exceeded limit")
        result = response.json()
        require(isinstance(result, dict) and "data" in result, "Apple returned incomplete diagnostic data")
        return result

    app = get(f"/v1/apps/{APP_ID}", {"fields[apps]": "bundleId,name"})["data"]
    require(app.get("type") == "apps" and app.get("id") == APP_ID
            and app.get("attributes", {}).get("bundleId") == BUNDLE_ID,
            "The requested app identity did not match")
    build_response = get(f"/v1/builds/{BUILD_ID}", {"include": "app,preReleaseVersion"})
    build = build_response["data"]
    require(build.get("type") == "builds" and build.get("id") == BUILD_ID
            and build.get("attributes", {}).get("version") == BUILD_NUMBER,
            "The reported build identity did not match")
    require(build.get("relationships", {}).get("app", {}).get("data", {}).get("id") == APP_ID,
            "The reported build belongs to a different app")
    versions = [item for item in build_response.get("included", [])
                if item.get("type") == "preReleaseVersions"]
    require(len(versions) == 1 and versions[0].get("attributes", {}).get("version") == VERSION
            and versions[0].get("attributes", {}).get("platform") == "IOS",
            "The reported build version or platform did not match")

    fields = "createdDate,deviceModel,osVersion,architecture,appUptimeInMilliseconds,appPlatform,buildBundleId,build,crashLog"
    feedback = get(f"/v1/apps/{APP_ID}/betaFeedbackCrashSubmissions", {
        "filter[build]": BUILD_ID, "sort": "-createdDate", "limit": 20,
        "fields[betaFeedbackCrashSubmissions]": fields,
    })
    require(isinstance(feedback["data"], list), "Apple returned an invalid feedback list")
    rows = []
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for item in feedback["data"]:
        ident = item.get("id", "")
        require(item.get("type") == "betaFeedbackCrashSubmissions"
                and re.fullmatch(r"[A-Za-z0-9-]{1,128}", ident), "Invalid crash feedback identity")
        attrs = item.get("attributes", {})
        require(item.get("relationships", {}).get("build", {}).get("data", {}).get("id") == BUILD_ID,
                "A crash feedback entry did not match the requested build")
        require(attrs.get("buildBundleId") in (None, BUNDLE_ID), "A crash feedback bundle did not match")
        row = {"id": ident, **{key: attrs.get(key) for key in
               ("createdDate", "deviceModel", "osVersion", "architecture", "appUptimeInMilliseconds", "appPlatform")}}
        if len(rows) < 5:
            allowed_log_ids.add(ident)
            log = get(f"/v1/betaFeedbackCrashSubmissions/{ident}/crashLog", optional=True)
            if log is not None:
                data = log["data"]
                text = data.get("attributes", {}).get("logText") if isinstance(data, dict) else None
                require(isinstance(data, dict) and data.get("type") == "betaCrashLogs"
                        and isinstance(text, str), "Invalid crash log response")
                raw = text.encode("utf-8")
                path = OUTPUT / f"{ident}.crash.txt"
                path.write_bytes(raw)
                row.update({"crashLog": path.name, "bytes": len(raw),
                            "sha256": hashlib.sha256(raw).hexdigest()})
            else:
                row["crashLogStatus"] = "not_available"
        rows.append(row)
    return {"checkedAt": datetime.now(timezone.utc).isoformat(), "readOnly": True,
            "appId": APP_ID, "bundleId": BUNDLE_ID, "version": VERSION,
            "buildNumber": BUILD_NUMBER, "appleBuildId": BUILD_ID,
            "feedbackCount": len(rows), "moreFeedbackAvailable": bool(feedback.get("links", {}).get("next")),
            "feedback": rows}


def main():
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
            report = run(session, client.generate_auth_headers)
        (OUTPUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({key: report[key] for key in
              ("checkedAt", "readOnly", "appId", "bundleId", "version", "buildNumber", "feedbackCount")}))
        return 0
    except DiagnosticError as error:
        print(f"Brain crash diagnostics stopped: {error}", file=sys.stderr)
    except Exception:
        print("Brain crash diagnostics stopped: managed Apple access or response unavailable", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
