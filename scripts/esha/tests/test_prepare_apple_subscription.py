"""Stateful offline Apple HTTP fixtures for create-only Esha draft preparation."""

import copy
import datetime as dt
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
import prepare_apple_subscription as draft


COMMIT = "b" * 40
TODAY = dt.date(2026, 11, 15)
PRIVATE = "PRIVATE-API-ERROR-OR-CREDENTIAL"
APP = "/v1/apps/6835184869"


def item(kind, identifier, attributes, relationships=None):
    value = {"type": kind, "id": identifier, "attributes": attributes}
    if relationships:
        value["relationships"] = {name: {"data": {"type": ref[0], "id": ref[1]}}
                                  for name, ref in relationships.items()}
    return value


def many(values=None, included=None):
    result = {"data": values or [], "links": {"next": None}}
    if included:
        result["included"] = included
    return result


class Response(io.BytesIO):
    def __init__(self, document, status=200):
        super().__init__(json.dumps(document).encode())
        self.status = status

    def getcode(self):
        return self.status


class AppleFixture:
    """Tiny API model: POST persists child resources; GET reads the stored graph."""
    def __init__(self):
        self.documents = {
            APP: {"data": item("apps", "6835184869", {"bundleId": "com.korlixdeveloper.esha", "sku": "ESHA_IOS_001"})},
            APP + "/subscriptionGroups": many(),
        }
        self.calls = []
        self.posts = []
        self.identity_reads = 0
        self.before_identity = None
        self.failure_stage = None
        self.failure_kind = None
        self.failure_count = 0
        self.response_id_override = None

    def __call__(self, request, timeout):
        parsed = urllib.parse.urlsplit(request.full_url)
        assert parsed.scheme == "https" and parsed.netloc == "api.appstoreconnect.apple.com"
        assert timeout == 20
        method, path = request.get_method(), parsed.path
        self.calls.append((method, path))
        if method == "GET":
            assert request.data is None
            if path == APP:
                self.identity_reads += 1
                if self.before_identity:
                    self.before_identity(self)
            document = self.documents.get(path)
            if isinstance(document, int):
                raise urllib.error.HTTPError(request.full_url, document, PRIVATE, {}, io.BytesIO(PRIVATE.encode()))
            if document is None:
                raise AssertionError("Unexpected fixture GET endpoint: " + path)
            return Response(copy.deepcopy(document))
        assert method == "POST"
        assert not parsed.query
        body = json.loads(request.data)
        self.posts.append((path, body))
        stage = next(name for name, contract in draft.CREATES.items() if contract[0] == path)
        fail = stage == self.failure_stage and self.failure_count == 0
        if fail:
            self.failure_count += 1
            if self.failure_kind == "reject401":
                raise urllib.error.HTTPError(request.full_url, 401, PRIVATE, {}, io.BytesIO(PRIVATE.encode()))
            if self.failure_kind == "timeout_absent":
                raise TimeoutError(PRIVATE)
        created = self.persist(body["data"])
        if fail and self.failure_kind == "timeout_persisted":
            raise TimeoutError(PRIVATE)
        if fail and self.failure_kind == "server_error_persisted":
            raise urllib.error.HTTPError(request.full_url, 503, PRIVATE, {}, io.BytesIO(PRIVATE.encode()))
        returned = copy.deepcopy(created)
        if self.response_id_override:
            returned["id"] = self.response_id_override
        return Response({"data": returned}, 201)

    def persist(self, data):
        kind = data["type"]
        relations = data["relationships"]
        attributes = copy.deepcopy(data.get("attributes", {}))
        identifier = {
            "subscriptionGroups": "GROUP", "subscriptionGroupVersions": "GVERSION",
            "subscriptionGroupLocalizations": "GLOCALE", "subscriptions": "SUB",
            "subscriptionVersions": "SVERSION", "subscriptionLocalizations": "SLOCALE",
            "subscriptionPlanAvailabilities": "AVAIL",
            "subscriptionPrices": "PRICE", "subscriptionIntroductoryOffers": "TRIAL",
        }[kind]
        parent = lambda key: relations[key]["data"]["id"]
        value = {"type": kind, "id": identifier, "attributes": attributes, "relationships": copy.deepcopy(relations)}
        if kind == "subscriptionGroups":
            path = APP + "/subscriptionGroups"
            self.documents["/v1/subscriptionGroups/GROUP/subscriptions"] = many()
            self.documents["/v1/subscriptionGroups/GROUP/versions"] = many()
        elif kind == "subscriptionGroupVersions":
            path = f"/v1/subscriptionGroups/{parent('subscriptionGroup')}/versions"
            attributes.update(state="PREPARE_FOR_SUBMISSION", version=1)
            self.documents["/v1/subscriptionGroupVersions/GVERSION/localizations"] = many()
        elif kind == "subscriptionGroupLocalizations":
            path = f"/v1/subscriptionGroupVersions/{parent('version')}/localizations"
        elif kind == "subscriptions":
            path = f"/v1/subscriptionGroups/{parent('group')}/subscriptions"
            attributes["state"] = "MISSING_METADATA"
            self.documents["/v1/subscriptions/SUB/versions"] = many()
            territory = item("territories", "USA", {"currency": "USD"})
            point = item("subscriptionPricePoints", "opaque-price-point=", {"customerPrice": "4.99"},
                         {"territory": ("territories", "USA")})
            self.documents["/v1/subscriptions/SUB/pricePoints"] = many([point], [territory])
            self.documents["/v1/subscriptions/SUB/prices"] = many()
            self.documents["/v1/subscriptions/SUB/introductoryOffers"] = many()
            self.documents["/v1/subscriptions/SUB/planAvailabilities"] = many()
        elif kind == "subscriptionVersions":
            path = f"/v1/subscriptions/{parent('subscription')}/versions"
            attributes.update(state="PREPARE_FOR_SUBMISSION", version=1)
            self.documents["/v1/subscriptionVersions/SVERSION/localizations"] = many()
        elif kind == "subscriptionLocalizations":
            path = f"/v1/subscriptionVersions/{parent('version')}/localizations"
        elif kind == "subscriptionPlanAvailabilities":
            path = f"/v1/subscriptions/{parent('subscription')}/planAvailabilities"
            self.documents["/v1/subscriptionPlanAvailabilities/AVAIL/availableTerritories"] = many([
                item("territories", value["id"], {"currency": "USD"})
                for value in relations["availableTerritories"]["data"]])
        elif kind == "subscriptionPrices":
            path = f"/v1/subscriptions/{parent('subscription')}/prices"
            attributes.update(preserved=False)
            value["relationships"]["territory"] = {"data": {"type": "territories", "id": "USA"}}
        elif kind == "subscriptionIntroductoryOffers":
            path = f"/v1/subscriptions/{parent('subscription')}/introductoryOffers"
        self.documents[path]["data"].append(value)
        return value


