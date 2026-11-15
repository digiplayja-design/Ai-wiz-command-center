#!/usr/bin/env python3
"""Plan Esha's exact subscription draft; --apply-draft creates only missing parts.

Current Apple OpenAPI 4.6: subscription/group versions and v2 localizations;
v1 product, price and introductory-offer resources. Only an absent USA UPFRONT
availability may be created. No PATCH, DELETE, submission, existing availability
replacement, agreement action, backend activation, or POST retry.
UPFRONT pays the full ONE_MONTH period; MONTHLY would be a 12-month commitment.
https://developer.apple.com/documentation/appstoreconnectapi/working-with-subscription-versions
https://developer.apple.com/documentation/appstoreconnectapi/working-with-subscription-group-versions
https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip
"""

from __future__ import annotations

import argparse
import datetime as dt
from decimal import Decimal, InvalidOperation
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
    InventoryError, MAX_REQUESTS, MAX_RESPONSE_BYTES, MAX_SECONDS,
    linkage, require, resource, save_report,
)


REPORT_FILE = "Esha-Apple-subscription-draft-verification.json"
PRODUCT_ID = "com.korlixdeveloper.esha.monthly"
GROUP_NAME = "Esha Membership"
PRODUCT_NAME = "Esha Membership Monthly"
DESCRIPTION = "Monthly access to Esha beauty features."
STAGES = (
    "group", "group_version", "group_localization", "subscription",
    "subscription_version", "subscription_localization", "usa_availability", "usa_price", "usa_trial",
)
# POST destinations are constants. No supplied URLs or JSON bodies are accepted.
CREATES = {
    "group": ("/v1/subscriptionGroups", "subscriptionGroups", "apps", "app"),
    "group_version": ("/v1/subscriptionGroupVersions", "subscriptionGroupVersions", "subscriptionGroups", "subscriptionGroup"),
    "group_localization": ("/v2/subscriptionGroupLocalizations", "subscriptionGroupLocalizations", "subscriptionGroupVersions", "version"),
    "subscription": ("/v1/subscriptions", "subscriptions", "subscriptionGroups", "group"),
    "subscription_version": ("/v1/subscriptionVersions", "subscriptionVersions", "subscriptions", "subscription"),
    "subscription_localization": ("/v2/subscriptionLocalizations", "subscriptionLocalizations", "subscriptionVersions", "version"),
    "usa_availability": ("/v1/subscriptionPlanAvailabilities", "subscriptionPlanAvailabilities", "subscriptions", "subscription"),
    "usa_price": ("/v1/subscriptionPrices", "subscriptionPrices", "subscriptions", "subscription"),
    "usa_trial": ("/v1/subscriptionIntroductoryOffers", "subscriptionIntroductoryOffers", "subscriptions", "subscription"),
}
PARENT_STAGE = {
    "group": None, "group_version": "group", "group_localization": "group_version",
    "subscription": "group", "subscription_version": "subscription",
    "subscription_localization": "subscription_version", "usa_availability": "subscription", "usa_price": "subscription",
    "usa_trial": "subscription",
}


def availability_body(subscription_id):
    return {"data": {"type": "subscriptionPlanAvailabilities",
            "attributes": {"planType": "UPFRONT", "availableInNewTerritories": False},
            "relationships": {"subscription": {"data": {"type": "subscriptions", "id": subscription_id}},
                "availableTerritories": {"data": [{"type": "territories", "id": "USA"}]}}}}


def expected_spec():
    return {
        "schema_version": 1, "app_id": APP_ID, "bundle_id": BUNDLE_ID, "sku": SKU,
        "group_reference_name": GROUP_NAME, "group_display_name": GROUP_NAME,
        "product_id": PRODUCT_ID, "subscription_reference_name": PRODUCT_NAME,
        "subscription_display_name": PRODUCT_NAME, "subscription_description": DESCRIPTION,
        "subscription_period": "ONE_MONTH", "family_sharable": False, "group_level": 1,
        "locale": "en-US", "territory": "USA", "currency": "USD", "customer_price": "4.99",
        "payment_plan_type": "UPFRONT", "offer_mode": "FREE_TRIAL",
        "offer_duration": "THREE_DAYS", "offer_number_of_periods": 1,
        "offer_start_date": None, "offer_end_date": None, "availability_action": "create_usa_upfront_only_if_absent",
        "availability_create_body": availability_body("$subscription_id"),
        "review_submission": False, "backend_activation": False, "agreement_changes": False,
    }


