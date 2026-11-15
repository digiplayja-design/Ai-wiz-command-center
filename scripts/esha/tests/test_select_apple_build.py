"""Offline stateful HTTP checks for the single Esha draft build association."""

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
import select_apple_build as select


COMMIT = "b" * 40
PRIVATE = "PRIVATE-API-ERROR-OR-CREDENTIAL"
APP = "/v1/apps/" + select.APP_ID
VERSION_ID = "ab8553e4-56d5-40a9-aa7a-8cfb447fca72"
VERSION_PATH = "/v1/appStoreVersions/" + VERSION_ID
PRERELEASE_PATH = "/v1/builds/" + select.BUILD_ID + "/preReleaseVersion"


def item(kind, identifier, attributes, parent=None):
    value = {"type": kind, "id": identifier, "attributes": attributes}
    if parent:
        value["relationships"] = {"app": {"data": {"type": "apps", "id": parent}}}
    return value


def many(values):
    return {"data": values, "links": {"next": None}}


class Response(io.BytesIO):
    def __init__(self, document=None, status=200):
        super().__init__(json.dumps(document).encode())
        self.status = status

    def getcode(self):
        return self.status


class AppleFixture:
    def __init__(self):
        self.app = item("apps", select.APP_ID, {"bundleId": select.BUNDLE_ID, "sku": select.SKU})
        self.version = item("appStoreVersions", VERSION_ID, {"platform": "IOS", "versionString": "1.0.0",
                            "appVersionState": "PREPARE_FOR_SUBMISSION"}, select.APP_ID)
        self.build = item("builds", select.BUILD_ID, {"version": "2", "processingState": "VALID",
                          "expired": False, "usesNonExemptEncryption": None,
                          "buildAudienceType": "APP_STORE_ELIGIBLE"}, select.APP_ID)
        self.prerelease = item("preReleaseVersions", "PRE_RELEASE", {"version": "1.0.0", "platform": "IOS"}, select.APP_ID)
        self.selected = None
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
                document = many([self.version])
            elif path == APP + "/builds":
                document = many([self.build])
            elif path == PRERELEASE_PATH:
                document = {"data": self.prerelease}
            elif path == VERSION_PATH + "/build":
                document = {"data": self.selected}
            else:
                raise AssertionError("Unexpected fixture GET: " + path)
            return Response(copy.deepcopy(document))
        assert method == "PATCH" and path == VERSION_PATH + "/relationships/build"
        assert not parsed.query
        body = json.loads(request.data)
        self.patches.append((path, body))
        if self.before_patch:
            self.before_patch(self)
        if self.patch_result.startswith("reject"):
            error = {"errors": [{"code": "ENTITY_ERROR.COMPLIANCE_REQUIRED", "detail": PRIVATE, "title": PRIVATE}]}
            raise urllib.error.HTTPError(request.full_url, int(self.patch_result[6:]), PRIVATE, {},
                                         io.BytesIO(json.dumps(error).encode()))
        if self.patch_result == "timeout_absent":
            raise TimeoutError(PRIVATE)
        if self.patch_result != "success_absent":
            self.selected = copy.deepcopy(self.build)
        if self.patch_result == "timeout_persisted":
            raise TimeoutError(PRIVATE)
        if self.patch_result == "server_error_persisted":
            raise urllib.error.HTTPError(request.full_url, 503, PRIVATE, {}, io.BytesIO(PRIVATE.encode()))
        return Response(status=200 if self.patch_result == "unexpected_200_persisted" else 204)


