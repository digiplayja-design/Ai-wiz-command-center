"""Offline release inventory fixtures; no Apple calls or real credentials."""

import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock
import urllib.error
import urllib.parse

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import inspect_apple_release as inventory


COMMIT = "b" * 40
PRIVATE = "PRIVATE-REVIEW-CREDENTIAL-OR-CONTACT"


def resource(kind, identifier, **attributes):
    return {"type": kind, "id": identifier, "attributes": attributes}


def relate(value, field, kind, identifier):
    value.setdefault("relationships", {})[field] = {"data": {"type": kind, "id": identifier}}
    return value


def many(*values, included=None, next_page=None, total=None):
    document = {"data": list(values), "links": {"next": next_page}}
    if included is not None:
        document["included"] = included
    if total is not None:
        document["meta"] = {"paging": {"total": total}}
    return document


class Response(io.BytesIO):
    def getcode(self):
        return 200


class Transport:
    def __init__(self, documents):
        self.documents = documents
        self.calls = []

    def __call__(self, request, timeout):
        assert request.get_method() == "GET"
        assert request.data is None
        assert timeout == 20
        parsed = urllib.parse.urlsplit(request.full_url)
        assert parsed.scheme == "https" and parsed.netloc == "api.appstoreconnect.apple.com"
        self.calls.append(request.full_url)
        key = (parsed.path, dict(urllib.parse.parse_qsl(parsed.query)).get("cursor"))
        value = self.documents.get(key, self.documents.get(parsed.path))
        if isinstance(value, int):
            raise urllib.error.HTTPError(request.full_url, value, PRIVATE, {}, io.BytesIO(PRIVATE.encode()))
        if value is None:
            raise AssertionError("Unexpected fixture endpoint: " + parsed.path)
        return Response(json.dumps(value).encode())


