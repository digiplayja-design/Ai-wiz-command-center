from copy import deepcopy
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import sync_copybox_apple_metadata as sync

LOCALIZATION_ID = "localization-en-us"
SECRET = "PRIVATE-REVIEW-OR-CONTACT-VALUE"


class Response:
    def __init__(self, data, status=200):
        self.data, self.status_code = data, status
        self.content = b"fixture"

    def json(self):
        return deepcopy(self.data)


class UnreadPatchResponse:
    """A PATCH response body must never be inspected."""

    def __init__(self, status):
        self.status_code = status
        self.closed = False

    @property
    def content(self):
        raise AssertionError("Private PATCH response body was read")

    def json(self):
        raise AssertionError("Private PATCH response body was parsed")

    def close(self):
        self.closed = True


class AppleFixture:
    def __init__(self, current=False):
        self.calls, self.patch_responses = [], []
        self.app = {"type": "apps", "id": sync.APP_ID, "attributes": {
            "bundleId": sync.BUNDLE_ID, "contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT",
            "primaryLocale": "en-US",
        }}
        self.version = {"type": "appStoreVersions", "id": sync.VERSION_ID,
                        "attributes": {
                            "platform": "IOS", "versionString": "1.0.0",
                            "appVersionState": "PREPARE_FOR_SUBMISSION",
                            "appStoreState": "PREPARE_FOR_SUBMISSION",
                            "releaseType": "AFTER_APPROVAL", "copyright": SECRET,
                        }}
        desired = sync.load_inputs()
        self.localization = {
            "type": "appStoreVersionLocalizations", "id": LOCALIZATION_ID,
            "attributes": {"locale": "en-US",
                           "description": desired["description"] if current else "Old description"},
            "relationships": {"appStoreVersion": {"data": {
                "type": "appStoreVersions", "id": sync.VERSION_ID}}},
        }
        self.review = {
            "type": "appStoreReviewDetails", "id": sync.REVIEW_ID,
            "attributes": {"notes": desired["notes"] if current else SECRET},
            "relationships": {"appStoreVersion": {"data": {
                "type": "appStoreVersions", "id": sync.VERSION_ID}}},
        }
        self.duplicate_locale = False
        self.more_locales = False
        self.version_reads = 0
        self.before_version_read = None
        self.after_patch = None
        self.patch_error = False
        self.patch_status = {"description": 200, "notes": 200}
        self.apply_patch = True

    def request(self, method, url, **kwargs):
        assert url.startswith(sync.ORIGIN + "/v1/")
        assert kwargs["headers"] == {"Authorization": SECRET}
        assert kwargs["timeout"] == 30 and kwargs["allow_redirects"] is False
        path = url.removeprefix(sync.ORIGIN)
        self.calls.append((method, path, deepcopy(kwargs.get("json"))))
        if method == "GET":
            if path == f"/v1/apps/{sync.APP_ID}":
                return Response({"data": self.app})
            if path == f"/v1/apps/{sync.APP_ID}/appStoreVersions":
                self.version_reads += 1
                if self.before_version_read:
                    self.before_version_read(self.version_reads)
                return Response({"data": [self.version]})
            if path == sync.LOCALIZATIONS_GET:
                return Response({"data": [self.localization] * (2 if self.duplicate_locale else 1),
                                 "links": {"next": "https://outside.invalid/" if self.more_locales else None}})
            if path == sync.REVIEW_GET:
                return Response({"data": self.review})
        if method == "PATCH":
            assert kwargs["stream"] is True
            body = kwargs["json"]["data"]
            self.assert_scope(path, body)
            if self.patch_error:
                raise RuntimeError(SECRET)
            attrs = body["attributes"]
            field = next(iter(attrs))
            status = self.patch_status[field]
            if status == 200 and self.apply_patch:
                target = self.localization if field == "description" else self.review
                target["attributes"][field] = attrs[field]
            if self.after_patch:
                self.after_patch(field)
            response = UnreadPatchResponse(status)
            self.patch_responses.append(response)
            return response
        raise AssertionError("Unexpected route")

    @staticmethod
    def assert_scope(path, body):
        attrs = body["attributes"]
        if set(attrs) == {"description"}:
            assert path == f"/v1/appStoreVersionLocalizations/{LOCALIZATION_ID}"
            assert body["type"] == "appStoreVersionLocalizations" and body["id"] == LOCALIZATION_ID
        else:
            assert set(attrs) == {"notes"}
            assert path == f"/v1/appStoreReviewDetails/{sync.REVIEW_ID}"
            assert body["type"] == "appStoreReviewDetails" and body["id"] == sync.REVIEW_ID

    @property
    def writes(self):
        return [call for call in self.calls if call[0] != "GET"]