class SelectionTests(unittest.TestCase):
    def setUp(self):
        network_guard = mock.patch("socket.socket", side_effect=AssertionError("No network permitted"))
        network_guard.start()
        self.addCleanup(network_guard.stop)
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.receipt = Path(directory.name) / "receipt.json"
        self.api = AppleFixture()

    def run_helper(self, apply=False):
        self.client = select.BuildSelectionClient(lambda: {"Authorization": "Bearer " + PRIVATE}, open_request=self.api)
        return select.select_build(self.client, apply_draft=apply, report_path=self.receipt, source_commit=COMMIT)

    def assert_stopped_without_patch(self, reason):
        with self.assertRaisesRegex(select.InventoryError, reason):
            self.run_helper(True)
        self.assertEqual(self.api.patches, [])
        self.assertNotIn(PRIVATE, self.receipt.read_text())

    def test_default_plan_is_get_only_and_records_exact_linkage(self):
        result = self.run_helper()
        self.assertEqual(result["status"], "plan_only_no_changes")
        self.assertEqual(result["planned_operation"]["body"], {"data": {"type": "builds", "id": select.BUILD_ID}})
        self.assertEqual(result["initial_observation"]["pre_release_version"], "1.0.0")
        self.assertEqual(result["initial_observation"]["processing_state"], "VALID")
        self.assertIsNone(result["initial_observation"]["uses_non_exempt_encryption"])
        self.assertTrue(all(method == "GET" for method, _ in self.api.calls))
        self.assertEqual(self.api.patches, [])

    def test_apply_persists_intent_then_one_patch_204_and_readback(self):
        def check_intent(api):
            receipt = json.loads(self.receipt.read_text())
            self.assertEqual(receipt["intent"]["outcome"], "attempting_once")
            self.assertEqual(receipt["intent"]["operation"]["body"], select.selection_body())
            self.assertEqual(receipt["association_changed_by_this_run"], "unknown")
            self.assertEqual(api.calls[-2], ("GET", VERSION_PATH + "/build"))
        self.api.before_patch = check_intent
        result = self.run_helper(True)
        self.assertEqual(result["status"], "build_selected_and_read_back")
        self.assertEqual(self.api.identity_reads, 3)
        self.assertEqual(self.api.patches, [(VERSION_PATH + "/relationships/build", select.selection_body())])
        self.assertEqual(result["final_observation"]["selected_build_id"], select.BUILD_ID)
        self.assertIsNone(result["final_observation"]["uses_non_exempt_encryption"])
        self.assertIsNone(self.api.build["attributes"]["usesNonExemptEncryption"])
        self.assertTrue(result["association_changed_by_this_run"])
        for flag in ("encryption_answers_changed", "contact_details_changed", "review_submitted", "published"):
            self.assertFalse(result[flag])
        self.assertNotIn(PRIVATE, self.receipt.read_text())

    def test_already_selected_target_never_writes(self):
        self.api.selected = copy.deepcopy(self.api.build)
        result = self.run_helper(True)
        self.assertEqual(result["status"], "already_selected_verified")
        self.assertEqual(self.api.patches, [])
        self.assertFalse(result["association_changed_by_this_run"])

    def test_wrong_app_bundle_or_sku_stops_before_other_reads(self):
        for field in ("id", "bundleId", "sku"):
            with self.subTest(field=field):
                self.api = AppleFixture()
                (self.api.app if field == "id" else self.api.app["attributes"])[field] = "WRONG"
                self.assert_stopped_without_patch("unexpected_resource_id|esha_identity_mismatch")
                self.assertEqual(self.api.calls, [("GET", APP)])

    def test_version_platform_number_or_noneditable_state_stops(self):
        for field, value in (("versionString", "1.0.1"), ("platform", "MAC_OS"),
                             ("appVersionState", "WAITING_FOR_REVIEW"), ("appStoreState", "READY_FOR_SALE")):
            with self.subTest(field=field):
                self.api = AppleFixture()
                self.api.version["attributes"][field] = value
                self.assert_stopped_without_patch("one_exact_ios|app_version_not_editable")

    def test_invalid_build_attributes_or_different_build_id_stop(self):
        for field, value in (("id", "OTHER"), ("version", "1"), ("processingState", "PROCESSING"),
                             ("expired", True), ("expired", None), ("buildAudienceType", "INTERNAL_ONLY")):
            with self.subTest(field=field):
                self.api = AppleFixture()
                (self.api.build if field == "id" else self.api.build["attributes"])[field] = value
                self.assert_stopped_without_patch("exact_build|target_build")

    def test_prerelease_version_platform_or_app_mismatch_stops(self):
        for field, value in (("version", "2.0.0"), ("platform", "MAC_OS"), ("app", "OTHER")):
            with self.subTest(field=field):
                self.api = AppleFixture()
                if field == "app":
                    self.api.prerelease["relationships"]["app"]["data"]["id"] = value
                else:
                    self.api.prerelease["attributes"][field] = value
                self.assert_stopped_without_patch("prerelease_version_app_mismatch|target_build_marketing")

    def test_another_selected_build_is_never_replaced(self):
        self.api.selected = copy.deepcopy(self.api.build)
        self.api.selected["id"] = "OTHER_BUILD"
        self.assert_stopped_without_patch("another_build_already_selected")

    def test_identity_and_selected_relation_are_rechecked_before_patch(self):
        for change in ("identity", "state", "another_selected", "target_now_selected", "target_disappeared"):
            with self.subTest(change=change):
                self.api = AppleFixture()
                if change == "target_disappeared":
                    self.api.selected = copy.deepcopy(self.api.build)
                def change_on_refresh(api):
                    if api.identity_reads != 2:
                        return
                    if change == "identity":
                        api.app["attributes"]["sku"] = "WRONG"
                    elif change == "state":
                        api.version["attributes"]["appVersionState"] = "WAITING_FOR_REVIEW"
                    elif change == "target_disappeared":
                        api.selected = None
                    else:
                        api.selected = copy.deepcopy(api.build)
                        if change == "another_selected":
                            api.selected["id"] = "OTHER_BUILD"
                self.api.before_identity = change_on_refresh
                if change == "target_now_selected":
                    self.assertEqual(self.run_helper(True)["status"], "already_selected_verified")
                    self.assertEqual(self.api.patches, [])
                else:
                    self.assert_stopped_without_patch("esha_identity|app_version_not_editable|another_build|previously_selected")

    def test_changed_prerelease_identity_stops_before_patch(self):
        def change_on_refresh(api):
            if api.identity_reads == 2:
                api.prerelease["id"] = "DIFFERENT_PRERELEASE"
        self.api.before_identity = change_on_refresh
        self.assert_stopped_without_patch("selection_resource_identity_changed")

    def test_ambiguous_persisted_patch_is_only_reconciled_with_gets(self):
        for failure in ("timeout_persisted", "server_error_persisted", "unexpected_200_persisted"):
            with self.subTest(failure=failure):
                self.api = AppleFixture()
                self.api.patch_result = failure
                result = self.run_helper(True)
                self.assertEqual(result["status"], "selection_reconciled_after_ambiguous_patch")
                self.assertEqual(result["association_changed_by_this_run"], "unknown")
                self.assertEqual(len(self.api.patches), 1)
                self.assertEqual(result["patch_retries"], 0)
                self.assertNotIn(PRIVATE, self.receipt.read_text())

    def test_unconfirmed_patch_stops_without_retry_or_false_unchanged_claim(self):
        for failure in ("timeout_absent", "success_absent"):
            with self.subTest(failure=failure):
                self.api = AppleFixture()
                self.api.patch_result = failure
                with self.assertRaisesRegex(select.InventoryError, "selection_not_confirmed"):
                    self.run_helper(True)
                receipt = json.loads(self.receipt.read_text())
                self.assertEqual(receipt["status"], "stopped_review_partial_progress")
                self.assertEqual(receipt["association_changed_by_this_run"], "unknown")
                self.assertEqual(len(self.api.patches), 1)

    def test_compliance_or_auth_rejection_does_not_mutate_other_fields_or_retry(self):
        for code in (401, 403, 409, 422, 429):
            with self.subTest(code=code):
                self.api = AppleFixture()
                self.api.patch_result = "reject" + str(code)
                with self.assertRaisesRegex(select.InventoryError, "build_association_rejected_http_" + str(code)):
                    self.run_helper(True)
                receipt = json.loads(self.receipt.read_text())
                self.assertEqual(receipt["apple_rejection"]["http_status"], code)
                self.assertEqual(receipt["apple_rejection"]["error_codes"], ["ENTITY_ERROR.COMPLIANCE_REQUIRED"])
                self.assertEqual(len(self.api.patches), 1)
                self.assertEqual(self.api.calls[-1][0], "PATCH")
                self.assertIsNone(self.api.build["attributes"]["usesNonExemptEncryption"])
                self.assertNotIn(PRIVATE, self.receipt.read_text())

    def test_fixed_prerelease_endpoint_requires_prior_app_binding(self):
        client = select.BuildSelectionClient(lambda: {}, open_request=self.api)
        with self.assertRaisesRegex(select.InventoryError, "target_build_not_bound"):
            client.target_prerelease_version()
        self.assertEqual(self.api.calls, [])

    def test_patch_requires_fresh_validated_snapshot_and_cannot_repeat(self):
        client = select.BuildSelectionClient(lambda: {}, open_request=self.api)
        with self.assertRaisesRegex(select.InventoryError, "fresh_selection_inventory_required"):
            client.select_once()
        select.inspect_selection(client)
        client.select_once()
        self.api.selected = None
        select.inspect_selection(client)
        with self.assertRaisesRegex(select.InventoryError, "selection_patch_retry_forbidden"):
            client.select_once()
        self.assertEqual(len(self.api.patches), 1)


if __name__ == "__main__":
    unittest.main()
