#!/usr/bin/env python3
"""Select one verified uploaded COPY Box build for the existing iOS version.

Only the exact version/build relationship can be patched, once per invocation.
Uses existing managed Apple authentication in memory. No review submission,
release-mode change, credential access, tester invitation, or backend request.
API: https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-appstoreversions-_id_-relationships-build
"""

from copy import deepcopy
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys

from read_copybox_apple_status import (
    APP_ID, BUNDLE_ID, TARGET_VERSION, ORIGIN, AppleReadOnly, AuditError,
    ident, related_id, resource, timestamp,
)

VERSION_ID = "3ae65f97-f9c5-498d-80b6-8f6d208615d6"
PREVIOUS_BUILD_ID = "ddd61c5d-982c-404c-9aaa-d280bd0495be"
BUILD_RELATION = f"/v1/appStoreVersions/{VERSION_ID}/relationships/build"
EXPECTED_STATE = "PREPARE_FOR_SUBMISSION"
EXPECTED_RELEASE_TYPE = "AFTER_APPROVAL"
OUTPUT = Path("artifacts/copybox-apple-build-selection.json")


class SelectionStop(Exception):
    """Only fixed, non-sensitive diagnostic codes belong here."""

    def __init__(self, code):
        self.code = code


def require(condition, code):
    if not condition:
        raise SelectionStop(code)


def build_number(value):
    require(type(value) is str and re.fullmatch(r"[1-9][0-9]{0,8}", value)
            and int(value) >= 2, "expected_build_number_invalid")
    return value


def new_report(number=None):
    return {
        "schemaVersion": 1, "checkedAt": datetime.now(timezone.utc).isoformat(),
        "appId": APP_ID, "bundleId": BUNDLE_ID, "versionId": VERSION_ID,
        "version": TARGET_VERSION, "expectedBuildNumber": number,
        "success": False, "phase": "initial", "scopeVerified": False,
        "alreadySelected": False, "selectedBuildVerified": False,
        "otherVersionAttributesUnchanged": False, "patchAttempts": [],
        "mutationOutcomeUnknown": False, "requestCount": 0,
        "submissionAttempted": False, "failureCode": None,
    }


class AppleBuildSelection:
    def __init__(self, session, auth_headers, report, number):
        self.session, self.auth_headers, self.report = session, auth_headers, report
        self.number = build_number(number)
        self.read = AppleReadOnly(session, auth_headers)
        self.verified_target_id = None
        self.ready_to_patch = False
        self.patch_count = 0

    def version_snapshot(self):
        rows, more = self.read.app_list("appStoreVersions")
        require(not more, "version_scope_incomplete")
        matches = [row for row in rows if row["id"] == VERSION_ID]
        require(len(matches) == 1, "version_identity_mismatch")
        attrs = resource(matches[0], "appStoreVersions")
        require(attrs.get("versionString") == TARGET_VERSION
                and attrs.get("platform") == "IOS", "version_identity_mismatch")
        states = [attrs[key] for key in ("appVersionState", "appStoreState")
                  if key in attrs]
        require(states and all(value == EXPECTED_STATE for value in states),
                "version_not_in_preparation")
        require(attrs.get("releaseType") == EXPECTED_RELEASE_TYPE,
                "release_type_changed")
        payload = self.read.get(BUILD_RELATION)
        link = payload["data"]
        require(isinstance(link, dict) and link.get("type") == "builds",
                "selected_build_relationship_missing")
        selected = ident(link.get("id"))
        return {"attributes": deepcopy(attrs), "selected": selected}

    def verified_build(self):
        rows, more = self.read.app_list("builds")
        require(not more, "build_scope_incomplete")
        matches = [row for row in rows
                   if row.get("attributes", {}).get("version") == self.number]
        require(len(matches) == 1, "expected_build_not_unique")
        row = matches[0]
        attrs = resource(row, "builds")
        require(row["id"] != PREVIOUS_BUILD_ID, "replacement_is_previous_build")
        require(attrs.get("processingState") == "VALID", "build_not_valid")
        require(attrs.get("expired") is False, "build_expired_or_unknown")
        pre = self.read.get(f"/v1/builds/{row['id']}/preReleaseVersion")["data"]
        pre_attrs = resource(pre, "preReleaseVersions")
        require(pre_attrs.get("version") == TARGET_VERSION
                and pre_attrs.get("platform") == "IOS",
                "build_version_or_platform_mismatch")
        require(related_id(pre, "app", "apps") in (None, APP_ID),
                "build_app_mismatch")
        result = {
            "id": row["id"], "buildNumber": self.number,
            "processingState": "VALID", "expired": False,
            "preReleaseVersion": TARGET_VERSION, "platform": "IOS",
            "uploadedDate": timestamp(attrs.get("uploadedDate")),
        }
        self.verified_target_id = result["id"]
        return result

    def select_once(self, target_id):
        require(self.ready_to_patch and self.read.verified_app
                and self.patch_count == 0
                and target_id == self.verified_target_id
                and target_id != PREVIOUS_BUILD_ID, "mutation_scope_violation")
        self.patch_count = 1  # No retry after a transport error or uncertain write.
        self.ready_to_patch = False
        attempt = {"httpStatus": None, "accepted": False}
        self.report["patchAttempts"].append(attempt)
        self.report["mutationOutcomeUnknown"] = True
        try:
            response = self.session.request(
                "PATCH", ORIGIN + BUILD_RELATION,
                json={"data": {"type": "builds", "id": target_id}},
                headers=self.auth_headers(), timeout=30, allow_redirects=False,
            )
        except Exception:
            raise SelectionStop("apple_patch_transport_unconfirmed") from None
        status = response.status_code
        require(type(status) is int and 100 <= status <= 599,
                "apple_patch_status_invalid")
        attempt["httpStatus"] = status
        require(status == 204, "apple_patch_not_confirmed")
        attempt["accepted"] = True