def execute(fixture, root=sync.ROOT):
    return sync.run(fixture, lambda: {"Authorization": SECRET}, root=root)


class MetadataTests(unittest.TestCase):
    def test_only_description_and_notes_are_patched_and_freshly_verified(self):
        fixture = AppleFixture()
        original = deepcopy(fixture.version["attributes"])
        report = execute(fixture)
        self.assertTrue(report["success"], report)
        self.assertEqual(len(fixture.writes), 2)
        self.assertEqual([next(iter(call[2]["data"]["attributes"])) for call in fixture.writes],
                         ["description", "notes"])
        self.assertEqual(fixture.version["attributes"], original)
        self.assertTrue(report["versionAttributesUnchanged"])
        self.assertTrue(all(row["readbackVerified"] for row in report["patchAttempts"]))
        self.assertTrue(all(response.closed for response in fixture.patch_responses))
        self.assertFalse(report["submissionAttempted"])
        self.assertFalse(report["mutationOutcomeUnknown"])
        self.assertNotIn(SECRET, json.dumps(report))
        self.assertEqual(report["sourceCommit"], sync.SOURCE_COMMIT)
        self.assertEqual(report["sources"]["notes"]["sourceFileSha256"], sync.INPUTS["notes"]["sha256"])

    def test_idempotent_and_single_field_updates_do_not_repeat_other_writes(self):
        fixture = AppleFixture(current=True)
        report = execute(fixture)
        self.assertTrue(report["success"], report)
        self.assertEqual(fixture.writes, [])
        fixture.localization["attributes"]["description"] = "Old description"
        report = execute(fixture)
        self.assertTrue(report["success"], report)
        self.assertEqual(len(fixture.writes), 1)
        self.assertEqual(report["fields"]["notes"], "unchanged_verified")

    def test_wrong_app_version_platform_state_and_release_type_fail_before_write(self):
        mutations = [
            lambda f: f.app.update(id="999"),
            lambda f: f.app["attributes"].update(bundleId="com.other.app"),
            lambda f: f.version.update(id="other-version"),
            lambda f: f.version["attributes"].update(versionString="2.0.0"),
            lambda f: f.version["attributes"].update(platform="ANDROID"),
            lambda f: f.version["attributes"].update(appVersionState="WAITING_FOR_REVIEW"),
            lambda f: f.version["attributes"].update(appStoreState="READY_FOR_DISTRIBUTION"),
            lambda f: f.version["attributes"].update(releaseType="MANUAL"),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                fixture = AppleFixture()
                mutate(fixture)
                self.assertFalse(execute(fixture)["success"])
                self.assertEqual(fixture.writes, [])

    def test_wrong_ambiguous_or_foreign_localization_or_review_detail_cannot_mutate(self):
        mutations = [
            lambda f: setattr(f, "duplicate_locale", True),
            lambda f: setattr(f, "more_locales", True),
            lambda f: f.localization["attributes"].update(locale="en-GB"),
            lambda f: f.localization["relationships"]["appStoreVersion"]["data"].update(id="other"),
            lambda f: f.review.update(id="other-review"),
            lambda f: f.review["relationships"]["appStoreVersion"]["data"].update(id="other"),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                fixture = AppleFixture()
                mutate(fixture)
                self.assertFalse(execute(fixture)["success"])
                self.assertEqual(fixture.writes, [])

    def test_sparse_review_fields_are_required_and_private_values_are_not_reported(self):
        fixture = AppleFixture()
        fixture.review["attributes"]["demoAccountPassword"] = SECRET
        report = execute(fixture)
        self.assertEqual(report["failureCode"], "sparse_fieldset_not_respected")
        self.assertEqual(fixture.writes, [])
        self.assertNotIn(SECRET, json.dumps(report))
        review_reads = [call[1] for call in fixture.calls if "appStoreReviewDetail" in call[1]]
        self.assertEqual(review_reads, [sync.REVIEW_GET])
        self.assertIn("fields[appStoreReviewDetails]=notes,appStoreVersion", sync.REVIEW_GET)
        self.assertNotIn("demoAccount", sync.REVIEW_GET)
        self.assertNotIn("contact", sync.REVIEW_GET)

    def test_changed_input_file_is_rejected_before_api_access(self):
        fixture = AppleFixture()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copytree(sync.ROOT / sync.INPUT_PREFIX, root / sync.INPUT_PREFIX)
            path = root / sync.INPUT_PREFIX / "description.txt"
            path.write_text(path.read_text() + SECRET)
            report = execute(fixture, root)
        self.assertEqual(report["failureCode"], "reviewed_input_hash_mismatch")
        self.assertEqual(fixture.calls, [])
        self.assertNotIn(SECRET, json.dumps(report))

    def test_concurrent_metadata_change_is_not_overwritten(self):
        fixture = AppleFixture()
        fixture.before_version_read = lambda count: (
            fixture.review["attributes"].update(notes="Changed elsewhere") if count == 2 else None)
        report = execute(fixture)
        self.assertEqual(report["failureCode"], "metadata_changed_during_run")
        self.assertEqual(fixture.writes, [])

    def test_patch_failure_is_not_retried_or_allowed_to_leak_a_response_body(self):
        for transport_failure in (False, True):
            with self.subTest(transport_failure=transport_failure):
                fixture = AppleFixture()
                fixture.patch_error = transport_failure
                fixture.patch_status["description"] = 500
                report = execute(fixture)
                self.assertFalse(report["success"])
                self.assertTrue(report["mutationOutcomeUnknown"])
                self.assertEqual(len(fixture.writes), 1)
                self.assertNotIn(SECRET, json.dumps(report))
                self.assertTrue(all(response.closed for response in fixture.patch_responses))

    def test_readback_mismatch_stops_before_the_next_write_and_cannot_claim_success(self):
        fixture = AppleFixture()
        fixture.apply_patch = False
        report = execute(fixture)
        self.assertEqual(report["failureCode"], "metadata_readback_mismatch")
        self.assertTrue(report["mutationOutcomeUnknown"])
        self.assertEqual(len(fixture.writes), 1)
        fixture = AppleFixture()
        fixture.after_patch = lambda field: fixture.version["attributes"].update(copyright="Changed")
        report = execute(fixture)
        self.assertEqual(report["failureCode"], "version_changed_during_run")
        self.assertFalse(report["success"])
        self.assertEqual(len(fixture.writes), 1)

    def test_partial_success_can_resume_without_repatching_verified_description(self):
        fixture = AppleFixture()
        fixture.patch_status["notes"] = 500
        report = execute(fixture)
        self.assertFalse(report["success"])
        self.assertEqual(report["fields"]["description"], "updated_verified")
        self.assertEqual(len(fixture.writes), 2)
        fixture.patch_status["notes"] = 200
        fixture.calls.clear()
        resumed = execute(fixture)
        self.assertTrue(resumed["success"], resumed)
        self.assertEqual(resumed["fields"]["description"], "unchanged_verified")
        self.assertEqual(len(fixture.writes), 1)
        self.assertEqual(set(fixture.writes[0][2]["data"]["attributes"]), {"notes"})


if __name__ == "__main__":
    unittest.main()