def fixture_documents():
    app = f"/v1/apps/{inventory.APP_ID}"
    build = resource("builds", "BUILD", version="1", processingState="VALID", expired=False,
                     usesNonExemptEncryption=False, uploadedDate="2026-11-15T21:00:00Z")
    price = resource("subscriptionPrices", "PRICE", startDate="2099-01-01", preserved=True, planType="MONTHLY")
    relate(price, "territory", "territories", "USA")
    relate(price, "subscriptionPricePoint", "subscriptionPricePoints", "eyJwcmljZSI6MX0=")
    point = relate(resource("subscriptionPricePoints", "eyJwcmljZSI6MX0=", customerPrice="4.99"),
                   "territory", "territories", "USA")
    territory = resource("territories", "USA", currency="USD")
    offer = resource("subscriptionIntroductoryOffers", "OFFER", offerMode="FREE_TRIAL", duration="THREE_DAYS",
                     numberOfPeriods=1, startDate="2026-11-15", endDate=None)
    relate(offer, "territory", "territories", "USA")
    relate(offer, "subscription", "subscriptions", "SUB")
    return {
        app: {"data": resource("apps", inventory.APP_ID, bundleId=inventory.BUNDLE_ID, sku=inventory.SKU)},
        app + "/appStoreVersions": many(resource("appStoreVersions", "VERSION", platform="IOS",
                                                  versionString="1.0.0", appVersionState="PREPARE_FOR_SUBMISSION")),
        "/v1/appStoreVersions/VERSION/build": {"data": build},
        "/v1/appStoreVersions/VERSION/appStoreVersionLocalizations":
            many(resource("appStoreVersionLocalizations", "LOCALE", locale="en-US", description=PRIVATE)),
        "/v1/appStoreVersionLocalizations/LOCALE/appScreenshotSets":
            many(resource("appScreenshotSets", "PHONE", screenshotDisplayType="APP_IPHONE_67"),
                 resource("appScreenshotSets", "PAD", screenshotDisplayType="APP_IPAD_PRO_3GEN_129")),
        "/v1/appScreenshotSets/PHONE/appScreenshots":
            many(resource("appScreenshots", "SHOT1", assetDeliveryState={"state": "COMPLETE"}, fileName=PRIVATE),
                 resource("appScreenshots", "SHOT2", assetDeliveryState={"state": "FAILED", "errors": [PRIVATE]})),
        "/v1/appScreenshotSets/PAD/appScreenshots": many(),
        "/v1/appStoreVersions/VERSION/appStoreReviewDetail": {"data": resource(
            "appStoreReviewDetails", "REVIEW", contactFirstName=PRIVATE, contactLastName=PRIVATE,
            contactPhone=PRIVATE, contactEmail=PRIVATE, demoAccountName=PRIVATE, demoAccountPassword=PRIVATE,
            demoAccountRequired=True, notes=PRIVATE)},
        app + "/builds": many(build),
        app + "/appInfos": many(resource("appInfos", "INFO", appStoreState="PREPARE_FOR_SUBMISSION")),
        "/v1/appInfos/INFO/ageRatingDeclaration": {"data": resource(
            "ageRatingDeclarations", "AGE", healthOrWellnessTopics=True, medicalOrTreatmentInformation="NONE",
            kidsAgeBand=None, developerAgeRatingInfoUrl=PRIVATE, unrelatedPrivateField=PRIVATE)},
        app + "/subscriptionGroups": many(resource("subscriptionGroups", "GROUP", referenceName="Esha")),
        "/v1/subscriptionGroups/GROUP/versions": many(resource(
            "subscriptionGroupVersions", "GROUPVERSION", version=1, state="PREPARE_FOR_SUBMISSION")),
        "/v1/subscriptionGroupVersions/GROUPVERSION/localizations": many(resource(
            "subscriptionGroupLocalizations", "GROUPLOCALE", locale="en-US", name="Esha", customAppName=None)),
        "/v1/subscriptionGroups/GROUP/subscriptions": many(resource(
            "subscriptions", "SUB", name="Esha membership", productId=inventory.PRODUCT_ID,
            subscriptionPeriod="ONE_MONTH", state="MISSING_METADATA", familySharable=False, reviewNote=PRIVATE)),
        "/v1/subscriptions/SUB/versions": many(resource(
            "subscriptionVersions", "SUBVERSION", version=1, state="PREPARE_FOR_SUBMISSION")),
        "/v1/subscriptionVersions/SUBVERSION/localizations": many(resource(
            "subscriptionLocalizations", "SUBLOCALE", locale="en-US", name="Esha", description="Membership")),
        "/v1/subscriptionVersions/SUBVERSION/images": many(resource(
            "subscriptionImages", "SUBIMAGE", assetDeliveryState={"state": "COMPLETE"}, uploadOperations=[PRIVATE])),
        "/v1/subscriptions/SUB/prices": many(price, included=[point, territory]),
        "/v1/subscriptions/SUB/introductoryOffers": many(offer, included=[territory]),
        "/v1/subscriptions/SUB/appStoreReviewScreenshot": {"data": None},
    }


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.no_network = mock.patch("socket.socket", side_effect=AssertionError("No network permitted"))
        self.no_network.start()
        self.addCleanup(self.no_network.stop)
        self.documents = fixture_documents()

    def run_inventory(self):
        self.transport = Transport(self.documents)
        self.client = inventory.AppleReadClient(lambda: {"Authorization": "Bearer FIXTURE"}, open_request=self.transport)
        return inventory.inspect(self.client, COMMIT)

    def test_complete_sanitized_bound_inventory_uses_get_only(self):
        report = self.run_inventory()
        self.assertEqual(report["status"], "inventory_complete")
        self.assertTrue(report["identity_verified"])
        self.assertEqual(report["observation_counts"]["expected_product_count"], 1)
        self.assertEqual(self.transport.calls[0], inventory.API_ORIGIN + f"/v1/apps/{inventory.APP_ID}")
        version = report["app_versions"]["items"][0]
        self.assertEqual(version["selected_build"]["item"]["build_number"], "1")
        sets = version["localizations"]["items"][0]["screenshot_sets"]["items"]
        self.assertEqual([item["device_family"] for item in sets], ["iphone", "ipad"])
        self.assertEqual(sets[0]["assets"]["summary"], {
            "count": 2, "complete_count": 1, "delivery_state_counts": {"COMPLETE": 1, "FAILED": 1}})
        self.assertEqual(sets[1]["assets"]["status"], "none_returned")
        self.assertTrue(version["review_access"]["item"]["demo_credentials_present"])
        group = report["subscription_groups"]["items"][0]
        self.assertEqual(group["versions"]["items"][0]["version"], 1)
        product = group["products"]["items"][0]
        self.assertEqual(product["subscription_period"], "ONE_MONTH")
        self.assertEqual(product["versions"]["items"][0]["version"], 1)
        price = product["usa_prices"]["items"][0]
        self.assertTrue(price["matches_usa_4_99_amount"])
        self.assertEqual(price["current_new_subscriber_price"], "not_inferred_from_schedule_rows")
        self.assertTrue(product["usa_introductory_offers"]["items"][0]["matches_expected_trial_shape"])
        serialized = json.dumps(report)
        self.assertNotIn(PRIVATE, serialized)
        self.assertNotIn("FIXTURE", serialized)
        self.assertNotIn("uploadOperations", serialized)
        self.assertFalse(report["apple_writes_performed"])
        self.assertFalse(report["submitted"])

    def test_wrong_app_id_bundle_or_sku_stops_all_other_reads(self):
        for field in ("id", "bundleId", "sku"):
            with self.subTest(field=field):
                self.documents = fixture_documents()
                app = self.documents[f"/v1/apps/{inventory.APP_ID}"]["data"]
                (app if field == "id" else app["attributes"])[field] = "OTHER"
                report = self.run_inventory()
                self.assertEqual(report["status"], "identity_not_verified")
                self.assertEqual(len(self.transport.calls), 1)
                self.assertFalse(report["identity_verified"])

    def test_optional_404_does_not_mean_empty_or_block_other_sections(self):
        self.documents["/v1/appStoreVersions/VERSION/appStoreReviewDetail"] = 404
        self.documents["/v1/appInfos/INFO/ageRatingDeclaration"] = {"data": None}
        report = self.run_inventory()
        self.assertEqual(report["status"], "partial_inventory")
        access = report["app_versions"]["items"][0]["review_access"]
        self.assertEqual(access, {"status": "unavailable", "reason": "unavailable_http_404"})
        age = report["app_information"]["items"][0]["age_rating_declaration"]
        self.assertEqual(age["status"], "no_related_resource_returned")
        self.assertEqual(report["subscription_groups"]["status"], "observed")
        self.assertNotIn(PRIVATE, json.dumps(report))

    def test_foreign_parent_cannot_bind_subscription_for_further_reads(self):
        product = self.documents["/v1/subscriptionGroups/GROUP/subscriptions"]["data"][0]
        relate(product, "group", "subscriptionGroups", "FOREIGN")
        report = self.run_inventory()
        products = report["subscription_groups"]["items"][0]["products"]
        self.assertEqual(products["reason"], "resource_parent_mismatch")
        self.assertIsNone(report["observation_counts"]["expected_product_count"])
        self.assertFalse(any("/subscriptions/SUB/" in url for url in self.transport.calls))

    def test_successful_empty_groups_establish_zero_products(self):
        self.documents[f"/v1/apps/{inventory.APP_ID}/subscriptionGroups"] = many()
        report = self.run_inventory()
        self.assertEqual(report["subscription_groups"]["status"], "none_returned")
        self.assertEqual(report["observation_counts"]["expected_product_count"], 0)

    def test_unknown_versioned_endpoint_is_reported_and_legacy_metadata_observed(self):
        self.documents["/v1/subscriptions/SUB/versions"] = 403
        self.documents["/v1/subscriptions/SUB/subscriptionLocalizations"] = many(resource(
            "subscriptionLocalizations", "LEGACY", locale="en-US", name="Esha", description="Existing"))
        report = self.run_inventory()
        product = report["subscription_groups"]["items"][0]["products"]["items"][0]
        self.assertEqual(product["versions"]["reason"], "unavailable_http_403")
        self.assertEqual(product["legacy_localizations"]["status"], "observed")
        self.assertEqual(product["usa_prices"]["status"], "observed")

    def test_unauthorized_read_stops_further_transport_without_retry_or_raw_errors(self):
        self.documents[f"/v1/apps/{inventory.APP_ID}/appStoreVersions"] = 401
        report = self.run_inventory()
        self.assertEqual(len(self.transport.calls), 2)
        self.assertEqual(report["status"], "partial_inventory")
        self.assertNotIn(PRIVATE, json.dumps(report))
        self.assertEqual(report["uploaded_builds"]["reason"], "http_401_further_reads_stopped")

    def test_missing_included_price_point_never_uses_unlinked_resource(self):
        prices = self.documents["/v1/subscriptions/SUB/prices"]
        prices["included"][0]["id"] = "UNRELATED"
        prices["included"][0]["attributes"]["customerPrice"] = PRIVATE
        report = self.run_inventory()
        price = report["subscription_groups"]["items"][0]["products"]["items"][0]["usa_prices"]["items"][0]
        self.assertIsNone(price["customer_price"])
        self.assertIsNone(price["matches_usa_4_99_amount"])
        self.assertNotIn(PRIVATE, json.dumps(report))

    def test_unknown_asset_state_and_nullable_age_answers_are_preserved_as_unknown(self):
        self.documents["/v1/appScreenshotSets/PHONE/appScreenshots"]["data"][0]["attributes"]["assetDeliveryState"] = None
        report = self.run_inventory()
        summary = report["app_versions"]["items"][0]["localizations"]["items"][0]["screenshot_sets"]["items"][0]["assets"]["summary"]
        self.assertEqual(summary["delivery_state_counts"]["UNKNOWN"], 1)
        age = report["app_information"]["items"][0]["age_rating_declaration"]["item"]
        self.assertIsNone(age["observed_answers"]["kidsAgeBand"])
        self.assertEqual(age["questionnaire_completeness"], "not_inferred_from_optional_or_nullable_fields")

    def test_absent_review_field_is_unknown_and_credentials_are_only_presence_checks(self):
        details = self.documents["/v1/appStoreVersions/VERSION/appStoreReviewDetail"]["data"]["attributes"]
        del details["contactPhone"]
        details["demoAccountPassword"] = ""
        report = self.run_inventory()
        review = report["app_versions"]["items"][0]["review_access"]["item"]
        self.assertIsNone(review["contact_phone_present"])
        self.assertIsNone(review["contact_fields_present"])
        self.assertFalse(review["demo_credentials_present"])