def validate_spec(spec):
    # Canonical JSON also distinguishes true from 1 and false from 0.
    require(json.dumps(spec, sort_keys=True) == json.dumps(expected_spec(), sort_keys=True),
            "subscription_spec_outside_exact_authorized_draft")


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def attributes_match(item, expected, reason):
    attrs = item["attributes"]
    require(all(key in attrs and type(attrs[key]) is type(value) and attrs[key] == value
                for key, value in expected.items()), reason)


def one(values, reason):
    require(len(values) <= 1, reason)
    return values[0] if values else None


def date_value(value):
    if value is None:
        return None
    require(isinstance(value, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", value), "invalid_schedule_date")
    try:
        return dt.date.fromisoformat(value)
    except ValueError:
        raise InventoryError("invalid_schedule_date") from None


def editable_version(client, parent_kind, parent_id):
    values = client.read(parent_kind, parent_id, "versions").values
    require(all(value["attributes"].get("state") == "PREPARE_FOR_SUBMISSION" for value in values),
            "non_draft_subscription_metadata_version")
    return one(values, "ambiguous_draft_subscription_metadata_versions")


def matching_locale(client, version, expected):
    values = client.read(version["type"], version["id"], "localizations").values
    require(all(isinstance(value["attributes"].get("locale"), str) and value["attributes"]["locale"]
                for value in values), "incomplete_localization_identity")
    item = one([value for value in values if value["attributes"].get("locale") == "en-US"],
               "duplicate_en_us_localizations")
    if item:
        attributes_match(item, expected, "conflicting_existing_en_us_localization")
        if item["type"] == "subscriptionGroupLocalizations":
            require(item["attributes"].get("customAppName") in (None, ""), "conflicting_custom_app_name")
    return item


def inspect_target(client, *, today=None):
    """A complete fresh inventory; unavailable reads never mean absence."""
    today = today or dt.datetime.now(dt.timezone.utc).date()
    client.inventory = None
    client.identity_verified = False
    client.bound.clear()
    client.parents.clear()
    client.verify_identity()
    result = {stage: None for stage in STAGES}
    result.update(price_point=None, availability=[], inspected_on=today.isoformat())
    groups = client.read("apps", APP_ID, "subscriptionGroups").values
    require(all(isinstance(value["attributes"].get("referenceName"), str) and value["attributes"]["referenceName"]
                for value in groups), "incomplete_subscription_group_identity")
    group = one([value for value in groups if value["attributes"].get("referenceName") == GROUP_NAME],
                "ambiguous_esha_membership_groups")
    matches, target_group_products = [], []
    for candidate in groups:
        products = client.read("subscriptionGroups", candidate["id"], "subscriptions").values
        require(all(isinstance(value["attributes"].get("productId"), str) and value["attributes"]["productId"]
                    for value in products), "incomplete_subscription_product_identity")
        if group and candidate["id"] == group["id"]:
            target_group_products = products
        matches.extend((candidate, value) for value in products if value["attributes"].get("productId") == PRODUCT_ID)
    pair = one(matches, "duplicate_esha_product_across_app_groups")
    if pair:
        require(group is not None and pair[0]["id"] == group["id"], "esha_product_in_different_group")
        result["subscription"] = pair[1]
    if group:
        require(all(value["attributes"].get("productId") == PRODUCT_ID for value in target_group_products),
                "unexpected_product_in_target_membership_group")
        result["group"] = group
        version = editable_version(client, "subscriptionGroups", group["id"])
        result["group_version"] = version
        if version:
            result["group_localization"] = matching_locale(client, version, {"locale": "en-US", "name": GROUP_NAME})
    subscription = result["subscription"]
    if subscription:
        attrs = subscription["attributes"]
        attributes_match(subscription, {"productId": PRODUCT_ID, "name": PRODUCT_NAME,
                         "subscriptionPeriod": "ONE_MONTH", "familySharable": False, "groupLevel": 1},
                         "conflicting_existing_subscription_settings")
        require(attrs.get("state") in {"MISSING_METADATA", "READY_TO_SUBMIT"}, "subscription_not_in_draft_state")
        sid = subscription["id"]
        version = editable_version(client, "subscriptions", sid)
        result["subscription_version"] = version
        if version:
            result["subscription_localization"] = matching_locale(client, version, {
                "locale": "en-US", "name": PRODUCT_NAME, "description": DESCRIPTION})

        points = client.read("subscriptions", sid, "pricePoints")
        territory = points.included.get(("territories", "USA"))
        require(territory and territory["attributes"].get("currency") == "USD", "usa_usd_price_points_not_verified")
        matching_points = []
        for point in points.values:
            require(linkage(point, "territory", "territories") == "USA", "price_point_territory_mismatch")
            try:
                price = Decimal(point["attributes"].get("customerPrice", "invalid"))
            except (InvalidOperation, TypeError, ValueError):
                raise InventoryError("invalid_price_point_amount") from None
            require(price.is_finite(), "invalid_price_point_amount")
            if price == Decimal("4.99"):
                matching_points.append(point)
        result["price_point"] = one(matching_points, "ambiguous_usa_4_99_price_point")
        require(result["price_point"] is not None, "usa_4_99_price_point_unavailable")

        prices = client.read("subscriptions", sid, "prices").values
        price = one(prices, "ambiguous_or_conflicting_usa_price_schedule")
        if price:
            require(linkage(price, "territory", "territories") == "USA"
                    and linkage(price, "subscriptionPricePoint", "subscriptionPricePoints") == result["price_point"]["id"],
                    "conflicting_existing_usa_price")
            require(price["attributes"].get("planType") == "UPFRONT"
                    and price["attributes"].get("preserved") is False
                    and "startDate" in price["attributes"], "unverified_regular_subscription_price")
            start = date_value(price["attributes"]["startDate"])
            require(start is None or start <= today, "future_regular_price_requires_review")
            result["usa_price"] = price

        offers = client.read("subscriptions", sid, "introductoryOffers").values
        offer = one(offers, "ambiguous_or_conflicting_usa_introductory_offers")
        if offer:
            require(linkage(offer, "territory", "territories") == "USA", "introductory_offer_territory_mismatch")
            attributes_match(offer, {"offerMode": "FREE_TRIAL", "duration": "THREE_DAYS", "numberOfPeriods": 1},
                             "conflicting_existing_usa_trial")
            oa = offer["attributes"]
            require(oa.get("targetSubscriptionPlanType") in (None, "UPFRONT"), "conflicting_trial_plan_type")
            require("startDate" in oa and "endDate" in oa and oa["endDate"] is None, "conflicting_trial_date_window")
            start = date_value(oa["startDate"])
            require(start is None or start <= today, "future_trial_requires_review")
            result["usa_trial"] = offer

        availabilities = client.read("subscriptions", sid, "planAvailabilities").values
        availability = one(availabilities, "ambiguous_existing_subscription_availability")
        if availability:
            territories = client.read("subscriptionPlanAvailabilities", availability["id"], "availableTerritories").values
            pa = availability["attributes"]
            require(pa.get("planType") == "UPFRONT" and pa.get("availableInNewTerritories") is False
                    and [value["id"] for value in territories] == ["USA"], "conflicting_existing_subscription_availability")
            result["usa_availability"] = availability
            result["availability"].append({"id": availability["id"], "plan_type": pa["planType"],
                "available_in_new_territories": pa.get("availableInNewTerritories"),
                "territories": sorted(value["id"] for value in territories)})
    client.inventory = result
    return result


def relation(kind, identifier):
    return {"data": {"type": kind, "id": identifier}}


def operation(stage, snapshot):
    require(stage in CREATES and snapshot[stage] is None, "operation_not_missing_or_allowlisted")
    path, kind, parent_kind, parent_field = CREATES[stage]
    parent = PARENT_STAGE[stage]
    pid = APP_ID if parent is None else snapshot[parent]["id"] if snapshot[parent] else None
    attributes = {
        "group": {"referenceName": GROUP_NAME},
        "group_localization": {"locale": "en-US", "name": GROUP_NAME},
        "subscription": {"name": PRODUCT_NAME, "productId": PRODUCT_ID, "subscriptionPeriod": "ONE_MONTH",
                         "familySharable": False, "groupLevel": 1},
        "subscription_localization": {"locale": "en-US", "name": PRODUCT_NAME, "description": DESCRIPTION},
        "usa_price": {"startDate": None, "planType": "UPFRONT"},
        "usa_trial": {"duration": "THREE_DAYS", "numberOfPeriods": 1, "offerMode": "FREE_TRIAL",
                      "startDate": None, "endDate": None, "targetSubscriptionPlanType": "UPFRONT"},
    }.get(stage)
    data = {"type": kind, "relationships": {parent_field: relation(parent_kind, pid)}}
    if attributes is not None:
        data["attributes"] = attributes
    if stage == "usa_price":
        point = snapshot["price_point"]
        data["relationships"]["subscriptionPricePoint"] = relation("subscriptionPricePoints", point["id"] if point else None)
    if stage == "usa_trial":
        data["relationships"]["territory"] = relation("territories", "USA")
    if stage == "usa_availability":
        data = availability_body(pid)["data"]
    resolved = pid is not None and (stage != "usa_price" or snapshot["price_point"] is not None)
    return {"stage": stage, "method": "POST", "path": path, "body": {"data": data}, "resolved": resolved,
            "depends_on": parent, "price_point_lookup_required": stage == "usa_price" and snapshot["price_point"] is None}


def plan(snapshot):
    return [operation(stage, snapshot) for stage in STAGES if snapshot[stage] is None]


class AmbiguousCreate(InventoryError):
    """The write may have succeeded. Only fresh GET reconciliation is allowed."""


class AppleDraftClient(AppleReadClient):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.inventory = None
        self.attempted_stages = set()

    def create(self, stage):
        require(self.identity_verified and self.inventory is not None, "fresh_inventory_required_before_create")
        require(stage not in self.attempted_stages, "post_retry_forbidden")
        op = operation(stage, self.inventory)
        require(op["resolved"], "unresolved_create_dependency")
        _, _, parent_kind, parent_field = CREATES[stage]
        pid = op["body"]["data"]["relationships"][parent_field]["data"]["id"]
        require((parent_kind, pid) in self.bound, "create_parent_not_bound_to_esha")
        if stage == "usa_price":
            point_id = self.inventory["price_point"]["id"]
            require(("subscriptionPricePoints", point_id) in self.bound, "price_point_not_bound_to_esha")
        require(not self.stopped_reason, self.stopped_reason or "requests_stopped")
        require(self.request_count < MAX_REQUESTS and self.clock() - self.started < MAX_SECONDS,
                "inventory_request_or_time_budget_exhausted")
        self.attempted_stages.add(stage)
        self.inventory = None  # A second POST requires another complete inventory.
        self.request_count += 1
        request = urllib.request.Request(API_ORIGIN + op["path"], method="POST",
            data=json.dumps(op["body"]).encode(), headers={**self.auth_headers(),
                "Accept": "application/json", "Content-Type": "application/json"})
        try:
            with self.open_request(request, timeout=20) as response:
                if response.getcode() != 201:
                    raise AmbiguousCreate("unexpected_create_status_reconcile_only")
                raw = response.read(MAX_RESPONSE_BYTES + 1)
        except urllib.error.HTTPError as error:
            status = error.code
            error.close()
            if status in (401, 403, 429):
                self.stopped_reason = f"http_{status}_further_requests_stopped"
            if status >= 500 or status == 408:
                raise AmbiguousCreate("create_http_failure_reconcile_only") from None
            raise InventoryError(f"create_rejected_http_{status}_no_retry") from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise AmbiguousCreate("create_transport_uncertain_reconcile_only") from None
        try:
            require(len(raw) <= MAX_RESPONSE_BYTES, "create_response_size_limit")
            document = json.loads(raw)
            require(isinstance(document, dict) and "errors" not in document, "invalid_create_document")
            created = resource(document.get("data"), CREATES[stage][1])
        except (InventoryError, ValueError, UnicodeError):
            raise AmbiguousCreate("create_response_unverified_reconcile_only") from None
        return created["id"]


def observations(snapshot):
    return {"resource_ids": {stage: value["id"] for stage in STAGES if (value := snapshot[stage])},
            "usa_price_point_id": snapshot["price_point"]["id"] if snapshot["price_point"] else None,
            "availability": {"scope": "usa_upfront_only_no_new_territories", "configured": bool(snapshot["availability"]),
                             "plans": snapshot["availability"]},
            "real_device_purchase_verified": False, "agreement_status": "not_inspected"}


def check_pins(snapshot, pins):
    require(all(snapshot[stage] is not None and snapshot[stage]["id"] == identifier for stage, identifier in pins.items()),
            "resource_identity_changed_during_draft_preparation")


def new_report(source_commit, apply_draft):
    return {"schema_version": 1, "status": "checking", "mode": "apply_draft" if apply_draft else "read_only_plan",
            "started_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "source_commit": source_commit,
            "app_id": APP_ID, "bundle_id": BUNDLE_ID, "sku": SKU, "product_id": PRODUCT_ID,
            "identity_verified": False, "planned_operations": [], "operation_evidence": [],
            "availability_changed": False, "review_submitted": False, "published": False,
            "backend_activated": False, "agreements_changed": False, "post_retries": 0}


def prepare(client, spec, *, apply_draft, report_path, source_commit, today=None):
    report_path = Path(report_path)
    report = new_report(source_commit, apply_draft)
    save_report(report_path, report)
    try:
        validate_spec(spec)
        require(isinstance(source_commit, str) and re.fullmatch(r"[a-f0-9]{40}", source_commit), "invalid_source_commit")
        report["spec_sha256"] = digest(spec)
        initial = inspect_target(client, today=today)
        report["identity_verified"] = True
        report["initial_observations"] = observations(initial)
        report["planned_operations"] = plan(initial)
        save_report(report_path, report)
        if not apply_draft:
            report["status"] = "plan_only_no_changes"
        else:
            permitted = {op["stage"] for op in report["planned_operations"]}
            pins = {stage: value["id"] for stage in STAGES if (value := initial[stage])}
            current = inspect_target(client, today=today)
            for _ in range(len(STAGES) + 1):
                # Initial recheck, then each POST's complete GET readback supplies
                # the fresh identity/inventory immediately preceding the next POST.
                check_pins(current, pins)
                pending = plan(current)
                require(all(op["stage"] in permitted for op in pending), "unplanned_resource_disappeared")
                if not pending:
                    report["final_observations"] = observations(current)
                    report["status"] = "subscription_draft_prepared"
                    break
                op = pending[0]
                require(op["resolved"], "unresolved_first_create_operation")
                entry = {"stage": op["stage"], "request": op, "request_sha256": digest(op["body"]),
                         "attempted_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "outcome": "attempting_once"}
                report["operation_evidence"].append(entry)
                save_report(report_path, report)
                created_id = None
                try:
                    created_id = client.create(op["stage"])
                    entry.update(outcome="created_response_received", response_resource_id=created_id)
                except AmbiguousCreate as error:
                    entry.update(outcome="ambiguous_post_get_reconciliation_only", reason=str(error))
                except InventoryError as error:
                    entry.update(outcome="create_stopped_no_retry", reason=str(error))
                    save_report(report_path, report)
                    raise
                save_report(report_path, report)
                after = inspect_target(client, today=today)
                check_pins(after, pins)
                item = after[op["stage"]]
                require(item is not None, "post_outcome_unconfirmed_stop_without_retry")
                require(created_id is None or item["id"] == created_id, "created_resource_id_not_found_in_scoped_readback")
                entry.update(outcome="created_and_read_back" if created_id else "matching_resource_reconciled_after_ambiguous_post",
                             verified_resource_id=item["id"], created_by_this_run=True if created_id else "unknown",
                             verified_at_utc=dt.datetime.now(dt.timezone.utc).isoformat())
                if op["stage"] == "usa_availability":
                    report["availability_changed"] = True if created_id else "unknown_post_reconciled"
                # Pin every resource now observed, including any automatically created children.
                pins.update({stage: value["id"] for stage in STAGES if (value := after[stage])})
                save_report(report_path, report)
                current = after
            else:
                raise InventoryError("draft_operation_budget_exhausted")
        report["request_count"] = client.request_count
        report["completed_at_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        save_report(report_path, report)
        return report
    except Exception as error:
        report.update(status="stopped_review_partial_progress", request_count=client.request_count,
                      identity_verified=client.identity_verified,
                      error=str(error) if isinstance(error, InventoryError) else "local_processing_failed_details_withheld")
        save_report(report_path, report)
        raise InventoryError(report["error"]) from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply-draft", action="store_true", help="Create only missing exact Esha draft components.")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    path = root / "apps/esha/artifacts/apple-subscription" / REPORT_FILE
    try:
        save_report(path, new_report(None, args.apply_draft))
        spec = json.loads((root / "apps/esha/release/apple-subscription-draft.json").read_text())
        validate_spec(spec)
        require(importlib.metadata.version("codemagic-cli-tools") == CLI_VERSION, "pinned_cli_version_required")
        require(os.environ.get("ESHA_APP_STORE_ID") == APP_ID, "esha_app_id_environment_mismatch")
        require((Path(sys.executable).parent / "app-store-connect").is_file(), "pinned_cli_python_required")
        require(all(os.environ.get(name) for name in ("APP_STORE_CONNECT_KEY_IDENTIFIER", "APP_STORE_CONNECT_ISSUER_ID",
                                                      "APP_STORE_CONNECT_PRIVATE_KEY")), "integration_credentials_unavailable")
        commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], stderr=subprocess.PIPE).decode().strip()
        with tempfile.TemporaryDirectory(prefix="esha-subscription-auth-") as temporary:
            previous_temp = tempfile.tempdir
            tempfile.tempdir = temporary
            try:
                from codemagic.apple.app_store_connect import AppStoreConnectApiClient
                from codemagic.tools.app_store_connect.arguments import Types
                auth_values = [argument.from_environment_variable_default().value for argument in (
                    Types.KeyIdentifierArgument, Types.IssuerIdArgument, Types.PrivateKeyArgument)]
                authenticator = AppStoreConnectApiClient(*auth_values, unauthorized_request_retries=0,
                                                        server_error_retries=0, enable_jwt_cache=False)
                headers = authenticator.generate_auth_headers()
                report = prepare(AppleDraftClient(lambda: dict(headers)), spec, apply_draft=args.apply_draft,
                                 report_path=path, source_commit=commit)
            finally:
                tempfile.tempdir = previous_temp
    except Exception as error:
        # Prepare writes operation receipts itself; setup failures must also replace any prior success.
        try:
            report = json.loads(path.read_text())
            if report.get("status") == "checking":
                report.update(status="local_setup_failed", error=str(error) if isinstance(error, InventoryError)
                              else "local_setup_failed_details_withheld")
                save_report(path, report)
        except Exception:
            pass
        print("Esha subscription draft stopped. Inspect the sanitized receipt; no POST retry was attempted.", file=sys.stderr)
        return 1
    print(f"Esha subscription draft: {report['status']}. Saved {REPORT_FILE}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
