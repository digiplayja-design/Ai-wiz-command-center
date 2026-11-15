#!/usr/bin/env python3
"""Plan selection of Esha 1.0.0 build 2; --apply-draft changes only its linkage.

No replacement of another selected build, declaration answers, review request,
contact changes or publishing. One PATCH at most, with fresh GET readback.
https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-appstoreversions-_id_-relationships-build
https://developer.apple.com/documentation/appstoreconnectapi/get-v1-builds-_id_-prereleaseversion
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

from inspect_apple_release import (
    API_ORIGIN, APP_ID, BUNDLE_ID, CLI_VERSION, SKU, AppleReadClient,
    InventoryError, MAX_REQUESTS, MAX_SECONDS, bool_value, enum_value,
    linkage, require, resource, save_report, text_value,
)


BUILD_ID = "50de7424-a350-42fb-9a9d-78eb17021ace"
BUILD_NUMBER = "2"
VERSION = "1.0.0"
REPORT_FILE = "Esha-Apple-build-selection-verification.json"


class AmbiguousSelection(InventoryError):
    """Only GET reconciliation is allowed after an uncertain PATCH result."""


def selection_body():
    return {"data": {"type": "builds", "id": BUILD_ID}}


class BuildSelectionClient(AppleReadClient):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.selection_snapshot = None
        self.latest_observation = {}
        self.patch_attempted = False
        self.last_api_rejection = None

    def target_prerelease_version(self):
        # This is the sole additional GET beyond the shared inventory routes.
        # Its fixed build ID must first be reached through Esha's builds list.
        require(self.identity_verified and ("builds", BUILD_ID) in self.bound,
                "target_build_not_bound_to_esha")
        path = f"/v1/builds/{BUILD_ID}/preReleaseVersion"
        value = resource(self._request(API_ORIGIN + path, path, {})["data"], "preReleaseVersions")
        app = linkage(value, "app", "apps")
        require(app is None or app == APP_ID, "prerelease_version_app_mismatch")
        return value

    def select_once(self):
        snapshot = self.selection_snapshot
        require(self.identity_verified and snapshot is not None, "fresh_selection_inventory_required")
        require(not self.patch_attempted, "selection_patch_retry_forbidden")
        require(snapshot["selected_build_id"] is None, "selected_build_must_be_absent")
        version_id = snapshot["version_id"]
        require(("appStoreVersions", version_id) in self.bound and ("builds", BUILD_ID) in self.bound,
                "selection_resources_not_bound_to_esha")
        require(not self.stopped_reason, self.stopped_reason or "requests_stopped")
        require(self.request_count < MAX_REQUESTS and self.clock() - self.started < MAX_SECONDS,
                "inventory_request_or_time_budget_exhausted")
        self.patch_attempted = True
        self.selection_snapshot = None
        self.request_count += 1
        path = f"/v1/appStoreVersions/{version_id}/relationships/build"
        request = urllib.request.Request(API_ORIGIN + path, method="PATCH",
            data=json.dumps(selection_body()).encode(), headers={**self.auth_headers(),
                "Accept": "application/json", "Content-Type": "application/json"})
        try:
            with self.open_request(request, timeout=20) as response:
                if response.getcode() != 204:
                    raise AmbiguousSelection("unexpected_patch_status_get_reconciliation_only")
        except urllib.error.HTTPError as error:
            status = error.code
            codes = []
            try:
                raw = error.read(65_537)
                if len(raw) <= 65_536:
                    document = json.loads(raw)
                    errors = document.get("errors", []) if isinstance(document, dict) else []
                    if isinstance(errors, list):
                        codes = [item["code"] for item in errors[:10] if isinstance(item, dict)
                                 and isinstance(item.get("code"), str)
                                 and re.fullmatch(r"[A-Z0-9_.-]{1,100}", item["code"])]
            except Exception:
                pass
            finally:
                error.close()
            self.last_api_rejection = {"http_status": status, "error_codes": codes,
                                       "raw_details_withheld": True}
            if status in (401, 403, 429):
                self.stopped_reason = f"http_{status}_further_requests_stopped"
            if status >= 500 or status == 408:
                raise AmbiguousSelection("patch_http_failure_get_reconciliation_only") from None
            raise InventoryError(f"build_association_rejected_http_{status}_no_retry") from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise AmbiguousSelection("patch_transport_uncertain_get_reconciliation_only") from None


def inspect_selection(client):
    client.selection_snapshot = None
    client.latest_observation = {}
    client.identity_verified = False
    client.bound.clear()
    client.parents.clear()
    client.verify_identity()
    versions = client.read("apps", APP_ID, "appStoreVersions").values
    matching = [value for value in versions if value["attributes"].get("platform") == "IOS"
                and value["attributes"].get("versionString") == VERSION]
    require(len(matching) == 1, "one_exact_ios_1_0_0_version_required")
    version = matching[0]
    states = [version["attributes"][field] for field in ("appVersionState", "appStoreState")
              if version["attributes"].get(field) is not None]
    observation = {"version_id": version["id"], "version": VERSION,
                   "version_states": [enum_value(state) for state in states], "target_build_id": BUILD_ID}
    client.latest_observation = observation
    require(states and all(state == "PREPARE_FOR_SUBMISSION" for state in states), "app_version_not_editable_draft")
    builds = client.read("apps", APP_ID, "builds").values
    matching = [value for value in builds if value["id"] == BUILD_ID]
    require(len(matching) == 1, "exact_build_2_id_not_found_under_esha")
    build = matching[0]
    attributes = build["attributes"]
    observation.update(build_number=text_value(attributes.get("version"), 64),
                       processing_state=enum_value(attributes.get("processingState")),
                       expired=bool_value(attributes.get("expired")),
                       uses_non_exempt_encryption=bool_value(attributes.get("usesNonExemptEncryption")))
    require(attributes.get("version") == BUILD_NUMBER, "target_build_number_mismatch")
    require(attributes.get("processingState") == "VALID" and attributes.get("expired") is False,
            "target_build_not_valid_and_unexpired")
    audience = attributes.get("buildAudienceType")
    require(audience is None or audience == "APP_STORE_ELIGIBLE", "target_build_not_app_store_eligible")
    prerelease = client.target_prerelease_version()
    observation.update(pre_release_id=prerelease["id"],
                       pre_release_version=text_value(prerelease["attributes"].get("version"), 64),
                       platform=enum_value(prerelease["attributes"].get("platform")))
    require(prerelease["attributes"].get("version") == VERSION
            and prerelease["attributes"].get("platform") == "IOS", "target_build_marketing_version_or_platform_mismatch")
    # Check the selected relationship last, immediately before any intent/PATCH.
    selected = client.read("appStoreVersions", version["id"], "build").values
    require(len(selected) <= 1, "ambiguous_selected_build")
    selected_id = selected[0]["id"] if selected else None
    observation["selected_build_id"] = selected_id
    require(selected_id in (None, BUILD_ID), "another_build_already_selected_no_replacement")
    if selected:
        selected_attributes = selected[0]["attributes"]
        require(selected_attributes.get("version") == BUILD_NUMBER
                and selected_attributes.get("processingState") == "VALID"
                and selected_attributes.get("expired") is False, "selected_build_readback_inconsistent")
    client.selection_snapshot = dict(observation)
    return dict(observation)


def new_report(source_commit, apply_draft):
    return {"schema_version": 1, "status": "checking", "mode": "apply_draft" if apply_draft else "read_only_plan",
            "started_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "source_commit": source_commit,
            "apple_app_id": APP_ID, "bundle_id": BUNDLE_ID, "sku": SKU,
            "target_version": VERSION, "target_build_number": BUILD_NUMBER, "target_apple_build_id": BUILD_ID,
            "identity_verified": False, "planned_operation": None, "patch_attempts": 0, "patch_retries": 0,
            "association_changed_by_this_run": False, "encryption_answers_changed": False,
            "review_submitted": False, "contact_details_changed": False, "published": False}


def select_build(client, *, apply_draft, report_path, source_commit):
    report_path = Path(report_path)
    report = new_report(source_commit, apply_draft)
    save_report(report_path, report)
    try:
        require(isinstance(source_commit, str) and re.fullmatch(r"[a-f0-9]{40}", source_commit), "invalid_source_commit")
        initial = inspect_selection(client)
        report.update(identity_verified=True, initial_observation=initial)
        if initial["selected_build_id"] is None:
            body = selection_body()
            report["planned_operation"] = {"method": "PATCH",
                "path": f"/v1/appStoreVersions/{initial['version_id']}/relationships/build", "body": body,
                "body_sha256": hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()}
        save_report(report_path, report)
        if not apply_draft:
            report["status"] = "already_selected_verified" if initial["selected_build_id"] else "plan_only_no_changes"
        else:
            current = inspect_selection(client)
            require(current["version_id"] == initial["version_id"] and current["pre_release_id"] == initial["pre_release_id"],
                    "selection_resource_identity_changed")
            require(initial["selected_build_id"] is None or current["selected_build_id"] == BUILD_ID,
                    "previously_selected_build_disappeared_stop")
            if current["selected_build_id"] == BUILD_ID:
                report.update(status="already_selected_verified", final_observation=current)
            else:
                report["intent"] = {"recorded_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                                    "observation_before_patch": current, "operation": report["planned_operation"],
                                    "outcome": "attempting_once"}
                # A process interruption after this durable intent cannot prove
                # whether Apple applied the request. Never record "unchanged".
                report["association_changed_by_this_run"] = "unknown"
                save_report(report_path, report)
                ambiguous = False
                try:
                    client.select_once()
                    report["intent"]["outcome"] = "http_204_received_readback_required"
                except AmbiguousSelection as error:
                    ambiguous = True
                    report["intent"].update(outcome="ambiguous_patch_get_reconciliation_only", reason=str(error))
                report["patch_attempts"] = int(client.patch_attempted)
                save_report(report_path, report)
                after = inspect_selection(client)
                require(after["version_id"] == initial["version_id"] and after["pre_release_id"] == initial["pre_release_id"],
                        "selection_resource_identity_changed")
                require(after["selected_build_id"] == BUILD_ID, "selection_not_confirmed_stop_without_retry")
                report.update(status="selection_reconciled_after_ambiguous_patch" if ambiguous else "build_selected_and_read_back",
                              final_observation=after, association_changed_by_this_run="unknown" if ambiguous else True)
                report["intent"]["outcome"] = "desired_build_selected_verified"
        report.update(request_count=client.request_count, completed_at_utc=dt.datetime.now(dt.timezone.utc).isoformat())
        save_report(report_path, report)
        return report
    except Exception as error:
        report.update(status="stopped_review_partial_progress", patch_attempts=int(client.patch_attempted),
                      request_count=client.request_count, identity_verified=client.identity_verified,
                      association_changed_by_this_run="unknown" if client.patch_attempted else False,
                      latest_observation=client.latest_observation,
                      error=str(error) if isinstance(error, InventoryError) else "local_processing_failed_details_withheld")
        if client.last_api_rejection:
            report["apple_rejection"] = client.last_api_rejection
            report["followup"] = "Inspect Apple's association rejection, including any declaration/compliance requirement it identifies; no declaration was answered."
        save_report(report_path, report)
        raise InventoryError(report["error"]) from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply-draft", action="store_true", help="Select only validated Esha build 2 on the empty draft relationship.")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    path = root / "apps/esha/artifacts/apple-build-selection" / REPORT_FILE
    try:
        save_report(path, new_report(None, args.apply_draft))
        require(importlib.metadata.version("codemagic-cli-tools") == CLI_VERSION, "pinned_cli_version_required")
        require(os.environ.get("ESHA_APP_STORE_ID") == APP_ID, "esha_app_id_environment_mismatch")
        require((Path(sys.executable).parent / "app-store-connect").is_file(), "pinned_cli_python_required")
        require(all(os.environ.get(name) for name in ("APP_STORE_CONNECT_KEY_IDENTIFIER", "APP_STORE_CONNECT_ISSUER_ID",
                                                      "APP_STORE_CONNECT_PRIVATE_KEY")), "integration_credentials_unavailable")
        commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], stderr=subprocess.PIPE).decode().strip()
        with tempfile.TemporaryDirectory(prefix="esha-build-selection-auth-") as temporary:
            previous_temp = tempfile.tempdir
            tempfile.tempdir = temporary
            try:
                from codemagic.apple.app_store_connect import AppStoreConnectApiClient
                from codemagic.tools.app_store_connect.arguments import Types
                values = [argument.from_environment_variable_default().value for argument in (
                    Types.KeyIdentifierArgument, Types.IssuerIdArgument, Types.PrivateKeyArgument)]
                authenticator = AppStoreConnectApiClient(*values, unauthorized_request_retries=0,
                                                        server_error_retries=0, enable_jwt_cache=False)
                headers = authenticator.generate_auth_headers()
                report = select_build(BuildSelectionClient(lambda: dict(headers)), apply_draft=args.apply_draft,
                                      report_path=path, source_commit=commit)
            finally:
                tempfile.tempdir = previous_temp
    except Exception:
        try:
            report = json.loads(path.read_text())
            if report.get("status") == "checking":
                report.update(status="local_setup_failed", error="local_setup_failed_details_withheld")
                save_report(path, report)
        except Exception:
            pass
        print("Esha build selection stopped; inspect the sanitized receipt. No PATCH retry was attempted.", file=sys.stderr)
        return 1
    print(f"Esha build selection: {report['status']}. Saved {REPORT_FILE}; no submission or publishing performed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
