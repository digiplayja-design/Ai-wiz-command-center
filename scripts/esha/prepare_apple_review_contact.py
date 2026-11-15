#!/usr/bin/env python3
"""Plan Esha's approved review contact; --apply-draft fills empty contact fields.

Only an existing review-details record on Esha's 1.0.0 editable iOS draft is
eligible. No account credentials, notes, declarations, submission or publishing
are changed. Official Apple OpenAPI 4.6 contract: PATCH returns HTTP 200.
https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-appstorereviewdetails-_id_
"""

from __future__ import annotations

import argparse
import copy
from dataclasses import dataclass, field
import datetime as dt
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
    InventoryError, MAX_REQUESTS, MAX_SECONDS, PATH_ID, enum_value,
    present, require, save_report,
)


VERSION = "1.0.0"
REPORT_FILE = "Esha-Apple-review-contact-verification.json"
CONTACT = {
    "contactFirstName": "Ricardo",
    "contactLastName": "Bailey",
    "contactEmail": "support@korlixdeveloper.com",
    "contactPhone": "+16148942317",
}
PROTECTED_FIELDS = ("demoAccountName", "demoAccountPassword", "demoAccountRequired", "notes")


class AmbiguousContactUpdate(InventoryError):
    """Only GET reconciliation is permitted after an uncertain PATCH."""


@dataclass
class ReviewSnapshot:
    observation: dict
    changes: dict
    # Keep existing credentials and notes in memory only, including on repr.
    protected_attributes: dict = field(repr=False)


def contact_body(snapshot):
    require(snapshot.changes and all(key in CONTACT and value == CONTACT[key]
            for key, value in snapshot.changes.items()), "unapproved_contact_patch_attributes")
    return {"data": {"type": "appStoreReviewDetails", "id": snapshot.observation["review_detail_id"],
                     "attributes": dict(snapshot.changes)}}


class ReviewContactClient(AppleReadClient):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.review_snapshot = None
        self.latest_observation = {}
        self.patch_attempted = False
        self.last_api_rejection = None

    def patch_once(self):
        snapshot = self.review_snapshot
        require(self.identity_verified and snapshot is not None, "fresh_review_contact_inventory_required")
        require(not self.patch_attempted, "contact_patch_retry_forbidden")
        observation = snapshot.observation
        identifier, version_id = observation["review_detail_id"], observation["version_id"]
        require(PATH_ID.fullmatch(identifier)
                and ("appStoreReviewDetails", identifier) in self.bound
                and ("appStoreVersions", version_id) in self.bound
                and self.parents.get(("appStoreReviewDetails", identifier, "appStoreVersions")) == version_id,
                "review_detail_not_bound_to_esha_version")
        body = contact_body(snapshot)
        require(not self.stopped_reason, self.stopped_reason or "requests_stopped")
        require(self.request_count < MAX_REQUESTS and self.clock() - self.started < MAX_SECONDS,
                "inventory_request_or_time_budget_exhausted")
        path = f"/v1/appStoreReviewDetails/{identifier}"
        self.patch_attempted = True
        self.review_snapshot = None
        self.request_count += 1
        request = urllib.request.Request(API_ORIGIN + path, method="PATCH", data=json.dumps(body).encode(),
            headers={**self.auth_headers(), "Accept": "application/json", "Content-Type": "application/json"})
        try:
            with self.open_request(request, timeout=20) as response:
                # The response may contain demo credentials. Never log it;
                # fresh bound GET readback verifies the result instead.
                if response.getcode() != 200:
                    raise AmbiguousContactUpdate("unexpected_patch_status_get_reconciliation_only")
        except urllib.error.HTTPError as error:
            status = error.code
            error.close()
            self.last_api_rejection = {"http_status": status, "details_withheld": True}
            if status in (401, 403, 429):
                self.stopped_reason = f"http_{status}_further_requests_stopped"
            if status >= 500 or status == 408:
                raise AmbiguousContactUpdate("contact_patch_http_failure_get_reconciliation_only") from None
            raise InventoryError(f"review_contact_rejected_http_{status}_no_retry") from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise AmbiguousContactUpdate("contact_patch_transport_uncertain_get_reconciliation_only") from None


