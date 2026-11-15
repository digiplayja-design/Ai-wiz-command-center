"""Stateful, network-disabled checks for the approved review-contact PATCH."""

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
import prepare_apple_review_contact as contact


COMMIT = "b" * 40
PRIVATE = "PRIVATE-DEMO-OR-API-CREDENTIAL"
APP = "/v1/apps/" + contact.APP_ID
VERSION_ID = "ab8553e4-56d5-40a9-aa7a-8cfb447fca72"
DETAIL_ID = "EXISTING_REVIEW_DETAIL"
VERSION_PATH = "/v1/appStoreVersions/" + VERSION_ID


def item(kind, identifier, attributes, relationship=None):
    value = {"type": kind, "id": identifier, "attributes": attributes}
    if relationship:
        name, parent_kind, parent_id = relationship
        value["relationships"] = {name: {"data": {"type": parent_kind, "id": parent_id}}}
    return value


class Response(io.BytesIO):
    def __init__(self, document, status=200):
        super().__init__(json.dumps(document).encode())
        self.status = status

    def getcode(self):
        return self.status


class AppleFixture:
    def __init__(self):
        self.app = item("apps", contact.APP_ID, {"bundleId": contact.BUNDLE_ID, "sku": contact.SKU})
        self.version = item("appStoreVersions", VERSION_ID, {"platform": "IOS", "versionString": "1.0.0",
                            "appVersionState": "PREPARE_FOR_SUBMISSION"}, ("app", "apps", contact.APP_ID))
        self.detail = item("appStoreReviewDetails", DETAIL_ID,
            {**dict.fromkeys(contact.CONTACT), "demoAccountName": PRIVATE + "-NAME",
             "demoAccountPassword": PRIVATE + "-PASSWORD", "demoAccountRequired": True, "notes": PRIVATE + "-NOTES"},
            ("appStoreVersion", "appStoreVersions", VERSION_ID))
        self.calls, self.patches = [], []
        self.identity_reads = 0
        self.before_identity = None
        self.before_patch = None
        self.patch_result = "success"

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
                document = {"data": self.app}
            elif path == APP + "/appStoreVersions":
                document = {"data": [self.version], "links": {"next": None}}
            elif path == VERSION_PATH + "/appStoreReviewDetail":
                document = {"data": self.detail}
            else:
                raise AssertionError("Unexpected fixture GET: " + path)
            return Response(copy.deepcopy(document))
        assert method == "PATCH" and path == "/v1/appStoreReviewDetails/" + DETAIL_ID
        assert not parsed.query
        body = json.loads(request.data)
        self.patches.append((path, body))
        if self.before_patch:
            self.before_patch(self)
        if self.patch_result.startswith("reject"):
            error = {"errors": [{"code": PRIVATE, "title": PRIVATE, "detail": PRIVATE}]}
            raise urllib.error.HTTPError(request.full_url, int(self.patch_result[6:]), PRIVATE, {},
                                         io.BytesIO(json.dumps(error).encode()))
        if self.patch_result == "timeout_absent":
            raise TimeoutError(PRIVATE)
        if self.patch_result != "success_absent":
            self.detail["attributes"].update(body["data"]["attributes"])
        if self.patch_result == "timeout_persisted":
            raise TimeoutError(PRIVATE)
        if self.patch_result == "server_error_persisted":
            raise urllib.error.HTTPError(request.full_url, 503, PRIVATE, {}, io.BytesIO(PRIVATE.encode()))
        # Real responses include the existing credential attributes too.
        return Response({"data": copy.deepcopy(self.detail)}, 204 if self.patch_result == "unexpected_204_persisted" else 200)


