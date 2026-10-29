#!/usr/bin/env python3
"""Read existing Apple release and TestFlight access without changing either."""

import json
import os
from pathlib import Path

from codemagic.apple.app_store_connect import AppStoreConnectApiClient
from codemagic.tools.app_store_connect.arguments import Types


APPS = (
    ("6783100102", "com.korlixdeveloper.korlixai", "12.0.3", "134"),
    ("6828213082", "com.korlixdeveloper.messenger", "1.0.2", "7"),
)
TESTER_EMAIL = "digiplayja@gmail.com"


def main():
    # Use only the existing Codemagic integration. Never log credentials or HTTP
    # headers, enable request logging, or export the key/token as an artifact.
    client = AppStoreConnectApiClient(
        key_identifier=Types.KeyIdentifierArgument(os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]).value,
        issuer_id=Types.IssuerIdArgument(os.environ["APP_STORE_CONNECT_ISSUER_ID"]).value,
        private_key=Types.PrivateKeyArgument(os.environ["APP_STORE_CONNECT_PRIVATE_KEY"]).value,
        log_requests=False,
        enable_jwt_cache=False,
    )

    def read(path, **params):
        return client.session.get(f"{client.API_URL}/{path}", params=params).json()

    def collection(path, **params):
        return client.paginate(f"{client.API_URL}/{path}", params=params, page_size=200)

    report = []
    for app_id, bundle_id, version, build_number in APPS:
        app = read(f"apps/{app_id}")["data"]
        if app["attributes"]["bundleId"] != bundle_id:
            raise ValueError(f"Apple app identity mismatch for {app_id}")
        item = {
            "app_id": app_id,
            "app_name": app["attributes"]["name"],
            "bundle_id": bundle_id,
            "expected_version": version,
            "expected_build": build_number,
        }
        versions = collection(f"apps/{app_id}/appStoreVersions", include="build")
        item["app_store_versions"] = [
            {"id": v["id"], "version": v["attributes"].get("versionString"),
             "state": v["attributes"].get("appStoreState"),
             "build": v.get("relationships", {}).get("build", {}).get("data")}
            for v in versions if v["attributes"].get("platform") == "IOS"
        ]
        builds = collection(f"apps/{app_id}/builds")
        matches = [b for b in builds if b["attributes"].get("version") == build_number]
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one build {build_number} for app {app_id}")
        build = matches[0]
        item["build"] = {"id": build["id"], **build["attributes"]}
        item["beta_detail"] = read(f"builds/{build['id']}/buildBetaDetail")["data"]["attributes"]
        item["groups"] = []
        for group in collection(f"apps/{app_id}/betaGroups"):
            group_id = group["id"]
            attrs = group["attributes"]
            testers = collection(f"betaGroups/{group_id}/betaTesters")
            target = [t for t in testers
                      if t["attributes"].get("email", "").casefold() == TESTER_EMAIL.casefold()]
            group_builds = collection(f"betaGroups/{group_id}/builds")
            item["groups"].append({
                "id": group_id,
                "name": attrs.get("name"),
                "internal": attrs.get("isInternalGroup"),
                "all_builds": attrs.get("hasAccessToAllBuilds"),
                "tester_count": len(testers),
                "target_testers": [{"id": t["id"], "email": TESTER_EMAIL,
                                    "state": t["attributes"].get("state"),
                                    "invite_type": t["attributes"].get("inviteType")}
                                   for t in target],
                "builds": [{"id": b["id"], "number": b["attributes"].get("version")}
                           for b in group_builds],
            })
        report.append(item)
        print(json.dumps(item, indent=2), flush=True)
    output = Path("artifacts/testflight-access.json")
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
