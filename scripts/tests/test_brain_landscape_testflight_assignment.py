import builtins
from contextlib import redirect_stderr
import copy
import io
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import urlparse

SCRIPT = Path(__file__).resolve().parents[1] / "assign_brain_landscape_testflight_build.py"
spec = importlib.util.spec_from_file_location("brain_landscape_testflight_assignment", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

# Synthetic fixtures, never a claim about the pending real upload or Apple IDs.
TEST_BUILD_NUMBER = "999"
TEST_UPLOAD_ID = "aaaaaaaaaaaaaaaaaaaaaaaa"
TEST_SOURCE_COMMIT = "c" * 40
TEST_SOURCE_TREE = "d" * 40
TEST_IPA_SHA256 = "b" * 64
TEST_APPLE_UPLOAD_ID = "33333333-3333-4333-8333-333333333333"
BUILD_ID = "11111111-1111-4111-8111-111111111118"
OLDER_BUILD_ID = "11111111-1111-4111-8111-111111111117"
TESTER_ID = "22222222-2222-4222-8222-222222222222"


def item(kind, identifier, **attributes):
    return {"type": kind, "id": identifier, "attributes": attributes}


class Response:
    def __init__(self, status_code=200, data=None, links=None):
        self.status_code = status_code
        self.payload = {"data": copy.deepcopy(data), "links": links or {}}

    def json(self):
        return copy.deepcopy(self.payload)


class Session:
    """Fake network boundary; it cannot open a socket or send an invitation."""

    def __init__(self):
        app = item("apps", module.APP_ID, bundleId=module.BUNDLE_ID)
        self.resources = {
            f"/v1/apps/{module.APP_ID}": app,
            module.GROUP_PATH: item("betaGroups", module.GROUP_ID,
                                    name=module.GROUP_NAME, isInternalGroup=True),
            f"{module.GROUP_PATH}/app": copy.deepcopy(app),
            f"/v1/builds/{BUILD_ID}/app": copy.deepcopy(app),
            f"/v1/builds/{BUILD_ID}/preReleaseVersion": item(
                "preReleaseVersions", "version-resource", version=module.VERSION, platform="IOS"),
            f"/v1/builds/{BUILD_ID}/buildBetaDetail": item(
                "buildBetaDetails", "detail-resource", internalBuildState="READY_FOR_BETA_TESTING"),
        }
        self.builds = [item("builds", BUILD_ID, version=module.BUILD_NUMBER,
                            processingState="VALID", expired=False)]
        self.testers = [item("betaTesters", TESTER_ID, email=module.EXISTING_TESTER)]
        self.group_build_ids = {OLDER_BUILD_ID}
        self.calls = []
        self.after_post = None
        self.post_status = 204
        self.post_commits = True
        self.post_state = "IN_BETA_TESTING"
        self.next_url = None

    @property
    def writes(self):
        return [call for call in self.calls if call[0] != "GET"]

    @property
    def state(self):
        return self.resources[f"/v1/builds/{BUILD_ID}/buildBetaDetail"]["attributes"]

    def request(self, method, url, **kwargs):
        path = urlparse(url).path
        self.calls.append((method, path, copy.deepcopy(kwargs)))
        if method == "POST":
            if path != module.ASSIGNMENT_PATH:
                raise AssertionError("Unexpected write endpoint")
            if self.post_status == 204 and self.post_commits:
                self.group_build_ids.add(kwargs["json"]["data"][0]["id"])
                self.state["internalBuildState"] = self.post_state
            if self.after_post:
                self.after_post()
            return Response(self.post_status)
        if method != "GET":
            raise AssertionError("Unexpected mutation")
        if path in self.resources:
            return Response(data=self.resources[path])
        if path == "/v1/builds":
            return Response(data=self.builds, links={"next": self.next_url})
        if path == f"{module.GROUP_PATH}/betaTesters":
            return Response(data=self.testers)
        if path == f"{module.GROUP_PATH}/builds":
            return Response(data=[item("builds", build, version=module.BUILD_NUMBER if build == BUILD_ID else "17")
                                  for build in sorted(self.group_build_ids)])
        raise AssertionError("Unexpected read endpoint")


class AssignmentTests(unittest.TestCase):
    def setUp(self):
        source = copy.deepcopy(module.SOURCE_UPLOAD)
        source["buildNumber"] = TEST_BUILD_NUMBER
        source["codemagicBuildId"] = TEST_UPLOAD_ID
        source["commit"] = TEST_SOURCE_COMMIT
        for field, value in (("BUILD_NUMBER", TEST_BUILD_NUMBER), ("SOURCE_UPLOAD", source),
                             ("SOURCE_COMMIT", TEST_SOURCE_COMMIT), ("SOURCE_TREE", TEST_SOURCE_TREE)):
            patcher = patch.object(module, field, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.record_path = Path(directory.name) / "verified-upload.json"
        self.review_record = {
            "schemaVersion": 1,
            "verifiedAt": "2026-11-12T18:00:00Z",
            "sourceUpload": copy.deepcopy(source),
            "sourceTree": module.SOURCE_TREE,
            "publishingStatus": "uploaded",
            "appleUploadId": TEST_APPLE_UPLOAD_ID,
            "appleBuildId": BUILD_ID,
            "ipa": {
                "sha256": TEST_IPA_SHA256,
                "bytes": 123456,
                "infoPlist": {
                    "CFBundleIdentifier": module.BUNDLE_ID,
                    "CFBundleShortVersionString": module.VERSION,
                    "CFBundleVersion": TEST_BUILD_NUMBER,
                    "CFBundleSupportedPlatforms": ["iPhoneOS"],
                },
            },
        }
        for field, value in (("VERIFIED_RECORD_PATH", self.record_path),
                             ("VERIFIED_RECORD_SHA256", "c" * 64)):
            patcher = patch.object(module, field, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.write_review_fixture(self.review_record)
        self.session = Session()

    def write_review_fixture(self, record):
        """Pin synthetic test observations; production has no automatic repin."""
        raw = (json.dumps(record, sort_keys=True, indent=2) + "\n").encode()
        self.record_path.write_bytes(raw)
        module.VERIFIED_RECORD_SHA256 = hashlib.sha256(raw).hexdigest()

    def run_assignment(self, assign=True):
        api = module.Apple(self.session, lambda: {"Authorization": "Bearer TEST_ONLY"}, assign=assign)
        return module.run(api, assign=assign, sleep=lambda _: None)

    def reject_before_write(self, message):
        with self.assertRaisesRegex(module.AssignmentError, message):
            self.run_assignment()
        self.assertEqual(self.session.writes, [])

    def test_exact_processed_build_gets_one_relationship_write_and_readback(self):
        testers_before = copy.deepcopy(self.session.testers)
        report = self.run_assignment()
        self.assertEqual(report["action"], "assigned")
        self.assertIs(report["deliveryVerified"], True)
        self.assertEqual(report["appleBuildId"], BUILD_ID)
        self.assertEqual(report["internalBuildState"], "IN_BETA_TESTING")
        self.assertEqual(report["expectedSourceUpload"]["codemagicBuildId"], TEST_UPLOAD_ID)
        self.assertEqual(report["expectedSourceUpload"]["commit"], TEST_SOURCE_COMMIT)
        self.assertEqual(report["reviewedArtifactRecord"]["basis"], "reviewed_local_artifact_record")
        self.assertEqual(report["reviewedArtifactRecord"]["recordSha256"], module.VERIFIED_RECORD_SHA256)
        self.assertEqual(report["reviewedArtifactRecord"]["ipaSha256"], TEST_IPA_SHA256)
        self.assertEqual(report["reviewedArtifactRecord"]["appleUploadId"], TEST_APPLE_UPLOAD_ID)
        self.assertEqual(report["reviewedArtifactRecord"]["appleBuildId"], BUILD_ID)
        self.assertEqual(len(self.session.writes), 1)
        method, path, request = self.session.writes[0]
        self.assertEqual((method, path), ("POST", module.ASSIGNMENT_PATH))
        self.assertEqual(request["json"], {"data": [{"type": "builds", "id": BUILD_ID}]})
        self.assertEqual(self.session.testers, testers_before)
        self.assertEqual(self.session.group_build_ids, {OLDER_BUILD_ID, BUILD_ID})
        for _, _, kwargs in self.session.calls:
            self.assertIs(kwargs["allow_redirects"], False)
            self.assertEqual(kwargs["timeout"], 30)
        listing = next(call for call in self.session.calls if call[1] == "/v1/builds")
        self.assertEqual(listing[2]["params"], {
            "limit": 200, "filter[app]": module.APP_ID, "filter[version]": TEST_BUILD_NUMBER})
        self.assertNotIn(module.EXISTING_TESTER, str(report))
        self.assertNotIn("TEST_ONLY", str(report))

    def test_read_only_default_validates_without_assigning(self):
        report = self.run_assignment(assign=False)
        self.assertEqual(report["action"], "validated_only")
        self.assertIs(report["deliveryVerified"], False)
        self.assertEqual(self.session.writes, [])

    def test_pending_or_invalid_source_commit_fails_before_any_apple_request(self):
        for commit in ("__PENDING_VERIFIED_SOURCE_COMMIT__", "", "not-a-commit", None):
            with self.subTest(commit=commit), patch.object(module, "SOURCE_COMMIT", commit):
                self.reject_before_write("source commit is still pending or invalid")
                self.assertEqual(self.session.calls, [])

    def test_pending_or_invalid_source_tree_fails_before_any_apple_request(self):
        for tree in ("__PENDING_VERIFIED_SOURCE_TREE__", "", "not-a-tree", None):
            with self.subTest(tree=tree), patch.object(module, "SOURCE_TREE", tree):
                self.reject_before_write("source tree is still pending or invalid")
                self.assertEqual(self.session.calls, [])

    def test_pending_preflight_stops_before_managed_credential_imports(self):
        original_import = builtins.__import__
        credential_imports = []
        def guarded_import(name, *args, **kwargs):
            if name.startswith("codemagic") or name == "requests":
                credential_imports.append(name)
                raise AssertionError("Pending evidence reached a credential or network import")
            return original_import(name, *args, **kwargs)
        with patch.object(module, "SOURCE_COMMIT", "__PENDING_VERIFIED_SOURCE_COMMIT__"), \
             patch.object(module.sys, "argv", [str(SCRIPT), "--assign"]), \
             patch("builtins.__import__", side_effect=guarded_import), redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(module.main(), 1)
        self.assertEqual(credential_imports, [])
        self.assertIn("source commit is still pending or invalid", errors.getvalue())
        self.assertEqual(self.session.calls, [])

    def test_pending_build_marker_fails_before_any_apple_request(self):
        with patch.object(module, "BUILD_NUMBER", "__PENDING_VERIFIED_BUILD_NUMBER__"):
            self.reject_before_write("build number is still pending")
        self.assertEqual(self.session.calls, [])

    def test_pending_or_invalid_upload_id_fails_before_any_apple_request(self):
        for upload_id in ("__PENDING_VERIFIED_UPLOAD_ID__", "", "not-a-verified-upload", None):
            with self.subTest(upload_id=upload_id), patch.dict(module.SOURCE_UPLOAD, codemagicBuildId=upload_id):
                self.reject_before_write("upload ID is still pending or invalid")
                self.assertEqual(self.session.calls, [])

    def test_previous_builds_17_18_19_20_21_22_and_23_cannot_replace_the_landscape_candidate(self):
        for previous in ("17", "18", "19", "20", "21", "22", "23"):
            with self.subTest(build=previous), patch.object(module, "BUILD_NUMBER", previous), patch.dict(module.SOURCE_UPLOAD, buildNumber=previous):
                self.reject_before_write("below the landscape source floor")
                self.assertEqual(self.session.calls, [])

    def test_source_upload_pins_must_match_before_any_apple_request(self):
        for field, value in (("commit", "e" * 40),
                             ("commit", "f" * 40),
                             ("workflow", "korlix-brain-ios-candidate"),
                             ("bundleId", "com.other.app"), ("version", "1.0.1"),
                             ("buildNumber", "1000")):
            with self.subTest(field=field), patch.dict(module.SOURCE_UPLOAD, {field: value}):
                self.reject_before_write("metadata does not match")
                self.assertEqual(self.session.calls, [])

    def test_pending_review_record_fingerprint_blocks_before_apple_access(self):
        with patch.object(module, "VERIFIED_RECORD_SHA256", "__PENDING_VERIFIED_RECORD_SHA256__"):
            self.reject_before_write("record fingerprint is still pending")
        self.assertEqual(self.session.calls, [])

    def test_environment_success_flags_cannot_replace_the_actual_review_record(self):
        self.record_path.unlink()
        with patch.dict(module.os.environ, {
            "CM_BUILD_ID": TEST_UPLOAD_ID, "CM_COMMIT": module.SOURCE_COMMIT,
            "KORLIX_IOS_BUILD_NUMBER": TEST_BUILD_NUMBER, "SOURCE_VERIFIED": "true",
            "VERIFIED_RECORD_SHA256": "d" * 64, "VERIFIED_RECORD_PATH": "pretend-success.json",
        }):
            self.reject_before_write("record is missing")
        self.assertEqual(self.session.calls, [])

    def test_review_record_tampering_fails_its_fixed_fingerprint(self):
        self.record_path.write_bytes(self.record_path.read_bytes() + b" ")
        self.reject_before_write("fingerprint does not match")
        self.assertEqual(self.session.calls, [])

    def test_record_must_match_source_upload_tree_and_success_observations(self):
        for field, value in (("sourceTree", "f" * 40), ("publishingStatus", "failed"),
                             ("sourceUpload", {**module.SOURCE_UPLOAD, "commit": "e" * 40})):
            with self.subTest(field=field):
                record = copy.deepcopy(self.review_record)
                record[field] = value
                self.write_review_fixture(record)
                self.reject_before_write("does not match the exact successful source upload")
                self.assertEqual(self.session.calls, [])

    def test_record_must_contain_actual_ipa_identity_observations(self):
        for field, value in (("CFBundleIdentifier", "com.other.app"),
                             ("CFBundleShortVersionString", "1.0.1"),
                             ("CFBundleVersion", "17"),
                             ("CFBundleSupportedPlatforms", ["iPhoneSimulator"])):
            with self.subTest(field=field):
                record = copy.deepcopy(self.review_record)
                record["ipa"]["infoPlist"][field] = value
                self.write_review_fixture(record)
                self.reject_before_write("inspected IPA identity does not match")
                self.assertEqual(self.session.calls, [])

    def test_record_success_flag_alone_is_not_artifact_verification(self):
        record = copy.deepcopy(self.review_record)
        record.pop("ipa")
        record["verified"] = True
        self.write_review_fixture(record)
        self.reject_before_write("lacks independent IPA observations")
        self.assertEqual(self.session.calls, [])

    def test_record_requires_ipa_checksum_size_and_observed_apple_upload(self):
        for field, value, message in (("sha256", "", "size or checksum"),
                                      ("bytes", 0, "size or checksum"),
                                      ("appleUploadId", "", "Apple upload identifier")):
            with self.subTest(field=field):
                record = copy.deepcopy(self.review_record)
                (record if field == "appleUploadId" else record["ipa"])[field] = value
                self.write_review_fixture(record)
                self.reject_before_write(message)
                self.assertEqual(self.session.calls, [])

    def test_record_requires_a_separate_observed_apple_build_resource_before_apple_access(self):
        invalid_ids = (None, "", "__PENDING_VERIFIED_APPLE_BUILD_ID__", 123,
                       "invalid resource id", "https://example.com/build", "a" * 129)
        for value in invalid_ids:
            with self.subTest(appleBuildId=value):
                record = copy.deepcopy(self.review_record)
                if value is None:
                    record.pop("appleBuildId")
                else:
                    record["appleBuildId"] = value
                self.write_review_fixture(record)
                self.reject_before_write("observed Apple build resource identifier")
                self.assertEqual(self.session.calls, [])

    def test_unique_valid_build_cannot_replace_the_reviewed_apple_build_resource(self):
        record = copy.deepcopy(self.review_record)
        record["appleBuildId"] = OLDER_BUILD_ID
        self.write_review_fixture(record)
        self.reject_before_write("does not match the reviewed build resource")
        self.assertTrue(self.session.calls)

    def test_environment_cannot_override_fixed_delivery_identity_or_record(self):
        with patch.dict(module.os.environ, {
            "CM_COMMIT": "f" * 40, "CM_BUILD_ID": "d" * 24,
            "KORLIX_IOS_BUILD_NUMBER": "17", "APP_ID": "wrong-app",
            "VERIFIED_RECORD_PATH": "wrong-record.json", "VERIFIED_RECORD_SHA256": "e" * 64,
        }):
            report = self.run_assignment(assign=False)
        self.assertEqual(report["buildNumber"], TEST_BUILD_NUMBER)
        self.assertEqual(report["expectedSourceUpload"]["codemagicBuildId"], TEST_UPLOAD_ID)
        self.assertEqual(report["appId"], "6829319523")
        self.assertEqual(report["reviewedArtifactRecord"]["recordSha256"], module.VERIFIED_RECORD_SHA256)
        self.assertEqual(self.session.writes, [])

    def test_already_linked_is_idempotent_and_still_verifies_delivery(self):
        self.session.group_build_ids.add(BUILD_ID)
        self.session.state["internalBuildState"] = "IN_BETA_TESTING"
        for _ in range(2):
            report = self.run_assignment()
            self.assertEqual(report["action"], "already_linked")
            self.assertIs(report["deliveryVerified"], True)
        self.assertEqual(self.session.writes, [])

    def test_read_only_already_linked_validates_membership_state_and_delivery(self):
        self.session.group_build_ids.add(BUILD_ID)
        self.session.state["internalBuildState"] = "IN_BETA_TESTING"
        report = self.run_assignment(assign=False)
        self.assertEqual(report["action"], "already_linked")
        self.assertIs(report["deliveryVerified"], True)
        self.assertIs(report["readOnly"], True)
        self.assertIs(report["sourceAttestedByApple"], False)
        self.assertEqual(report["existingTesterCount"], 1)
        self.assertEqual(self.session.writes, [])

    def test_read_only_link_without_testing_state_cannot_claim_delivery(self):
        self.session.group_build_ids.add(BUILD_ID)
        with self.assertRaisesRegex(module.AssignmentError, "read-back is pending"):
            self.run_assignment(assign=False)
        self.assertEqual(self.session.writes, [])

    def test_rerun_after_success_does_not_write_again(self):
        self.run_assignment()
        report = self.run_assignment()
        self.assertEqual(report["action"], "already_linked")
        self.assertEqual(len(self.session.writes), 1)

    def test_wrong_app_at_any_relationship_is_rejected(self):
        paths = [f"/v1/apps/{module.APP_ID}", f"{module.GROUP_PATH}/app", f"/v1/builds/{BUILD_ID}/app"]
        for path in paths:
            for field in ("id", "bundleId"):
                with self.subTest(path=path, field=field):
                    self.session = Session()
                    target = self.session.resources[path]
                    if field == "id":
                        target["id"] = "wrong-app"
                    else:
                        target["attributes"]["bundleId"] = "com.other.app"
                    self.reject_before_write("Wrong Apple app")

    def test_wrong_or_external_group_is_rejected(self):
        for field, value in [("id", "wrong-group"), ("name", "Another Group"),
                             ("isInternalGroup", False), ("isInternalGroup", None)]:
            with self.subTest(field=field, value=value):
                self.session = Session()
                group = self.session.resources[module.GROUP_PATH]
                (group if field == "id" else group["attributes"])[field] = value
                self.reject_before_write("Wrong beta group")

    def test_missing_or_ambiguous_build_is_rejected(self):
        for builds in ([], [self.session.builds[0], self.session.builds[0]]):
            with self.subTest(count=len(builds)):
                self.session = Session()
                self.session.builds = builds
                self.reject_before_write("exactly one matching build")

    def test_wrong_build_number_or_unusable_build_is_rejected(self):
        for field, value, message in [("version", "16", "Wrong build number"),
                                      ("processingState", "PROCESSING", "not processed"),
                                      ("processingState", "FAILED", "not processed"),
                                      ("expired", True, "not processed"),
                                      ("expired", None, "not processed")]:
            with self.subTest(field=field, value=value):
                self.session = Session()
                self.session.builds[0]["attributes"][field] = value
                self.reject_before_write(message)

    def test_wrong_version_or_platform_is_rejected(self):
        for field, value in [("version", "1.0.1"), ("platform", "MAC_OS")]:
            with self.subTest(field=field):
                self.session = Session()
                self.session.resources[f"/v1/builds/{BUILD_ID}/preReleaseVersion"]["attributes"][field] = value
                self.reject_before_write("Wrong prerelease version or platform")

    def test_missing_compliance_is_not_silently_changed(self):
        self.session.state["internalBuildState"] = "MISSING_EXPORT_COMPLIANCE"
        self.reject_before_write("not eligible for internal testing")

    def test_existing_tester_membership_is_required_and_never_created(self):
        for testers in ([], [item("betaTesters", TESTER_ID, email="someone-else@example.test")],
                        [self.session.testers[0], self.session.testers[0]]):
            with self.subTest(testers=testers):
                self.session = Session()
                self.session.testers = testers
                self.reject_before_write("already be a unique member")

    def test_post_success_without_readback_is_not_reported_as_delivered(self):
        self.session.post_commits = False
        with self.assertRaisesRegex(module.AssignmentError, "read-back is pending"):
            self.run_assignment()
        self.assertEqual(len(self.session.writes), 1)

    def test_link_without_internal_testing_state_is_not_reported_as_delivered(self):
        self.session.post_state = "READY_FOR_BETA_TESTING"
        with self.assertRaisesRegex(module.AssignmentError, "read-back is pending"):
            self.run_assignment()
        self.assertEqual(len(self.session.writes), 1)

    def test_readback_detects_concurrent_tester_change(self):
        self.session.after_post = lambda: self.session.testers.append(
            item("betaTesters", "another-member", email="someone-else@example.test"))
        with self.assertRaisesRegex(module.AssignmentError, "Tester membership changed"):
            self.run_assignment()
        self.assertEqual(len(self.session.writes), 1)

    def test_readback_detects_removal_of_a_preexisting_group_build(self):
        self.session.after_post = lambda: self.session.group_build_ids.discard(OLDER_BUILD_ID)
        with self.assertRaisesRegex(module.AssignmentError, "Existing group builds changed"):
            self.run_assignment()
        self.assertEqual(len(self.session.writes), 1)

    def test_failed_post_is_not_retried(self):
        self.session.post_status = 403
        with self.assertRaisesRegex(module.AssignmentError, "Apple POST failed: HTTP 403"):
            self.run_assignment()
        self.assertEqual(len(self.session.writes), 1)

    def test_ambiguous_post_transport_failure_is_not_retried_and_rerun_reads_existing_link(self):
        def timeout_after_commit():
            raise TimeoutError("synthetic timeout after Apple may have committed")
        self.session.after_post = timeout_after_commit
        with self.assertRaisesRegex(module.AssignmentError, "POST transport failed"):
            self.run_assignment()
        self.assertEqual(len(self.session.writes), 1)
        self.assertIn(BUILD_ID, self.session.group_build_ids)
        self.session.after_post = None
        self.assertEqual(self.run_assignment()["action"], "already_linked")
        self.assertEqual(len(self.session.writes), 1)

    def test_assignment_capability_cannot_invite_review_release_or_mutate_other_resources(self):
        api = module.Apple(self.session, lambda: {}, assign=True)
        for method, path in (("POST", "/v1/betaTesters"),
                             ("POST", "/v1/betaTesterInvitations"),
                             ("POST", "/v1/betaAppReviewSubmissions"),
                             ("POST", "/v1/appStoreVersionSubmissions"),
                             ("POST", "/v1/appStoreVersionReleaseRequests"),
                             ("DELETE", module.ASSIGNMENT_PATH),
                             ("PATCH", f"/v1/builds/{BUILD_ID}")):
            with self.subTest(method=method, path=path), self.assertRaises(module.AssignmentError):
                api.request(method, path, body={"data": []})
        self.assertEqual(self.session.calls, [])

    def test_assign_permission_alone_cannot_write_an_unvalidated_build(self):
        api = module.Apple(self.session, lambda: {}, assign=True)
        with self.assertRaisesRegex(module.AssignmentError, "exact validated build relationship"):
            api.assign_build(BUILD_ID)
        self.assertEqual(self.session.calls, [])

    def test_assignment_transport_rejects_other_builds_multiple_relationships_or_query_params(self):
        api = module.Apple(self.session, lambda: {}, assign=True)
        api.verified_build_id = BUILD_ID
        for body, params in (({"data": [{"type": "builds", "id": OLDER_BUILD_ID}]}, None),
                             ({"data": [{"type": "builds", "id": BUILD_ID}, {"type": "builds", "id": OLDER_BUILD_ID}]}, None),
                             ({"data": [{"type": "builds", "id": BUILD_ID}]}, {"override": "true"}),
                             ({"data": [{"type": "betaTesters", "id": BUILD_ID}]}, None)):
            with self.subTest(body=body, params=params), self.assertRaisesRegex(module.AssignmentError, "exact validated build relationship"):
                api.request("POST", module.ASSIGNMENT_PATH, body=body, params=params)
        self.assertEqual(self.session.calls, [])

    def test_read_only_transport_blocks_assignment_before_network(self):
        api = module.Apple(self.session, lambda: {})
        with self.assertRaisesRegex(module.AssignmentError, "requires --assign"):
            api.assign_build(BUILD_ID)
        self.assertEqual(self.session.calls, [])

    def test_credentials_do_not_follow_external_or_unrelated_pagination(self):
        for url in ["https://example.test/v1/builds", "http://api.appstoreconnect.apple.com/v1/builds",
                    "https://api.appstoreconnect.apple.com.evil.test/v1/builds",
                    "https://user@api.appstoreconnect.apple.com/v1/builds",
                    "https://api.appstoreconnect.apple.com/v1/apps"]:
            with self.subTest(url=url):
                self.session = Session()
                self.session.next_url = url
                self.reject_before_write("Unexpected Apple")
                self.assertEqual(len([c for c in self.session.calls if c[1] == "/v1/builds"]), 1)
                self.assertTrue(all(c[1] != "/v1/apps" for c in self.session.calls))

    def test_transport_failure_does_not_expose_credentials_or_raw_responses(self):
        class BrokenSession:
            def request(self, *args, **kwargs):
                raise RuntimeError("private-key=NOT_A_REAL_KEY authorization=TEST_ONLY")
        api = module.Apple(BrokenSession(), lambda: {"Authorization": "Bearer TEST_ONLY"})
        with self.assertRaises(module.AssignmentError) as caught:
            module.run(api)
        self.assertEqual(str(caught.exception), "Apple GET transport failed; rerun to inspect current state")


if __name__ == "__main__":
    unittest.main()