def inspect_contact(client):
    client.review_snapshot = None
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
    states = [version["attributes"][key] for key in ("appVersionState", "appStoreState")
              if version["attributes"].get(key) is not None]
    observation = {"version_id": version["id"], "version": VERSION,
                   "version_states": [enum_value(state) for state in states]}
    client.latest_observation = observation
    require(states and all(state == "PREPARE_FOR_SUBMISSION" for state in states), "app_version_not_editable_draft")
    details = client.read("appStoreVersions", version["id"], "appStoreReviewDetail").values
    require(len(details) == 1, "existing_review_detail_required_no_creation")
    detail = details[0]
    require(PATH_ID.fullmatch(detail["id"]), "unsafe_review_detail_id")
    attributes = detail["attributes"]
    observation["review_detail_id"] = detail["id"]
    require(all(key in attributes for key in (*CONTACT, *PROTECTED_FIELDS)), "incomplete_review_detail_attributes")
    require(all(attributes[key] is None or isinstance(attributes[key], str)
                for key in ("demoAccountName", "demoAccountPassword", "notes"))
            and (attributes["demoAccountRequired"] is None or type(attributes["demoAccountRequired"]) is bool),
            "invalid_protected_review_attribute_type")
    statuses, changes = {}, {}
    for key, approved in CONTACT.items():
        value = attributes[key]
        require(value is None or isinstance(value, str), "invalid_contact_attribute_type")
        empty = value is None or not value.strip()
        statuses[key] = "empty" if empty else "approved" if value == approved else "conflict"
        if empty:
            changes[key] = approved
    observation.update(contact_field_states=statuses,
                       demo_account_name_present=present(attributes, "demoAccountName"),
                       demo_account_password_present=present(attributes, "demoAccountPassword"),
                       review_notes_present=present(attributes, "notes"))
    require("conflict" not in statuses.values(), "nonempty_review_contact_conflict_no_overwrite")
    protected = copy.deepcopy({key: value for key, value in attributes.items() if key not in CONTACT})
    snapshot = ReviewSnapshot(copy.deepcopy(observation), changes, protected)
    client.review_snapshot = snapshot
    return snapshot


def same_record_and_protected(initial, current):
    require(all(current.observation[key] == initial.observation[key] for key in ("version_id", "review_detail_id")),
            "review_contact_resource_identity_changed")
    require(json.dumps(current.protected_attributes, sort_keys=True, allow_nan=False)
            == json.dumps(initial.protected_attributes, sort_keys=True, allow_nan=False),
            "non_contact_attributes_changed_or_incomplete_readback")


def new_report(source_commit, apply_draft):
    return {"schema_version": 1, "status": "checking", "mode": "apply_draft" if apply_draft else "read_only_plan",
            "started_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "source_commit": source_commit,
            "apple_app_id": APP_ID, "bundle_id": BUNDLE_ID, "sku": SKU, "target_version": VERSION,
            "identity_verified": False, "planned_operation": None, "patch_attempts": 0, "patch_retries": 0,
            "contact_changed_by_this_run": False, "non_contact_attributes_unchanged": None,
            "demo_credentials_unchanged": None, "review_submitted": False, "published": False}


def operation(snapshot):
    return None if not snapshot.changes else {"method": "PATCH",
        "path": f"/v1/appStoreReviewDetails/{snapshot.observation['review_detail_id']}", "body": contact_body(snapshot)}