class ScopeAndPaginationTests(unittest.TestCase):
    def setUp(self):
        self.path = f"/v1/apps/{inventory.APP_ID}/appInfos"
        self.documents = {f"/v1/apps/{inventory.APP_ID}": fixture_documents()[f"/v1/apps/{inventory.APP_ID}"]}
        self.transport = Transport(self.documents)
        self.client = inventory.AppleReadClient(lambda: {"Authorization": "Bearer FIXTURE"}, open_request=self.transport)
        self.client.verify_identity()

    def test_unbound_resource_or_unapproved_endpoint_never_reaches_transport(self):
        for arguments in (("subscriptions", "OTHER", "prices"), ("apps", inventory.APP_ID, "reviewSubmissions"),
                          ("apps", "OTHER", "builds"), ("appInfos", "../OTHER", "ageRatingDeclaration")):
            with self.subTest(arguments=arguments):
                with self.assertRaises(inventory.InventoryError):
                    self.client.read(*arguments)
        self.assertEqual(len(self.transport.calls), 1)
        unverified = inventory.AppleReadClient(lambda: self.fail("Auth must not be read"), open_request=self.transport)
        with self.assertRaises(inventory.InventoryError):
            unverified.read("apps", inventory.APP_ID, "builds")

    def test_complete_two_page_collection_binds_children(self):
        self.documents[self.path] = many(resource("appInfos", "ONE", appStoreState="PREPARE_FOR_SUBMISSION"),
                                         next_page=inventory.API_ORIGIN + self.path + "?limit=200&cursor=two", total=2)
        self.documents[(self.path, "two")] = many(resource("appInfos", "TWO", appStoreState="READY_FOR_DISTRIBUTION"), total=2)
        fetched = self.client.read("apps", inventory.APP_ID, "appInfos")
        self.assertEqual([item["id"] for item in fetched.values], ["ONE", "TWO"])
        self.assertIn(("appInfos", "TWO"), self.client.bound)

    def test_foreign_origin_path_and_changed_query_are_rejected_before_auth_leaves(self):
        bad_links = ["https://example.com" + self.path + "?limit=200&cursor=two",
                     inventory.API_ORIGIN + "/v1/apps/OTHER/appInfos?limit=200&cursor=two",
                     inventory.API_ORIGIN + self.path + "?limit=200&cursor=two&include=secrets",
                     inventory.API_ORIGIN + self.path + "?limit=200&limit=200&cursor=two",
                     inventory.API_ORIGIN + self.path + "?limit=100&cursor=two",
                     inventory.API_ORIGIN + self.path + "?limit=200&cursor=two#fragment"]
        for next_link in bad_links:
            with self.subTest(next_link=next_link):
                self.documents[self.path] = many(resource("appInfos", "ONE", appStoreState="PREPARE_FOR_SUBMISSION"), next_page=next_link)
                calls = len(self.transport.calls)
                with self.assertRaises(inventory.InventoryError):
                    self.client.read("apps", inventory.APP_ID, "appInfos")
                self.assertEqual(len(self.transport.calls), calls + 1)
                self.assertNotIn(("appInfos", "ONE"), self.client.bound)

    def test_duplicate_or_incomplete_collections_are_not_bound(self):
        for variant in ("duplicate", "total", "cycle"):
            with self.subTest(variant=variant):
                next_page = inventory.API_ORIGIN + self.path + "?limit=200&cursor=two"
                self.documents[self.path] = many(resource("appInfos", "ONE", appStoreState="PREPARE_FOR_SUBMISSION"), next_page=next_page, total=2)
                self.documents[(self.path, "two")] = many(
                    resource("appInfos", "ONE" if variant == "duplicate" else "TWO", appStoreState="PREPARE_FOR_SUBMISSION"),
                    next_page=next_page if variant == "cycle" else None, total=3 if variant == "total" else 2)
                with self.assertRaises(inventory.InventoryError):
                    self.client.read("apps", inventory.APP_ID, "appInfos")
                self.assertNotIn(("appInfos", "ONE"), self.client.bound)

    def test_request_budget_and_redirects_cannot_trigger_unbounded_reads(self):
        self.client.request_count = inventory.MAX_REQUESTS
        with self.assertRaisesRegex(inventory.InventoryError, "budget_exhausted"):
            self.client.read("apps", inventory.APP_ID, "appInfos")
        self.assertEqual(len(self.transport.calls), 1)
        self.assertIsNone(inventory.NoRedirects().redirect_request(None, None, 307, None, None, "https://example.com"))

    def test_report_replaces_stale_result_and_rejects_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / inventory.REPORT_FILE
            inventory.save_report(path, {"status": "inventory_complete"})
            inventory.save_report(path, {"status": "checking"})
            self.assertEqual(json.loads(path.read_text()), {"status": "checking"})
            link = Path(directory) / "linked.json"
            link.symlink_to(path)
            with self.assertRaises(inventory.InventoryError):
                inventory.save_report(link, {"secret": PRIVATE})
            self.assertNotIn(PRIVATE, path.read_text())


if __name__ == "__main__":
    unittest.main()
