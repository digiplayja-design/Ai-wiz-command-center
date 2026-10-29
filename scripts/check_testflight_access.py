#!/usr/bin/env python3
"""Inspect TestFlight access; make only explicitly requested, guarded changes."""

import argparse
import json
import os
from pathlib import Path

from codemagic.apple.app_store_connect import AppStoreConnectApiClient
from codemagic.tools.app_store_connect.arguments import Types


APPS = (
    ("6783100102", "com.korlixdeveloper.korlixai", "12.0.3", "134"),
    ("6828213082", "com.korlixdeveloper.messenger", "1.0.2", "7"),
)
TESTER_EMAIL = "ricardo@korlixdeveloper.com"
EXPECTED_GROUPS = {
    "6783100102": ("d00681e0-53e5-47e7-a3a2-f97a95e17c8f", "Korlix internal testers"),
    "6828213082": ("b1dfb03e-0029-4274-9402-c01ee7452eb6", "KORLIX Messenger Internal"),
}
EXPECTED_BUILDS = {
    "6783100102": "86f4e8c1-54a8-4f91-a1f7-34c0ea82deeb",
    "6828213082": "0b33ee4f-a15d-40b6-b490-ddda8f0cf694",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assign-current-builds", action="store_true")
    parser.add_argument("--add-existing-ricardo-to-messenger", action="store_true")
    args = parser.parse_args()
    if args.add_existing_ricardo_to_messenger and not args.assign_current_builds:
        parser.error("Adding the existing tester requires --assign-current-builds")
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

    def link(path, resource_type, resource_id):
        response = client.session.post(
            f"{client.API_URL}/{path}",
            json={"data": [{"type": resource_type, "id": resource_id}]},
        )
        if response.status_code != 204:
            raise RuntimeError(f"Apple relationship update returned HTTP {response.status_code}")

    report = []
    errors = []
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
    if args.assign_current_builds:
        assignments = []
        # Validate both apps before any write. The separate membership flag
        # permits only the existing Ricardo tester to join Messenger's group.
        # Never create users, change roles, enable automatic distribution,
        # resend invitations, or alter App Store submissions.
        for item in report:
            app_id = item["app_id"]
            build_id = EXPECTED_BUILDS[app_id]
            group_id, group_name = EXPECTED_GROUPS[app_id]
            if item["build"]["id"] != build_id or item["build"].get("expired"):
                raise ValueError(f"Unexpected or expired build for {app_id}")
            versions = [v for v in item["app_store_versions"]
                        if v["version"] == item["expected_version"]]
            if len(versions) != 1 or (versions[0]["build"] or {}).get("id") != build_id:
                raise ValueError(f"Build is not attached to the expected App Store version for {app_id}")
            groups = [g for g in item["groups"] if g["id"] == group_id]
            if len(groups) != 1:
                raise ValueError(f"Expected existing internal group for {app_id}")
            group = groups[0]
            allow_missing = args.add_existing_ricardo_to_messenger and app_id == "6828213082"
            valid_count = len(group["target_testers"]) in ((0, 1) if allow_missing else (1,))
            if group["name"] != group_name or not group["internal"] or not valid_count:
                raise ValueError(f"Group or existing tester membership changed for {app_id}")
            assignments.append((item, group, build_id))
        if args.add_existing_ricardo_to_messenger:
            ai_group = next(g for i, g, _ in assignments if i["app_id"] == "6783100102")
            messenger_item, messenger_group, _ = next(
                entry for entry in assignments if entry[0]["app_id"] == "6828213082"
            )
            existing_tester = ai_group["target_testers"][0]
            if existing_tester["state"] != "INSTALLED":
                raise ValueError("Ricardo's existing installed AI tester could not be confirmed")
            try:
                if not messenger_group["target_testers"]:
                    # Resolve the destination app's own tester record. Apple
                    # rejected copying the installed AI record into this group.
                    candidates = collection("betaTesters", **{
                        "filter[email]": TESTER_EMAIL,
                        "filter[apps]": messenger_item["app_id"],
                    })
                    candidates = [t for t in candidates
                                  if t["attributes"].get("email", "").casefold() == TESTER_EMAIL.casefold()]
                    print(f"Existing Messenger tester records for {TESTER_EMAIL}: {len(candidates)}")
                    if len(candidates) > 1:
                        raise ValueError("Ambiguous existing Messenger tester records")
                    if candidates:
                        link(f"betaGroups/{messenger_group['id']}/relationships/betaTesters",
                             "betaTesters", candidates[0]["id"])
                    else:
                        # This enrolls only the approved email in the approved
                        # beta group; it does not create an App Store team user.
                        response = client.session.post(
                            f"{client.API_URL}/betaTesters",
                            json={"data": {
                                "type": "betaTesters",
                                "attributes": {"email": TESTER_EMAIL},
                                "relationships": {"betaGroups": {"data": [
                                    {"type": "betaGroups", "id": messenger_group["id"]}
                                ]}},
                            }},
                        )
                        if response.status_code != 201:
                            raise RuntimeError(f"Apple tester enrollment returned HTTP {response.status_code}")
                members = collection(f"betaGroups/{messenger_group['id']}/betaTesters")
                matched = [t for t in members
                           if t["attributes"].get("email", "").casefold() == TESTER_EMAIL.casefold()]
                if len(matched) != 1:
                    raise ValueError("Ricardo's Messenger tester membership was not confirmed")
                messenger_group["tester_count"] = len(members)
                messenger_group["target_testers"] = [
                    {"id": t["id"], "email": TESTER_EMAIL,
                     "state": t["attributes"].get("state"),
                     "invite_type": t["attributes"].get("inviteType")}
                    for t in matched
                ]
                messenger_item["membership_verified"] = True
            except Exception as error:
                messenger_item["membership_error"] = str(error)
                errors.append(f"Messenger membership: {error}")
                # Read only this user's existing eligibility to explain a
                # rejection. Never change team roles or app permissions.
                try:
                    users = collection("users", **{"filter[username]": TESTER_EMAIL,
                                                    "include": "visibleApps"})
                    messenger_item["target_user_access"] = [
                        {"roles": u["attributes"].get("roles"),
                         "all_apps_visible": u["attributes"].get("allAppsVisible"),
                         "visible_apps": u.get("relationships", {}).get("visibleApps", {}).get("data")}
                        for u in users
                        if u["attributes"].get("username", "").casefold() == TESTER_EMAIL.casefold()
                    ]
                    print("Existing App Store user access: " + json.dumps(messenger_item["target_user_access"]))
                except Exception as lookup_error:
                    print(f"User eligibility lookup unavailable: {lookup_error}")
        for item, group, build_id in assignments:
            try:
                if not any(b["id"] == build_id for b in group["builds"]):
                    link(f"betaGroups/{group['id']}/relationships/builds", "builds", build_id)
                linked = collection(f"betaGroups/{group['id']}/builds")
                if not any(b["id"] == build_id for b in linked):
                    raise ValueError(f"Build assignment was not confirmed for {item['app_id']}")
                group["builds"] = [{"id": b["id"], "number": b["attributes"].get("version")}
                                   for b in linked]
                item["beta_detail"] = read(f"builds/{build_id}/buildBetaDetail")["data"]["attributes"]
                item["assignment_verified"] = True
            except Exception as error:
                item["assignment_error"] = str(error)
                errors.append(f"{item['app_name']} build assignment: {error}")
    output = Path("artifacts/testflight-access.json")
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n")
    for item in report:
        print(f"\n{item['app_name']} {item['expected_version']} ({item['expected_build']})")
        current = next(v for v in item["app_store_versions"] if v["version"] == item["expected_version"])
        print(f"App Store: {current['state']}")
        print(f"TestFlight: {item['beta_detail']['internalBuildState']}")
        for group in item["groups"]:
            assigned = any(b["id"] == item["build"]["id"] for b in group["builds"])
            print(f"Group: {group['name']}; current build assigned: {assigned}")
            if not group["target_testers"]:
                print(f"Tester: {TESTER_EMAIL}; not a member of this group")
            for tester in group["target_testers"]:
                print(f"Tester: {tester['email']}; invitation: {tester['state']}")
    for error in errors:
        print(f"UNRESOLVED: {error}")
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