class ReviewContactTests(unittest.TestCase):
    def setUp(self):
        guard = mock.patch("socket.socket", side_effect=AssertionError("No network permitted"))
        guard.start()
        self.addCleanup(guard.stop)
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.receipt = Path(directory.name) / "receipt.json"
        self.api = AppleFixture()

    def run_helper(self, apply=False):
        self.client = contact.ReviewContactClient(lambda: {"Authorization": "Bearer " + PRIVATE}, open_request=self.api)
        return contact.prepare_contact(self.client, apply_draft=apply, report_path=self.receipt, source_commit=COMMIT)

    def assert_stopped_without_patch(self, reason):
        with self.assertRaisesRegex(contact.InventoryError, reason):
            self.run_helper(True)
        self.assertEqual(self.api.patches, [])
        self.assertNotIn(PRIVATE, self.receipt.read_text())

    def test_default_plan_is_get_only_and_contains_only_approved_contact(self):
        result = self.run_helper()
        self.assertEqual(result["status"], "plan_only_no_changes")
        self.assertEqual(result["planned_operation"]["body"], {"data": {
            "type": "appStoreReviewDetails", "id": DETAIL_ID, "attributes": {
            "contactFirstName": "Ricardo", "contactLastName": "Bailey",
            "contactEmail": "support@korlixdeveloper.com", "contactPhone": "+16148942317"}}})
        self.assertEqual(self.api.patches, [])
        self.assertTrue(all(method == "GET" for method, _ in self.api.calls))
        self.assertNotIn(PRIVATE, self.receipt.read_text())
        self.assertNotIn(PRIVATE, repr(self.client.review_snapshot))

    def test_apply_persists_intent_then_one_patch_and_private_preservation_readback(self):
        before = copy.deepcopy(self.api.detail["attributes"])
        def check_intent(api):
            receipt = json.loads(self.receipt.read_text())
            self.assertEqual(receipt["intent"]["outcome"], "attempting_once")
            self.assertEqual(receipt["contact_changed_by_this_run"], "unknown")
            self.assertEqual(api.calls[-2], ("GET", VERSION_PATH + "/appStoreReviewDetail"))
        self.api.before_patch = check_intent
        result = self.run_helper(True)
        self.assertEqual(result["status"], "review_contact_updated_and_read_back")
        self.assertEqual(len(self.api.patches), 1)
        self.assertEqual(self.api.identity_reads, 3)
        self.assertEqual(set(self.api.patches[0][1]["data"]["attributes"]), set(contact.CONTACT))
        for key in contact.PROTECTED_FIELDS:
            self.assertEqual(self.api.detail["attributes"][key], before[key])
        self.assertTrue(result["non_contact_attributes_unchanged"])
        self.assertTrue(result["demo_credentials_unchanged"])
        self.assertFalse(result["review_submitted"])
        self.assertFalse(result["published"])
        self.assertNotIn(PRIVATE, self.receipt.read_text())

    def test_existing_approved_fields_are_omitted_from_partial_patch(self):
        self.api.detail["attributes"].update(contactFirstName="Ricardo", contactLastName="Bailey", contactPhone="   ")
        self.run_helper(True)
        self.assertEqual(self.api.patches[0][1]["data"]["attributes"], {
            "contactEmail": "support@korlixdeveloper.com", "contactPhone": "+16148942317"})

    def test_already_configured_contact_is_a_noop(self):
        self.api.detail["attributes"].update(contact.CONTACT)
        result = self.run_helper(True)
        self.assertEqual(result["status"], "already_configured_verified")
        self.assertEqual(self.api.patches, [])
        self.assertFalse(result["contact_changed_by_this_run"])

    def test_each_nonempty_conflicting_contact_field_stops_without_logging_it(self):
        for key in contact.CONTACT:
            with self.subTest(key=key):
                self.api = AppleFixture()
                self.api.detail["attributes"][key] = PRIVATE
                self.assert_stopped_without_patch("nonempty_review_contact_conflict")

    def test_wrong_app_identity_stops_before_descendant_reads(self):
        for key in ("id", "bundleId", "sku"):
            with self.subTest(key=key):
                self.api = AppleFixture()
                (self.api.app if key == "id" else self.api.app["attributes"])[key] = "OTHER"
                self.assert_stopped_without_patch("unexpected_resource_id|esha_identity_mismatch")
                self.assertEqual(self.api.calls, [("GET", APP)])

    def test_missing_review_detail_is_never_created(self):
        self.api.detail = None
        self.assert_stopped_without_patch("existing_review_detail_required_no_creation")

    def test_foreign_review_detail_and_unsafe_id_are_rejected(self):
        for change in ("parent", "id"):
            with self.subTest(change=change):
                self.api = AppleFixture()
                if change == "parent":
                    self.api.detail["relationships"]["appStoreVersion"]["data"]["id"] = "OTHER_VERSION"
                else:
                    self.api.detail["id"] = "unsafe/path"
                self.assert_stopped_without_patch("resource_parent_mismatch|unsafe_review_detail_id")

    def test_wrong_version_platform_or_noneditable_state_stops(self):
        for key, value in (("versionString", "1.0.1"), ("platform", "MAC_OS"),
                           ("appVersionState", "WAITING_FOR_REVIEW"), ("appStoreState", "READY_FOR_SALE")):
            with self.subTest(key=key):
                self.api = AppleFixture()
                self.api.version["attributes"][key] = value
                self.assert_stopped_without_patch("one_exact_ios|app_version_not_editable")

    def test_incomplete_or_invalid_attribute_readback_cannot_authorize_a_write(self):
        for key in (*contact.CONTACT, *contact.PROTECTED_FIELDS):
            with self.subTest(key=key):
                self.api = AppleFixture()
                del self.api.detail["attributes"][key]
                self.assert_stopped_without_patch("incomplete_review_detail_attributes")
        self.api = AppleFixture()
        self.api.detail["attributes"]["contactPhone"] = 6148942317
        self.assert_stopped_without_patch("invalid_contact_attribute_type")
        self.api = AppleFixture()
        self.api.detail["attributes"]["demoAccountRequired"] = 1
        self.assert_stopped_without_patch("invalid_protected_review_attribute_type")

    def test_identity_state_contact_and_protected_data_are_rechecked_before_patch(self):
        for change in ("identity", "state", "contact", "credentials", "record_id"):
            with self.subTest(change=change):
                self.api = AppleFixture()
                def drift(api):
                    if api.identity_reads != 2:
                        return
                    if change == "identity":
                        api.app["attributes"]["sku"] = "OTHER"
                    elif change == "state":
                        api.version["attributes"]["appVersionState"] = "WAITING_FOR_REVIEW"
                    elif change == "contact":
                        api.detail["attributes"]["contactEmail"] = PRIVATE
                    elif change == "credentials":
                        api.detail["attributes"]["demoAccountPassword"] = PRIVATE + "-CHANGED"
                    else:
                        api.detail["id"] = "ANOTHER_DETAIL"
                self.api.before_identity = drift
                self.assert_stopped_without_patch("esha_identity|app_version_not_editable|nonempty_review_contact|non_contact_attributes|resource_identity")

    def test_previously_approved_contact_cannot_disappear_before_write(self):
        self.api.detail["attributes"]["contactFirstName"] = "Ricardo"
        def drift(api):
            if api.identity_reads == 2:
                api.detail["attributes"]["contactFirstName"] = None
        self.api.before_identity = drift
        self.assert_stopped_without_patch("approved_contact_disappeared")

    def test_readback_of_changed_protected_attributes_fails_without_retry_or_secret_output(self):
        for change in ("password", "missing_notes", "new_attribute"):
            with self.subTest(change=change):
                self.api = AppleFixture()
                def drift(api):
                    if api.identity_reads != 3:
                        return
                    if change == "password":
                        api.detail["attributes"]["demoAccountPassword"] = PRIVATE + "-CHANGED"
                    elif change == "missing_notes":
                        del api.detail["attributes"]["notes"]
                    else:
                        api.detail["attributes"]["newProtectedField"] = PRIVATE
                self.api.before_identity = drift
                with self.assertRaisesRegex(contact.InventoryError, "non_contact_attributes|incomplete_review_detail"):
                    self.run_helper(True)
                result = json.loads(self.receipt.read_text())
                self.assertEqual(result["contact_changed_by_this_run"], "unknown")
                self.assertIsNone(result["demo_credentials_unchanged"])
                self.assertEqual(len(self.api.patches), 1)
                self.assertNotIn(PRIVATE, self.receipt.read_text())

    def test_ambiguous_persisted_patch_is_reconciled_only_with_gets(self):
        for failure in ("timeout_persisted", "server_error_persisted", "unexpected_204_persisted"):
            with self.subTest(failure=failure):
                self.api = AppleFixture()
                self.api.patch_result = failure
                result = self.run_helper(True)
                self.assertEqual(result["status"], "contact_reconciled_after_ambiguous_patch")
                self.assertEqual(result["contact_changed_by_this_run"], "unknown")
                self.assertTrue(result["demo_credentials_unchanged"])
                self.assertEqual(result["patch_retries"], 0)
                self.assertEqual(len(self.api.patches), 1)
                self.assertNotIn(PRIVATE, self.receipt.read_text())

    def test_unconfirmed_patch_stops_without_false_success_or_retry(self):
        for failure in ("timeout_absent", "success_absent"):
            with self.subTest(failure=failure):
                self.api = AppleFixture()
                self.api.patch_result = failure
                with self.assertRaisesRegex(contact.InventoryError, "contact_update_not_confirmed"):
                    self.run_helper(True)
                result = json.loads(self.receipt.read_text())
                self.assertEqual(result["status"], "stopped_review_partial_progress")
                self.assertEqual(result["contact_changed_by_this_run"], "unknown")
                self.assertEqual(len(self.api.patches), 1)

    def test_http_rejection_stops_and_never_exposes_error_or_credential_values(self):
        for code in (401, 403, 409, 422, 429):
            with self.subTest(code=code):
                self.api = AppleFixture()
                self.api.patch_result = "reject" + str(code)
                with self.assertRaisesRegex(contact.InventoryError, "review_contact_rejected_http_" + str(code)):
                    self.run_helper(True)
                result = json.loads(self.receipt.read_text())
                self.assertEqual(result["apple_rejection"], {"http_status": code, "details_withheld": True})
                self.assertEqual(self.api.calls[-1][0], "PATCH")
                self.assertEqual(len(self.api.patches), 1)
                self.assertNotIn(PRIVATE, self.receipt.read_text())

    def test_patch_requires_fresh_bound_snapshot_and_cannot_repeat(self):
        client = contact.ReviewContactClient(lambda: {}, open_request=self.api)
        with self.assertRaisesRegex(contact.InventoryError, "fresh_review_contact_inventory_required"):
            client.patch_once()
        contact.inspect_contact(client)
        client.patch_once()
        self.api.detail["attributes"].update(dict.fromkeys(contact.CONTACT))
        contact.inspect_contact(client)
        with self.assertRaisesRegex(contact.InventoryError, "contact_patch_retry_forbidden"):
            client.patch_once()
        self.assertEqual(len(self.api.patches), 1)

    def test_patch_rejects_arbitrary_attributes_or_unbound_record(self):
        for change in ("attributes", "binding"):
            with self.subTest(change=change):
                self.api = AppleFixture()
                client = contact.ReviewContactClient(lambda: {}, open_request=self.api)
                snapshot = contact.inspect_contact(client)
                if change == "attributes":
                    snapshot.changes["demoAccountRequired"] = False
                else:
                    client.parents.clear()
                with self.assertRaisesRegex(contact.InventoryError, "unapproved_contact_patch|not_bound_to_esha"):
                    client.patch_once()
                self.assertEqual(self.api.patches, [])


if __name__ == "__main__":
    unittest.main()