def run(session, auth_headers, expected_number):
    report = new_report()
    api = None
    try:
        report["expectedBuildNumber"] = build_number(expected_number)
        api = AppleBuildSelection(session, auth_headers, report, expected_number)
        report["phase"] = "verify_identity_and_uploaded_build"
        app = api.read.verify_app()
        require(app["id"] == "6830765098"
                and app["bundleId"] == "com.korlixdeveloper.copybox",
                "app_identity_mismatch")
        before = api.version_snapshot()
        desired = api.verified_build()
        report["scopeVerified"] = True
        report["previousSelectedBuildId"] = before["selected"]
        report["desiredBuild"] = desired
        require(before["selected"] in (PREVIOUS_BUILD_ID, desired["id"]),
                "unexpected_current_build")
        report["alreadySelected"] = before["selected"] == desired["id"]
        if not report["alreadySelected"]:
            report["phase"] = "recheck_before_selection"
            current = api.version_snapshot()
            current_build = api.verified_build()
            require(current == before and current_build == desired,
                    "release_or_build_changed_during_run")
            api.ready_to_patch = True
            report["phase"] = "select_reviewed_build"
            api.select_once(desired["id"])

        report["phase"] = "verify_selection"
        after = api.version_snapshot()
        require(after["selected"] == desired["id"], "selection_readback_mismatch")
        require(after["attributes"] == before["attributes"],
                "other_version_attributes_changed")
        require(api.verified_build() == desired, "uploaded_build_changed")
        report["selectedBuildId"] = after["selected"]
        report["selectedBuildVerified"] = True
        report["otherVersionAttributesUnchanged"] = True
        report["releaseType"] = EXPECTED_RELEASE_TYPE
        report["state"] = EXPECTED_STATE
        report["mutationOutcomeUnknown"] = False
        report["phase"] = "complete"
        report["success"] = True
    except SelectionStop as error:
        report["failureCode"] = error.code
    except AuditError:
        report["failureCode"] = "apple_scoped_get_or_identity_check_failed"
    except Exception:
        report["failureCode"] = "selection_unconfirmed"
    if api is not None:
        report["requestCount"] = api.read.request_count + api.patch_count
    return report


def main():
    if len(sys.argv) != 4 or sys.argv[1:3] != ["--select-reviewed-build", "--build-number"]:
        print("Use --select-reviewed-build --build-number with the confirmed uploaded build number.",
              file=sys.stderr)
        return 2
    try:
        number = build_number(sys.argv[3])
    except SelectionStop:
        print("The confirmed replacement build number must be an integer of at least 2.",
              file=sys.stderr)
        return 2
    report = new_report(number)
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
            session.trust_env = False
            report = run(session, client.generate_auth_headers, number)
    except Exception:
        report["failureCode"] = "managed_apple_access_unavailable"
    try:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except Exception:
        print("COPY Box build selection stopped: evidence could not be saved.", file=sys.stderr)
        return 1
    print(json.dumps({key: report[key] for key in (
        "appId", "expectedBuildNumber", "success", "phase", "alreadySelected",
        "selectedBuildVerified", "failureCode", "requestCount",
    )} | {"report": str(OUTPUT)}))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    sys.exit(main())