def prepare_contact(client, *, apply_draft, report_path, source_commit):
    report_path = Path(report_path)
    report = new_report(source_commit, apply_draft)
    save_report(report_path, report)
    try:
        require(isinstance(source_commit, str) and re.fullmatch(r"[a-f0-9]{40}", source_commit), "invalid_source_commit")
        initial = inspect_contact(client)
        report.update(identity_verified=True, initial_observation=initial.observation, planned_operation=operation(initial))
        save_report(report_path, report)
        if not apply_draft:
            report["status"] = "plan_only_no_changes" if initial.changes else "already_configured_verified"
        else:
            current = inspect_contact(client)
            same_record_and_protected(initial, current)
            require(not any(initial.observation["contact_field_states"][key] == "approved"
                            and current.observation["contact_field_states"][key] != "approved" for key in CONTACT),
                    "approved_contact_disappeared_before_write")
            report["planned_operation"] = operation(current)
            if not current.changes:
                report.update(status="already_configured_verified", final_observation=current.observation,
                              non_contact_attributes_unchanged=True, demo_credentials_unchanged=True)
            else:
                report["intent"] = {"recorded_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                                    "observation_before_patch": current.observation,
                                    "operation": report["planned_operation"], "outcome": "attempting_once"}
                report["contact_changed_by_this_run"] = "unknown"
                save_report(report_path, report)
                ambiguous = False
                try:
                    client.patch_once()
                    report["intent"]["outcome"] = "http_200_received_readback_required"
                except AmbiguousContactUpdate as error:
                    ambiguous = True
                    report["intent"].update(outcome="ambiguous_patch_get_reconciliation_only", reason=str(error))
                report["patch_attempts"] = int(client.patch_attempted)
                save_report(report_path, report)
                after = inspect_contact(client)
                same_record_and_protected(initial, after)
                require(not after.changes, "contact_update_not_confirmed_stop_without_retry")
                report.update(status="contact_reconciled_after_ambiguous_patch" if ambiguous else "review_contact_updated_and_read_back",
                              final_observation=after.observation,
                              contact_changed_by_this_run="unknown" if ambiguous else True,
                              non_contact_attributes_unchanged=True, demo_credentials_unchanged=True)
                report["intent"]["outcome"] = "approved_contact_and_preserved_attributes_verified"
        report.update(request_count=client.request_count, completed_at_utc=dt.datetime.now(dt.timezone.utc).isoformat())
        save_report(report_path, report)
        return report
    except Exception as error:
        report.update(status="stopped_review_partial_progress", patch_attempts=int(client.patch_attempted),
                      request_count=client.request_count, identity_verified=client.identity_verified,
                      contact_changed_by_this_run="unknown" if client.patch_attempted else False,
                      latest_observation=client.latest_observation,
                      error=str(error) if isinstance(error, InventoryError) else "local_processing_failed_details_withheld")
        if client.last_api_rejection:
            report["apple_rejection"] = client.last_api_rejection
        save_report(report_path, report)
        raise InventoryError(report["error"]) from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply-draft", action="store_true", help="Fill only empty approved contact fields on the existing draft.")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    path = root / "apps/esha/artifacts/apple-review-contact" / REPORT_FILE
    try:
        save_report(path, new_report(None, args.apply_draft))
        require(importlib.metadata.version("codemagic-cli-tools") == CLI_VERSION, "pinned_cli_version_required")
        require(os.environ.get("ESHA_APP_STORE_ID") == APP_ID, "esha_app_id_environment_mismatch")
        require((Path(sys.executable).parent / "app-store-connect").is_file(), "pinned_cli_python_required")
        require(all(os.environ.get(name) for name in ("APP_STORE_CONNECT_KEY_IDENTIFIER", "APP_STORE_CONNECT_ISSUER_ID",
                                                      "APP_STORE_CONNECT_PRIVATE_KEY")), "integration_credentials_unavailable")
        commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], stderr=subprocess.PIPE).decode().strip()
        with tempfile.TemporaryDirectory(prefix="esha-review-contact-auth-") as temporary:
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
                report = prepare_contact(ReviewContactClient(lambda: dict(headers)), apply_draft=args.apply_draft,
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
        print("Esha review contact stopped; inspect the sanitized receipt. No PATCH retry was attempted.", file=sys.stderr)
        return 1
    print(f"Esha review contact: {report['status']}. Saved {REPORT_FILE}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
