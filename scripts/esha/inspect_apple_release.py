#!/usr/bin/env python3
"""Inspect only Esha's Apple release records; no Apple writes or submission.

Run with the existing integration and codemagic-cli-tools 0.69.0 Python. Only
sanitized observations are saved. A partial inventory is not release approval.
Current endpoint contracts: https://developer.apple.com/documentation/appstoreconnectapi
Subscription metadata follows the 4.4.1 version-based read endpoints; legacy
localizations are read only when no versioned metadata can be inventoried.
Primary schema references (verified 2026-11-15):
https://developer.apple.com/documentation/appstoreconnectapi/migrating-in-app-purchase-metadata-to-v2
https://developer.apple.com/documentation/appstoreconnectapi/get-v1-subscriptions-_id_-prices
https://developer.apple.com/documentation/appstoreconnectapi/get-v1-subscriptions-_id_-introductoryoffers
https://developer.apple.com/documentation/appstoreconnectapi/get-v1-appinfos-_id_-ageratingdeclaration
https://developer.apple.com/documentation/appstoreconnectapi/get-v1-appstoreversions-_id_-appstorereviewdetail
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import datetime as dt
from decimal import Decimal, InvalidOperation
import importlib.metadata
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

from prepare_ios_profile import APP_ID, BUNDLE_ID, CLI_VERSION, SKU


API_ORIGIN = "https://api.appstoreconnect.apple.com"
REPORT_FILE = "Esha-Apple-release-inventory.json"
PRODUCT_ID = "com.korlixdeveloper.esha.monthly"
TARGET_VERSION = "1.0.0"
PATH_ID = re.compile(r"[A-Za-z0-9_-]{1,128}\Z")
# Price-point IDs can be opaque base64 strings. They are never used in a URL.
OPAQUE_ID = re.compile(r"[\x21-\x7e]{1,512}\Z")
MAX_RESPONSE_BYTES = 4_000_000
MAX_REQUESTS = 160
MAX_PAGES = 10
MAX_ITEMS = 200
MAX_SECONDS = 300


class InventoryError(Exception):
    """Fixed reason codes only; never API bodies, URLs, contact or credentials."""


def require(condition, reason):
    if not condition:
        raise InventoryError(reason)


@dataclass(frozen=True)
class Route:
    kind: str
    many: bool = True
    parent_field: str | None = None
    query: tuple = ()
    included_types: tuple = ()


# Only child endpoints of resources already reached through Esha are allowed.
# No API-provided related URLs are followed. All query values are fixed here.
ROUTES = {
    ("apps", "appInfos"): Route("appInfos", parent_field="app"),
    ("apps", "appStoreVersions"): Route("appStoreVersions", parent_field="app"),
    ("apps", "builds"): Route("builds", parent_field="app"),
    ("apps", "subscriptionGroups"): Route("subscriptionGroups", parent_field="app"),
    ("appInfos", "ageRatingDeclaration"): Route("ageRatingDeclarations", False),
    ("appStoreVersions", "build"): Route("builds", False, "appStoreVersion"),
    ("appStoreVersions", "appStoreVersionLocalizations"):
        Route("appStoreVersionLocalizations", parent_field="appStoreVersion"),
    ("appStoreVersions", "appStoreReviewDetail"):
        Route("appStoreReviewDetails", False, "appStoreVersion"),
    ("appStoreVersionLocalizations", "appScreenshotSets"):
        Route("appScreenshotSets", parent_field="appStoreVersionLocalization"),
    ("appScreenshotSets", "appScreenshots"): Route("appScreenshots", parent_field="appScreenshotSet"),
    ("subscriptionGroups", "subscriptions"): Route("subscriptions", parent_field="group"),
    ("subscriptionGroups", "versions"): Route("subscriptionGroupVersions", parent_field="subscriptionGroup"),
    ("subscriptionGroups", "subscriptionGroupLocalizations"):
        Route("subscriptionGroupLocalizations", parent_field="subscriptionGroup"),
    ("subscriptionGroupVersions", "localizations"):
        Route("subscriptionGroupLocalizations", parent_field="version"),
    ("subscriptions", "versions"): Route("subscriptionVersions", parent_field="subscription"),
    ("subscriptions", "subscriptionLocalizations"):
        Route("subscriptionLocalizations", parent_field="subscription"),
    ("subscriptionVersions", "localizations"): Route("subscriptionLocalizations", parent_field="version"),
    ("subscriptionVersions", "images"): Route("subscriptionImages", parent_field="version"),
    ("subscriptions", "appStoreReviewScreenshot"):
        Route("subscriptionAppStoreReviewScreenshots", False, "subscription"),
    ("subscriptions", "prices"): Route(
        "subscriptionPrices", query=(("filter[territory]", "USA"),
        ("include", "subscriptionPricePoint,territory")),
        included_types=("subscriptionPricePoints", "territories")),
    ("subscriptions", "introductoryOffers"): Route(
        "subscriptionIntroductoryOffers", parent_field="subscription",
        query=(("filter[territory]", "USA"), ("include", "territory")),
        included_types=("territories",)),
}


def resource(value, kind, identifier=None):
    require(isinstance(value, dict) and value.get("type") == kind, "unexpected_resource_type")
    require(isinstance(value.get("id"), str) and OPAQUE_ID.fullmatch(value["id"]), "invalid_resource_id")
    require(identifier is None or value["id"] == identifier, "unexpected_resource_id")
    require(isinstance(value.get("attributes"), dict), "missing_resource_attributes")
    return value


def linkage(value, field, kind):
    relationships = value.get("relationships", {})
    require(isinstance(relationships, dict), "invalid_relationships_object")
    relation = relationships.get(field, {})
    require(isinstance(relation, dict), "invalid_relationship")
    data = relation.get("data")
    if data is None:
        return None
    require(isinstance(data, dict) and data.get("type") == kind
            and isinstance(data.get("id"), str) and OPAQUE_ID.fullmatch(data["id"]),
            "invalid_relationship_binding")
    return data["id"]


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


@dataclass
class Fetched:
    values: list
    included: dict
    many: bool


class AppleReadClient:
    """GET-only, identity-gated, parent-bound, paginated Apple reads."""

    def __init__(self, auth_headers, *, open_request=None, clock=time.monotonic):
        self.auth_headers = auth_headers
        self.open_request = open_request or urllib.request.build_opener(NoRedirects()).open
        self.clock, self.started = clock, clock()
        self.request_count = 0
        self.identity_verified = False
        self.bound = set()
        self.parents = {}
        self.stopped_reason = None

    def _request(self, url, expected_path, expected_query, *, next_page=False):
        parsed = urllib.parse.urlsplit(url)
        require(parsed.scheme == "https" and parsed.netloc == "api.appstoreconnect.apple.com"
                and parsed.path == expected_path and not parsed.fragment,
                "unapproved_origin_or_pagination_path")
        try:
            pairs = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True, strict_parsing=True)
        except ValueError:
            raise InventoryError("invalid_query_parameters") from None
        query = dict(pairs)
        require(len(query) == len(pairs), "duplicate_query_parameters")
        allowed = set(expected_query) | ({"cursor"} if next_page else set())
        def same_value(key, expected):
            actual = query.get(key)
            return (actual is not None and sorted(actual.split(",")) == sorted(expected.split(","))) if key == "include" else actual == expected
        require(set(query) <= allowed and all(same_value(k, v) for k, v in expected_query.items()),
                "pagination_changed_query_scope")
        if "cursor" in query:
            require(0 < len(query["cursor"]) <= 2048 and all(ord(c) >= 32 for c in query["cursor"]),
                    "invalid_pagination_cursor")
        require(not self.stopped_reason, self.stopped_reason or "reads_stopped")
        if self.request_count >= MAX_REQUESTS or self.clock() - self.started >= MAX_SECONDS:
            self.stopped_reason = "inventory_request_or_time_budget_exhausted"
            raise InventoryError(self.stopped_reason)
        self.request_count += 1
        # Authentication is generated only after origin/path/query validation.
        request = urllib.request.Request(url, headers={**self.auth_headers(), "Accept": "application/json"}, method="GET")
        try:
            with self.open_request(request, timeout=20) as response:
                require(response.getcode() == 200, "unexpected_http_status")
                raw = response.read(MAX_RESPONSE_BYTES + 1)
        except urllib.error.HTTPError as error:
            status = error.code
            error.close()
            if status in (401, 429):
                self.stopped_reason = f"http_{status}_further_reads_stopped"
            raise InventoryError(f"unavailable_http_{status}") from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise InventoryError("transport_unavailable_no_retry") from None
        require(len(raw) <= MAX_RESPONSE_BYTES, "response_size_limit_exceeded")
        try:
            document = json.loads(raw)
        except (ValueError, UnicodeError):
            raise InventoryError("invalid_json_response") from None
        require(isinstance(document, dict) and "data" in document and "errors" not in document,
                "incomplete_or_error_document")
        return document

    def verify_identity(self):
        path = f"/v1/apps/{APP_ID}"
        app = resource(self._request(API_ORIGIN + path, path, {})["data"], "apps", APP_ID)
        require(app["attributes"].get("bundleId") == BUNDLE_ID and app["attributes"].get("sku") == SKU,
                "esha_identity_mismatch")
        self.identity_verified = True
        self.bound.add(("apps", APP_ID))

    def read(self, parent_kind, parent_id, relationship):
        require(self.identity_verified, "esha_identity_not_verified")
        require((parent_kind, parent_id) in self.bound and isinstance(parent_id, str)
                and PATH_ID.fullmatch(parent_id), "resource_not_bound_to_esha")
        route = ROUTES.get((parent_kind, relationship))
        require(route is not None, "endpoint_not_allowlisted")
        path = f"/v1/{parent_kind}/{parent_id}/{relationship}"
        query = dict(route.query)
        if route.many:
            query["limit"] = "200"
        url = API_ORIGIN + path + ("?" + urllib.parse.urlencode(query) if query else "")
        values, included, seen_ids, seen_pages = [], {}, set(), set()
        total = None
        while url:
            require(url not in seen_pages and len(seen_pages) < MAX_PAGES, "cyclic_or_excessive_pagination")
            document = self._request(url, path, query, next_page=bool(seen_pages))
            seen_pages.add(url)
            data = document["data"]
            require(isinstance(data, list) if route.many else data is None or isinstance(data, dict),
                    "unexpected_relationship_cardinality")
            page = data if route.many else ([] if data is None else [data])
            for item in page:
                resource(item, route.kind)
                require(item["id"] not in seen_ids, "duplicate_resource_across_pages")
                seen_ids.add(item["id"])
                if route.parent_field:
                    backref = linkage(item, route.parent_field, parent_kind)
                    require(backref is None or backref == parent_id, "resource_parent_mismatch")
                old_parent = self.parents.get((route.kind, item["id"], parent_kind))
                require(old_parent is None or old_parent == parent_id, "resource_seen_under_different_parent")
                values.append(item)
            require(len(values) <= MAX_ITEMS, "resource_count_limit_exceeded")
            extras = document.get("included", [])
            require(isinstance(extras, list), "invalid_included_resources")
            for item in extras:
                if isinstance(item, dict) and item.get("type") in route.included_types:
                    resource(item, item["type"])
                    key = (item["type"], item["id"])
                    require(key not in included or included[key] == item, "inconsistent_included_resource")
                    included[key] = item
            if not route.many:
                break
            links = document.get("links")
            require(isinstance(links, dict), "missing_pagination_links")
            meta = document.get("meta", {})
            require(isinstance(meta, dict) and isinstance(meta.get("paging", {}), dict), "invalid_pagination_metadata")
            page_total = meta.get("paging", {}).get("total")
            if page_total is not None:
                require(type(page_total) is int and page_total >= 0 and (total is None or total == page_total),
                        "inconsistent_pagination_total")
                total = page_total
            next_link = links.get("next")
            require(next_link is None or isinstance(next_link, str) and next_link, "invalid_next_page")
            url = urllib.parse.urljoin(API_ORIGIN + path, next_link) if next_link else None
        require(total is None or total == len(values), "incomplete_paginated_collection")
        # Bind only after the complete collection and parent relationships pass.
        for item in values:
            self.bound.add((route.kind, item["id"]))
            self.parents[(route.kind, item["id"], parent_kind)] = parent_id
        return Fetched(values, included, route.many)


def text_value(value, maximum=200):
    return value if isinstance(value, str) and len(value) <= maximum and all(ord(c) >= 32 for c in value) else None


def enum_value(value):
    return value if isinstance(value, str) and re.fullmatch(r"[A-Z0-9_]{1,100}", value) else None


def bool_value(value):
    return value if type(value) is bool else None


def present(attributes, field):
    if field not in attributes:
        return None
    value = attributes[field]
    return isinstance(value, str) and bool(value.strip())


def all_present(values):
    return False if False in values else (None if None in values else True)


def asset_summary(values):
    states = []
    for item in values:
        delivery = item["attributes"].get("assetDeliveryState")
        states.append(enum_value(delivery.get("state")) if isinstance(delivery, dict) else None)
    counts = Counter(state or "UNKNOWN" for state in states)
    return {"count": len(values), "complete_count": counts.get("COMPLETE", 0), "delivery_state_counts": dict(counts)}


def localization(value, included):
    attributes = value["attributes"]
    result = {"id": value["id"], "locale": text_value(attributes.get("locale"), 20),
              "name_present": present(attributes, "name")}
    for field in ("description", "customAppName"):
        if field in attributes:
            result[field + "_present"] = present(attributes, field)
    if "state" in attributes:
        result["state"] = enum_value(attributes["state"])
    return result


def build_summary(value, included):
    attributes = value["attributes"]
    return {"id": value["id"], "build_number": text_value(attributes.get("version"), 64),
            "processing_state": enum_value(attributes.get("processingState")),
            "uploaded_at": text_value(attributes.get("uploadedDate"), 50),
            "expired": bool_value(attributes.get("expired")),
            "uses_non_exempt_encryption": bool_value(attributes.get("usesNonExemptEncryption"))}


def review_summary(value, included):
    attributes = value["attributes"]
    fields = {name + "_present": present(attributes, field) for name, field in (
        ("contact_first_name", "contactFirstName"), ("contact_last_name", "contactLastName"),
        ("contact_phone", "contactPhone"), ("contact_email", "contactEmail"),
        ("demo_account_name", "demoAccountName"), ("demo_account_password", "demoAccountPassword"),
        ("review_notes", "notes"))}
    fields["contact_fields_present"] = all_present([fields[name + "_present"] for name in
                                                   ("contact_first_name", "contact_last_name", "contact_phone", "contact_email")])
    fields["demo_credentials_present"] = all_present([fields["demo_account_name_present"], fields["demo_account_password_present"]])
    fields["demo_account_required"] = bool_value(attributes.get("demoAccountRequired"))
    return fields


AGE_BOOLEANS = {"advertising", "gambling", "healthOrWellnessTopics", "lootBox", "messagingAndChat",
                "parentalControls", "ageAssurance", "socialMedia", "socialMediaAgeRestricted",
                "unrestrictedWebAccess", "userGeneratedContent"}
AGE_ENUMS = {"alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
             "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity",
             "sexualContentOrNudity", "horrorOrFearThemes", "matureOrSuggestiveThemes", "violenceCartoonOrFantasy",
             "violenceRealisticProlongedGraphicOrSadistic", "violenceRealistic", "ageRatingOverrideV2",
             "kidsAgeBand", "ageRatingOverride", "koreaAgeRatingOverride"}


def age_summary(value, included):
    attributes = value["attributes"]
    answers = {key: bool_value(attributes[key]) for key in sorted(AGE_BOOLEANS & attributes.keys())}
    answers.update({key: enum_value(attributes[key]) for key in sorted(AGE_ENUMS & attributes.keys())})
    return {"id": value["id"], "observed_answers": answers,
            "developer_age_rating_info_url_present": present(attributes, "developerAgeRatingInfoUrl"),
            "questionnaire_completeness": "not_inferred_from_optional_or_nullable_fields"}


def included_related(value, field, kind, included):
    identifier = linkage(value, field, kind)
    return identifier, included.get((kind, identifier))


def price_summary(value, included):
    attributes = value["attributes"]
    territory_id, territory = included_related(value, "territory", "territories", included)
    require(territory_id in (None, "USA"), "price_territory_filter_mismatch")
    _, point = included_related(value, "subscriptionPricePoint", "subscriptionPricePoints", included)
    if point is not None:
        point_territory = linkage(point, "territory", "territories")
        require(point_territory in (None, territory_id), "price_point_territory_mismatch")
    amount = text_value(point["attributes"].get("customerPrice"), 32) if point else None
    currency = enum_value(territory["attributes"].get("currency")) if territory else None
    try:
        matches = territory_id == "USA" and currency == "USD" and Decimal(amount) == Decimal("4.99") if all(
            value is not None for value in (territory_id, currency, amount)) else None
    except InvalidOperation:
        matches = None
    return {"id": value["id"], "territory": territory_id, "currency": currency, "customer_price": amount,
            "start_date": text_value(attributes.get("startDate"), 32),
            "preserved": bool_value(attributes.get("preserved")), "plan_type": enum_value(attributes.get("planType")),
            "matches_usa_4_99_amount": matches, "current_new_subscriber_price": "not_inferred_from_schedule_rows"}


def offer_summary(value, included):
    attributes = value["attributes"]
    territory_id, _ = included_related(value, "territory", "territories", included)
    require(territory_id in (None, "USA"), "offer_territory_filter_mismatch")
    periods = attributes.get("numberOfPeriods")
    periods = periods if type(periods) is int and 0 <= periods <= 1000 else None
    mode, duration = enum_value(attributes.get("offerMode")), enum_value(attributes.get("duration"))
    return {"id": value["id"], "territory": territory_id, "offer_mode": mode, "duration": duration,
            "number_of_periods": periods, "start_date": text_value(attributes.get("startDate"), 32),
            "end_date": text_value(attributes.get("endDate"), 32),
            "target_subscription_plan_type": enum_value(attributes.get("targetSubscriptionPlanType")),
            "matches_expected_trial_shape": (territory_id == "USA" and mode == "FREE_TRIAL"
            and duration == "THREE_DAYS" and periods == 1) if all(
                value is not None for value in (territory_id, mode, duration, periods)) else None,
            "active_offer_and_storekit_eligibility": "requires_date_and_device_verification"}


class Inventory:
    def __init__(self, client):
        self.client = client
        self.unavailable = []

    def section(self, parent_kind, parent_id, relationship, render, *, aggregate=False):
        path = f"/v1/{parent_kind}/{parent_id}/{relationship}"
        try:
            fetched = self.client.read(parent_kind, parent_id, relationship)
            if fetched.many:
                return {"status": "observed" if fetched.values else "none_returned",
                        **({"summary": render(fetched.values)} if aggregate else
                           {"items": [render(value, fetched.included) for value in fetched.values]})}
            if not fetched.values:
                return {"status": "no_related_resource_returned"}
            return {"status": "observed", "item": render(fetched.values[0], fetched.included)}
        except InventoryError as error:
            self.unavailable.append({"endpoint": path, "reason": str(error)})
            return {"status": "unavailable", "reason": str(error)}
        except (TypeError, ValueError, AttributeError, KeyError):
            self.unavailable.append({"endpoint": path, "reason": "unusable_resource_shape"})
            return {"status": "unavailable", "reason": "unusable_resource_shape"}

    def screenshots(self, value, included):
        display = enum_value(value["attributes"].get("screenshotDisplayType"))
        family = "iphone" if display and display.startswith("APP_IPHONE") else (
            "ipad" if display and display.startswith("APP_IPAD") else "other_or_unknown")
        return {"id": value["id"], "display_type": display, "device_family": family,
                "assets": self.section("appScreenshotSets", value["id"], "appScreenshots", asset_summary, aggregate=True)}

    def app_locale(self, value, included):
        return {"id": value["id"], "locale": text_value(value["attributes"].get("locale"), 20),
                "screenshot_sets": self.section("appStoreVersionLocalizations", value["id"],
                                                "appScreenshotSets", self.screenshots)}

    def app_version(self, value, included):
        attributes, identifier = value["attributes"], value["id"]
        result = {"id": identifier, "version": text_value(attributes.get("versionString"), 64),
                  "platform": enum_value(attributes.get("platform")),
                  "state": enum_value(attributes.get("appVersionState") or attributes.get("appStoreState"))}
        if result["platform"] == "IOS" and result["version"] in ("1.0", TARGET_VERSION):
            result.update({
                "selected_build": self.section("appStoreVersions", identifier, "build", build_summary),
                "localizations": self.section("appStoreVersions", identifier, "appStoreVersionLocalizations", self.app_locale),
                "review_access": self.section("appStoreVersions", identifier, "appStoreReviewDetail", review_summary),
            })
        return result

    def app_info(self, value, included):
        attributes = value["attributes"]
        return {"id": value["id"], "state": enum_value(attributes.get("state") or attributes.get("appStoreState")),
                "age_rating_declaration": self.section("appInfos", value["id"], "ageRatingDeclaration", age_summary)}

    def metadata_version(self, value, included):
        kind, identifier, attributes = value["type"], value["id"], value["attributes"]
        version = attributes.get("version")
        result = {"id": identifier, "version": version if type(version) is int and 0 <= version < 1_000_000 else text_value(version, 64),
                  "state": enum_value(attributes.get("state")),
                  "localizations": self.section(kind, identifier, "localizations", localization)}
        if kind == "subscriptionVersions":
            result["images"] = self.section(kind, identifier, "images", asset_summary, aggregate=True)
        return result

    def product(self, value, included):
        identifier, attributes = value["id"], value["attributes"]
        versions = self.section("subscriptions", identifier, "versions", self.metadata_version)
        result = {"id": identifier, "name": text_value(attributes.get("name")),
                  "product_id": text_value(attributes.get("productId"), 200),
                  "expected_esha_product": attributes.get("productId") == PRODUCT_ID,
                  "subscription_period": enum_value(attributes.get("subscriptionPeriod")),
                  "state": enum_value(attributes.get("state")),
                  "family_sharable": bool_value(attributes.get("familySharable")),
                  "versions": versions,
                  "usa_prices": self.section("subscriptions", identifier, "prices", price_summary),
                  "usa_introductory_offers": self.section("subscriptions", identifier, "introductoryOffers", offer_summary),
                  "review_screenshot": self.section("subscriptions", identifier, "appStoreReviewScreenshot",
                                                     lambda item, _: asset_summary([item]))}
        if not versions.get("items"):
            result["legacy_localizations"] = self.section("subscriptions", identifier, "subscriptionLocalizations", localization)
        return result

    def group(self, value, included):
        identifier = value["id"]
        versions = self.section("subscriptionGroups", identifier, "versions", self.metadata_version)
        result = {"id": identifier, "reference_name": text_value(value["attributes"].get("referenceName")),
                  "versions": versions,
                  "products": self.section("subscriptionGroups", identifier, "subscriptions", self.product)}
        if not versions.get("items"):
            result["legacy_localizations"] = self.section("subscriptionGroups", identifier, "subscriptionGroupLocalizations", localization)
        return result


def new_report(source_commit):
    return {"schema_version": 1, "status": "checking", "mode": "read_only_inventory",
            "started_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "apple_app_id": APP_ID, "bundle_id": BUNDLE_ID, "sku": SKU,
            "source_commit": source_commit, "cli_version": CLI_VERSION, "identity_verified": False,
            "expected_offer": {"product_id": PRODUCT_ID, "subscription_period": "ONE_MONTH",
                               "usa_monthly_price": "4.99", "trial_duration": "THREE_DAYS"},
            "required_screenshot_families": ["iphone", "ipad"],
            "apple_writes_performed": False, "uploaded": False, "submitted": False,
            "limitations": ["Presence does not verify reviewer credentials or StoreKit behavior.",
                            "Price schedules are observations, not a current-price approval.",
                            "Subscription period is recurrence; price plan type can describe an installment commitment.",
                            "HTTP 404 is unavailable, not proof that a field is unconfigured.",
                            "App privacy questionnaire and account agreements are not inventoried.",
                            "Optional age fields are not used to infer questionnaire completeness."]}


def observation_counts(report):
    def items(section):
        return section.get("items", []) if section.get("status") in ("observed", "none_returned") else None
    versions = items(report["app_versions"])
    builds = items(report["uploaded_builds"])
    groups = items(report["subscription_groups"])
    products = None
    if groups is not None and all(items(group["products"]) is not None for group in groups):
        products = [product for group in groups for product in items(group["products"])]
    return {
        "target_ios_version": TARGET_VERSION,
        "target_ios_version_count": sum(value["platform"] == "IOS" and value["version"] == TARGET_VERSION
                                         for value in versions) if versions is not None else None,
        "uploaded_build_count": len(builds) if builds is not None else None,
        "expected_product_count": sum(value["expected_esha_product"] for value in products) if products is not None else None,
        "unknown_counts_are_null": True,
    }


def inspect(client, source_commit):
    require(isinstance(source_commit, str) and re.fullmatch(r"[a-f0-9]{40}", source_commit), "invalid_source_commit")
    report = new_report(source_commit)
    try:
        client.verify_identity()
    except InventoryError as error:
        report.update(status="identity_not_verified", error=str(error), request_count=client.request_count)
        return report
    report["identity_verified"] = True
    inventory = Inventory(client)
    report["app_versions"] = inventory.section("apps", APP_ID, "appStoreVersions", inventory.app_version)
    report["uploaded_builds"] = inventory.section("apps", APP_ID, "builds", build_summary)
    report["app_information"] = inventory.section("apps", APP_ID, "appInfos", inventory.app_info)
    report["subscription_groups"] = inventory.section("apps", APP_ID, "subscriptionGroups", inventory.group)
    report["observation_counts"] = observation_counts(report)
    report["unavailable_reads"] = inventory.unavailable
    report["status"] = "partial_inventory" if inventory.unavailable else "inventory_complete"
    report["request_count"] = client.request_count
    report["completed_at_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
    return report


def save_report(path, report):
    require(not any(candidate.is_symlink() for candidate in (path, *path.parents)), "report_path_is_symlink")
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix="esha-inventory-", delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(report, stream, indent=2)
        stream.write("\n")
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    root = Path(__file__).resolve().parents[2]
    report_path = root / "apps/esha/artifacts/apple-inventory" / REPORT_FILE
    report = new_report(None)
    try:
        save_report(report_path, report)  # Replace any prior success before setup.
        require(importlib.metadata.version("codemagic-cli-tools") == CLI_VERSION, "pinned_cli_version_required")
        require(os.environ.get("ESHA_APP_STORE_ID") == APP_ID, "esha_app_id_environment_mismatch")
        require((Path(sys.executable).parent / "app-store-connect").is_file(), "pinned_cli_python_required")
        require(all(os.environ.get(name) for name in ("APP_STORE_CONNECT_KEY_IDENTIFIER", "APP_STORE_CONNECT_ISSUER_ID",
                                                      "APP_STORE_CONNECT_PRIVATE_KEY")), "integration_credentials_unavailable")
        commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], stderr=subprocess.PIPE).decode().strip()
        # Reuse the pinned CLI's environment argument resolution and in-memory
        # JWT generation only. Its HTTP client/logger is never used. No cache.
        with tempfile.TemporaryDirectory(prefix="esha-inventory-auth-") as temporary:
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
                report = inspect(AppleReadClient(lambda: dict(headers)), commit)
            finally:
                tempfile.tempdir = previous_temp
        save_report(report_path, report)
    except Exception as error:
        report.update(status="setup_or_local_inspection_failed",
                      error=str(error) if isinstance(error, InventoryError) else "local_setup_or_processing_failed_details_withheld")
        try:
            save_report(report_path, report)
        except Exception:
            pass
        print("Esha release inventory stopped; raw diagnostics and credentials are withheld.", file=sys.stderr)
        return 1
    print(f"Esha release inventory: {report['status']}. Saved {REPORT_FILE}; no Apple changes performed.")
    return 0 if report["identity_verified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