class DraftTests(unittest.TestCase):
    def setUp(self):
        self.socket_guard = mock.patch("socket.socket", side_effect=AssertionError("No network permitted"))
        self.socket_guard.start()
        self.addCleanup(self.socket_guard.stop)
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.receipt = Path(self.directory.name) / "receipt.json"
        self.api = AppleFixture()

    def run_helper(self, apply=False, spec=None):
        self.client = draft.AppleDraftClient(lambda: {"Authorization": "Bearer " + PRIVATE}, open_request=self.api)
        return draft.prepare(self.client, spec or draft.expected_spec(), apply_draft=apply,
                             report_path=self.receipt, source_commit=COMMIT, today=TODAY)

    def completed_fixture(self):
        self.run_helper(True)
        self.api.posts.clear()
        self.api.calls.clear()
        self.api.identity_reads = 0

    def test_default_absent_plan_is_get_only_with_unresolved_dependent_ids(self):
        result = self.run_helper()
        self.assertEqual(result["status"], "plan_only_no_changes")
        self.assertEqual([x["stage"] for x in result["planned_operations"]], list(draft.STAGES))
        self.assertTrue(result["planned_operations"][0]["resolved"])
        self.assertTrue(all(not x["resolved"] for x in result["planned_operations"][1:]))
        self.assertEqual(self.api.posts, [])
        self.assertTrue(all(method == "GET" for method, _ in self.api.calls))

    def test_apply_creates_nine_scoped_parts_and_reuses_everything_on_repeat(self):
        result = self.run_helper(True)
        self.assertEqual(result["status"], "subscription_draft_prepared")
        self.assertEqual(len(self.api.posts), 9)
        self.assertEqual(len(result["operation_evidence"]), 9)
        self.assertTrue(all(x["outcome"] == "created_and_read_back" for x in result["operation_evidence"]))
        self.assertTrue(result["final_observations"]["availability"]["configured"])
        self.assertTrue(result["availability_changed"])
        availability = next(body for path, body in self.api.posts if path == "/v1/subscriptionPlanAvailabilities")
        self.assertEqual(availability, draft.availability_body("SUB"))
        product = next(body["data"] for path, body in self.api.posts if path == "/v1/subscriptions")
        self.assertEqual(product["attributes"], {"name": "Esha Membership Monthly",
                         "productId": "com.korlixdeveloper.esha.monthly", "subscriptionPeriod": "ONE_MONTH",
                         "familySharable": False, "groupLevel": 1})
        self.assertNotIn("availableInAllTerritories", json.dumps(self.api.posts))
        self.assertNotIn("/v1/subscriptionLocalizations", [path for path, _ in self.api.posts])
        price = next(body["data"] for path, body in self.api.posts if path == "/v1/subscriptionPrices")
        self.assertEqual(price["relationships"]["subscriptionPricePoint"]["data"]["id"], "opaque-price-point=")
        self.assertEqual(price["attributes"]["planType"], "UPFRONT")
        trial = next(body["data"] for path, body in self.api.posts if path == "/v1/subscriptionIntroductoryOffers")
        self.assertEqual((trial["attributes"]["duration"], trial["attributes"]["numberOfPeriods"],
                          trial["attributes"]["offerMode"]), ("THREE_DAYS", 1, "FREE_TRIAL"))
        self.assertEqual(trial["relationships"]["territory"]["data"]["id"], "USA")
        self.assertNotIn("subscriptionPricePoint", trial["relationships"])
        first_count = len(self.api.posts)
        repeated = self.run_helper(True)
        self.assertEqual(len(self.api.posts), first_count)
        self.assertEqual(repeated["planned_operations"], [])
        self.assertNotIn(PRIVATE, self.receipt.read_text())

    def test_full_identity_is_rechecked_immediately_before_first_write(self):
        def change_identity(api):
            if api.identity_reads == 2:
                api.documents[APP]["data"]["attributes"]["sku"] = "WRONG"
        self.api.before_identity = change_identity
        with self.assertRaisesRegex(draft.InventoryError, "esha_identity_mismatch"):
            self.run_helper(True)
        self.assertEqual(self.api.posts, [])

    def test_existing_product_is_searched_across_all_app_groups(self):
        self.api.documents[APP + "/subscriptionGroups"] = many([
            item("subscriptionGroups", "OTHER", {"referenceName": "Different Group"})])
        self.api.documents["/v1/subscriptionGroups/OTHER/subscriptions"] = many([
            item("subscriptions", "SUB", {"productId": draft.PRODUCT_ID})])
        with self.assertRaisesRegex(draft.InventoryError, "esha_product_in_different_group"):
            self.run_helper(True)
        self.assertEqual(self.api.posts, [])

    def test_incomplete_inventory_cannot_establish_product_absence(self):
        self.api.documents[APP + "/subscriptionGroups"] = many([
            item("subscriptionGroups", "OTHER", {"referenceName": "Different Group"})])
        self.api.documents["/v1/subscriptionGroups/OTHER/subscriptions"] = many([
            item("subscriptions", "UNKNOWN", {"name": "Incomplete response"})])
        with self.assertRaisesRegex(draft.InventoryError, "incomplete_subscription_product_identity"):
            self.run_helper(True)
        self.assertEqual(self.api.posts, [])

    def test_duplicate_group_or_product_is_never_repaired_by_creating_another(self):
        for duplicate in ("group", "product"):
            with self.subTest(duplicate=duplicate):
                self.api = AppleFixture()
                self.completed_fixture()
                path = APP + "/subscriptionGroups" if duplicate == "group" else "/v1/subscriptionGroups/GROUP/subscriptions"
                extra = copy.deepcopy(self.api.documents[path]["data"][0])
                extra["id"] += "2"
                self.api.documents[path]["data"].append(extra)
                with self.assertRaises(draft.InventoryError):
                    self.run_helper(True)
                self.assertEqual(self.api.posts, [])

    def test_conflicting_shared_or_annual_product_never_mutates(self):
        for field, value in (("familySharable", True), ("subscriptionPeriod", "ONE_YEAR"), ("name", "Other")):
            with self.subTest(field=field):
                self.api = AppleFixture()
                self.completed_fixture()
                self.api.documents["/v1/subscriptionGroups/GROUP/subscriptions"]["data"][0]["attributes"][field] = value
                with self.assertRaisesRegex(draft.InventoryError, "conflicting_existing_subscription_settings"):
                    self.run_helper(True)
                self.assertEqual(self.api.posts, [])

    def test_non_draft_version_blocks_all_creates(self):
        self.completed_fixture()
        self.api.documents["/v1/subscriptions/SUB/versions"]["data"][0]["attributes"]["state"] = "WAITING_FOR_REVIEW"
        with self.assertRaisesRegex(draft.InventoryError, "non_draft_subscription_metadata_version"):
            self.run_helper(True)
        self.assertEqual(self.api.posts, [])

    def test_existing_wrong_price_or_future_preserved_schedule_blocks_creates(self):
        for mode in ("wrong_point", "preserved", "future"):
            with self.subTest(mode=mode):
                self.api = AppleFixture()
                self.completed_fixture()
                price = self.api.documents["/v1/subscriptions/SUB/prices"]["data"][0]
                if mode == "wrong_point":
                    price["relationships"]["subscriptionPricePoint"]["data"]["id"] = "WRONG"
                elif mode == "preserved":
                    price["attributes"]["preserved"] = True
                else:
                    price["attributes"]["startDate"] = "2099-01-01"
                with self.assertRaises(draft.InventoryError):
                    self.run_helper(True)
                self.assertEqual(self.api.posts, [])

    def test_conflicting_trial_dates_or_multiple_offers_are_not_overwritten(self):
        for mode in ("wrong_duration", "end_date", "duplicate"):
            with self.subTest(mode=mode):
                self.api = AppleFixture()
                self.completed_fixture()
                offers = self.api.documents["/v1/subscriptions/SUB/introductoryOffers"]["data"]
                if mode == "wrong_duration":
                    offers[0]["attributes"]["duration"] = "ONE_WEEK"
                elif mode == "end_date":
                    offers[0]["attributes"]["endDate"] = "2026-12-01"
                else:
                    duplicate = copy.deepcopy(offers[0]); duplicate["id"] = "TRIAL2"; offers.append(duplicate)
                with self.assertRaises(draft.InventoryError):
                    self.run_helper(True)
                self.assertEqual(self.api.posts, [])

    def test_availability_is_read_and_preserved(self):
        self.completed_fixture()
        self.api.documents["/v1/subscriptions/SUB/planAvailabilities"] = many([
            item("subscriptionPlanAvailabilities", "AVAIL", {"planType": "UPFRONT", "availableInNewTerritories": False},
                 {"subscription": ("subscriptions", "SUB")})])
        self.api.documents["/v1/subscriptionPlanAvailabilities/AVAIL/availableTerritories"] = many([
            item("territories", "USA", {"currency": "USD"})])
        result = self.run_helper(True)
        availability = result["final_observations"]["availability"]
        self.assertTrue(availability["configured"])
        self.assertEqual(availability["plans"][0]["territories"], ["USA"])
        self.assertEqual(self.api.posts, [])

    def test_existing_territories_are_preserved_when_configuration_conflicts(self):
        self.completed_fixture()
        before = copy.deepcopy(self.api.documents["/v1/subscriptionPlanAvailabilities/AVAIL/availableTerritories"])
        before["data"].append(item("territories", "CAN", {"currency": "CAD"}))
        self.api.documents["/v1/subscriptionPlanAvailabilities/AVAIL/availableTerritories"] = copy.deepcopy(before)
        with self.assertRaisesRegex(draft.InventoryError, "conflicting_existing_subscription_availability"):
            self.run_helper(True)
        self.assertEqual(self.api.posts, [])
        self.assertEqual(self.api.documents["/v1/subscriptionPlanAvailabilities/AVAIL/availableTerritories"], before)

    def test_timeout_after_persist_is_reconciled_with_get_and_not_reposted(self):
        for failure_kind in ("timeout_persisted", "server_error_persisted"):
            with self.subTest(failure_kind=failure_kind):
                self.api = AppleFixture()
                self.api.failure_stage = "subscription"
                self.api.failure_kind = failure_kind
                result = self.run_helper(True)
                self.assertEqual(result["status"], "subscription_draft_prepared")
                self.assertEqual(sum(path == "/v1/subscriptions" for path, _ in self.api.posts), 1)
                evidence = next(x for x in result["operation_evidence"] if x["stage"] == "subscription")
                self.assertEqual(evidence["outcome"], "matching_resource_reconciled_after_ambiguous_post")
                self.assertEqual(evidence["created_by_this_run"], "unknown")
                self.assertNotIn(PRIVATE, self.receipt.read_text())

    def test_timeout_without_confirmed_resource_stops_and_preserves_partial_receipt(self):
        self.api.failure_stage, self.api.failure_kind = "subscription", "timeout_absent"
        with self.assertRaisesRegex(draft.InventoryError, "post_outcome_unconfirmed_stop_without_retry"):
            self.run_helper(True)
        self.assertEqual(len(self.api.posts), 4)
        report = json.loads(self.receipt.read_text())
        self.assertEqual(report["status"], "stopped_review_partial_progress")
        self.assertEqual(report["operation_evidence"][-1]["outcome"], "ambiguous_post_get_reconciliation_only")
        self.assertEqual(len([x for x in report["operation_evidence"] if x["outcome"] == "created_and_read_back"]), 3)

    def test_auth_error_does_not_retry_or_treat_denied_read_as_absence(self):
        self.api.failure_stage, self.api.failure_kind = "group", "reject401"
        with self.assertRaisesRegex(draft.InventoryError, "create_rejected_http_401_no_retry"):
            self.run_helper(True)
        self.assertEqual(len(self.api.posts), 1)
        self.assertEqual(self.api.calls[-1], ("POST", "/v1/subscriptionGroups"))
        self.assertNotIn(PRIVATE, self.receipt.read_text())
        self.api = AppleFixture()
        self.api.documents[APP + "/subscriptionGroups"] = 403
        with self.assertRaises(draft.InventoryError):
            self.run_helper(True)
        self.assertEqual(self.api.posts, [])

    def test_readback_must_find_exact_returned_id(self):
        self.api.response_id_override = "UNRELATED"
        with self.assertRaisesRegex(draft.InventoryError, "created_resource_id_not_found_in_scoped_readback"):
            self.run_helper(True)
        self.assertEqual(len(self.api.posts), 1)

    def test_changed_spec_cannot_expand_scope_or_claim_unlimited_ai(self):
        for field, value in (("customer_price", "9.99"), ("territory", "CAN"), ("family_sharable", True),
                             ("subscription_description", "Unlimited AI"), ("review_submission", True),
                             ("group_level", True)):
            with self.subTest(field=field):
                spec = draft.expected_spec(); spec[field] = value
                with self.assertRaisesRegex(draft.InventoryError, "subscription_spec_outside_exact_authorized_draft"):
                    self.run_helper(True, spec)
                self.assertEqual(self.api.calls, [])

    def test_direct_create_requires_complete_fresh_inventory_and_cannot_repeat(self):
        client = draft.AppleDraftClient(lambda: {}, open_request=self.api)
        with self.assertRaisesRegex(draft.InventoryError, "fresh_inventory_required"):
            client.create("group")
        draft.inspect_target(client, today=TODAY)
        client.create("group")
        with self.assertRaisesRegex(draft.InventoryError, "fresh_inventory_required"):
            client.create("group_version")
        self.assertEqual(len(self.api.posts), 1)

    def test_checked_in_spec_matches_guarded_contract(self):
        path = Path(__file__).resolve().parents[3] / "apps/esha/release/apple-subscription-draft.json"
        draft.validate_spec(json.loads(path.read_text()))


if __name__ == "__main__":
    unittest.main()
