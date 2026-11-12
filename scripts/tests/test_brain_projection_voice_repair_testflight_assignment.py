import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import urlparse

SCRIPT = Path(__file__).resolve().parents[1] / "assign_brain_projection_voice_repair_testflight_build.py"
spec = importlib.util.spec_from_file_location("brain_projection_voice_repair_testflight_assignment", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

# Synthetic fixtures, never a claim about the pending real upload or Apple IDs.
TEST_SOURCE_COMMIT = "a" * 40
TEST_SOURCE_TREE = "b" * 40
TEST_BUILD_NUMBER = "999"
TEST_UPLOAD_ID = "aaaaaaaaaaaaaaaaaaaaaaaa"
TEST_IPA_SHA256 = "b" * 64
TEST_APPLE_UPLOAD_ID = "33333333-3333-4333-8333-333333333333"
BUILD_ID = "11111111-1111-4111-8111-111111111120"
OLDER_BUILD_ID = "11111111-1111-4111-8111-111111111119"
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
            return Response(data=[item("builds", build, version=module.BUILD_NUMBER if build == BUILD_ID else "19")
                                  for build in sorted(self.group_build_ids)])
        raise AssertionError("Unexpected read endpoint")


class AssignmentTests(unittest.TestCase):
    def setUp(self):
        source = copy.deepcopy(module.SOURCE_UPLOAD)
        source["commit"] = TEST_SOURCE_COMMIT
        source["buildNumber"] = TEST_BUILD_NUMBER
        source["codemagicBuildId"] = TEST_UPLOAD_ID
        for field, value in (("SOURCE_COMMIT", TEST_SOURCE_COMMIT), ("SOURCE_TREE", TEST_SOURCE_TREE),
                             ("BUILD_NUMBER", TEST_BUILD_NUMBER), ("SOURCE_UPLOAD", source)):
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
            "publishingStatusBasis": "apple_readback_after_ambiguous_upload",
            "appleUploadId": TEST_APPLE_UPLOAD_ID,
            "uploadObservation": {
                "codemagicBuildId": TEST_UPLOAD_ID,
                "codemagicTerminalStatus": "failed",
                "codemagicFailureStage": "publishing",
                "altoolResult": "UPLOAD SUCCEEDED with no errors",
                "appleUploadId": TEST_APPLE_UPLOAD_ID,
                "transferredBytes": 123456,
            },
            "appleReconciliation": {
                "job": copy.deepcopy(module.RECONCILIATION_JOB),
                "jobStatus": "finished",
            },
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
        self.reconciliation_report = {
            "schemaVersion": 1,
            "checkedAt": "2026-11-12T17:59:00Z",
            "purpose": "reconcile_ambiguous_upload",
            "readOnly": True,
            "uploadContext": {
                "codemagicBuildId": TEST_UPLOAD_ID,
                "codemagicIndex": 25,
                "workflow": module.SOURCE_UPLOAD["workflow"],
                "sourceCommit": TEST_SOURCE_COMMIT,
                "sourceTree": TEST_SOURCE_TREE,
                "observedAppleUploadId": TEST_APPLE_UPLOAD_ID,
                "observedAltoolResult": "UPLOAD SUCCEEDED with no errors",
                "observedCodemagicResult": "failed_publishing_after_Apple_500_errors",
                "inspectedIpaSha256": TEST_IPA_SHA256,
                "inspectedIpaBytes": 123456,
            },
            "appId": module.APP_ID,
            "bundleId": module.BUNDLE_ID,
            "version": module.VERSION,
            "buildNumber": TEST_BUILD_NUMBER,
            "sourceAttestedByApple": False,
            "deliveryVerified": False,
            "returnedBuildCount": 1,
            "exactBuildPresent": True,
            "presenceStatus": "found",
            "processingVerified": True,
            "appleBuildId": BUILD_ID,
            "platform": "IOS",
            "processingState": "VALID",
            "expired": False,
            "observedUploadIdMatchesBuildId": False,
            "internalBuildState": "READY_FOR_BETA_TESTING",
            "existingGroup": {
                "groupId": module.GROUP_ID,
                "groupName": module.GROUP_NAME,
                "isInternalGroup": True,
                "buildLinked": False,
            },
        }
        for field, value in (("VERIFIED_RECORD_PATH", self.record_path),
                             ("VERIFIED_RECORD_SHA256", "c" * 64)):
            patcher = patch.object(module, field, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.review_record = self.write_reconciliation_fixture(self.reconciliation_report)
        self.session = Session()

    def write_review_fixture(self, record):
        """Pin synthetic test observations; production has no automatic repin."""
        raw = (json.dumps(record, sort_keys=True, indent=2) + "\n").encode()
        self.record_path.write_bytes(raw)
        module.VERIFIED_RECORD_SHA256 = hashlib.sha256(raw).hexdigest()

    def write_reconciliation_fixture(self, report):
        """Embed synthetic report bytes; production never generates observations."""
        record = copy.deepcopy(self.review_record)
        raw = json.dumps(report, sort_keys=True, indent=2) + "\n"
        record["appleReconciliation"]["reportJson"] = raw
        record["appleReconciliation"]["reportSha256"] = hashlib.sha256(raw.encode()).hexdigest()
        self.write_review_fixture(record)
        return record

    def run_assignment(self, assign=True):
        api = module.Apple(self.session, lambda: {"Authorization": "Bearer TEST_ONLY"}, assign=assign)
        return module.run(api, assign=assign, sleep=lambda _: None)

    def reject_before_write(self, message):
        with self.assertRaisesRegex(module.AssignmentError, message):
            self.run_assignment()
        self.assertEqual(self.session.writes, [])

    def reject_before_apple(self, message):
        self.reject_before_write(message)
        self.assertEqual(self.session.calls, [])

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
        self.assertEqual(report["reviewedArtifactRecord"]["publishingStatusBasis"],
                         "apple_readback_after_ambiguous_upload")
        self.assertEqual(report["reviewedArtifactRecord"]["originalCodemagicTerminalStatus"], "failed")
        self.assertEqual(report["reviewedArtifactRecord"]["reconciledAppleBuildId"], BUILD_ID)
        self.assertEqual(report["reviewedArtifactRecord"]["reconciliationJob"], module.RECONCILIATION_JOB)
        self.assertEqual(report["reviewedArtifactRecord"]["reconciliationReportSha256"],
                         self.review_record["appleReconciliation"]["reportSha256"])
        self.assertNotEqual(report["appleBuildId"], report["reviewedArtifactRecord"]["appleUploadId"])
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

    def test_pending_build_marker_fails_before_any_apple_request(self):
        with patch.object(module, "BUILD_NUMBER", "__PENDING_VERIFIED_BUILD_NUMBER__"):
            self.reject_before_write("build number is still pending")
        self.assertEqual(self.session.calls, [])

    def test_pending_or_invalid_upload_id_fails_before_any_apple_request(self):
        for upload_id in ("__PENDING_VERIFIED_UPLOAD_ID__", "", "not-a-verified-upload", None):
            with self.subTest(upload_id=upload_id), patch.dict(module.SOURCE_UPLOAD, codemagicBuildId=upload_id):
                self.reject_before_write("upload ID is still pending or invalid")
                self.assertEqual(self.session.calls, [])

    def test_previous_builds_17_18_and_19_cannot_replace_the_projection_voice_repair_candidate(self):
        for previous in ("17", "18", "19"):
            with self.subTest(build=previous), patch.object(module, "BUILD_NUMBER", previous), patch.dict(module.SOURCE_UPLOAD, buildNumber=previous):
                self.reject_before_write("below the projection-voice-repair source floor")
                self.assertEqual(self.session.calls, [])

    def test_source_upload_pins_must_match_before_any_apple_request(self):
        for field, value in (("commit", "f390b8441ad8931ee565b197b78eb116f7da58ef"),
                             ("commit", "5933fe7274bfc33f8846288457c01cb27723993e"),
                             ("commit", "8b25e22eb5fc5cbfbc871a24f14c372d2d37efc0"),
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
                             ("sourceUpload", {**module.SOURCE_UPLOAD, "commit": "2f813ef77f6cd3b86fc109f8085ca8c3cd48f62f"})):
            with self.subTest(field=field):
                record = copy.deepcopy(self.review_record)
                record[field] = value
                self.write_review_fixture(record)
                self.reject_before_write("does not match the exact Apple-accepted source upload")
                self.assertEqual(self.session.calls, [])

    def test_record_must_contain_actual_ipa_identity_observations(self):
        for field, value in (("CFBundleIdentifier", "com.other.app"),
                             ("CFBundleShortVersionString", "1.0.1"),
                             ("CFBundleVersion", "17"),
                             ("CFBundleVersion", "19"),
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

    def test_apple_readback_basis_and_original_failed_publishing_must_be_preserved(self):
        for basis in (None, "codemagic_success", "__PENDING_VERIFIED_PUBLISHING_BASIS__"):
            with self.subTest(basis=basis):
                record = copy.deepcopy(self.review_record)
                record["publishingStatusBasis"] = basis
                self.write_review_fixture(record)
                self.reject_before_apple("requires its explicit Apple read-back basis")
        for field, value in (("codemagicBuildId", "f" * 24),
                             ("codemagicTerminalStatus", "finished"),
                             ("codemagicFailureStage", "build"),
                             ("altoolResult", "pending"),
                             ("appleUploadId", BUILD_ID),
                             ("transferredBytes", 654321)):
            with self.subTest(field=field):
                record = copy.deepcopy(self.review_record)
                record["uploadObservation"][field] = value
                self.write_review_fixture(record)
                self.reject_before_apple("failed Codemagic job and successful altool observation")

    def test_reconciliation_requires_the_exact_completed_job_and_source(self):
        cases = [None, {}, {**self.review_record["appleReconciliation"], "job": None}]
        for field, value in (("codemagicBuildId", "f" * 24),
                             ("workflow", "korlix-brain-ios-testflight"),
                             ("commit", "f" * 40)):
            evidence = copy.deepcopy(self.review_record["appleReconciliation"])
            evidence["job"][field] = value
            cases.append(evidence)
        for status in ("queued", "building", "failed", "__PENDING_RECONCILIATION_STATUS__"):
            cases.append({**self.review_record["appleReconciliation"], "jobStatus": status})
        for evidence in cases:
            with self.subTest(evidence=evidence):
                record = copy.deepcopy(self.review_record)
                record["appleReconciliation"] = evidence
                self.write_review_fixture(record)
                self.reject_before_apple("exact completed reconciliation job and source")

    def test_reconciliation_requires_its_exact_report_bytes_and_fingerprint(self):
        for field, value in (("reportJson", None), ("reportJson", ""),
                             ("reportJson", "x" * 32769),
                             ("reportJson", self.review_record["appleReconciliation"]["reportJson"] + " "),
                             ("reportSha256", None), ("reportSha256", "f" * 64)):
            with self.subTest(field=field, size=len(value) if isinstance(value, str) else None):
                record = copy.deepcopy(self.review_record)
                record["appleReconciliation"][field] = value
                self.write_review_fixture(record)
                self.reject_before_apple("report fingerprint is pending or mismatched")

    def test_reconciliation_report_must_be_valid_json(self):
        record = copy.deepcopy(self.review_record)
        record["appleReconciliation"]["reportJson"] = "{"
        record["appleReconciliation"]["reportSha256"] = hashlib.sha256(b"{").hexdigest()
        self.write_review_fixture(record)
        self.reject_before_apple("reconciliation report is invalid JSON")

    def test_reconciliation_must_not_claim_source_attestation_or_delivery(self):
        for field, value in (("schemaVersion", 2), ("purpose", "assign_build"),
                             ("readOnly", False), ("readOnly", None),
                             ("sourceAttestedByApple", True), ("sourceAttestedByApple", None),
                             ("deliveryVerified", True), ("deliveryVerified", None)):
            with self.subTest(field=field, value=value):
                report = copy.deepcopy(self.reconciliation_report)
                report[field] = value
                self.write_reconciliation_fixture(report)
                self.reject_before_apple("unsupported or misleading observation contract")
        self.write_reconciliation_fixture([])
        self.reject_before_apple("unsupported or misleading observation contract")

    def test_reconciliation_report_must_identify_the_exact_app_version_and_build(self):
        for field, value in (("appId", "1234567890"), ("bundleId", "com.other.app"),
                             ("version", "1.0.1"), ("buildNumber", "19"),
                             ("platform", "MAC_OS")):
            with self.subTest(field=field):
                report = copy.deepcopy(self.reconciliation_report)
                report[field] = value
                self.write_reconciliation_fixture(report)
                self.reject_before_apple("does not identify this exact app, version and build")

    def test_reconciliation_report_requires_one_valid_unexpired_build(self):
        for field, value in (("returnedBuildCount", 0), ("returnedBuildCount", 2),
                             ("returnedBuildCount", True), ("exactBuildPresent", False),
                             ("presenceStatus", "not_found"), ("presenceStatus", "ambiguous"),
                             ("processingVerified", False), ("processingState", "PROCESSING"),
                             ("processingState", "FAILED"), ("processingState", "INVALID"),
                             ("expired", True), ("expired", None)):
            with self.subTest(field=field, value=value):
                report = copy.deepcopy(self.reconciliation_report)
                report[field] = value
                self.write_reconciliation_fixture(report)
                self.reject_before_apple("one exact VALID and unexpired build")

    def test_reconciliation_upload_source_and_ipa_context_must_match(self):
        for field, value in (("codemagicBuildId", "f" * 24), ("codemagicIndex", 24),
                             ("workflow", "korlix-brain-ios-candidate"),
                             ("sourceCommit", "f" * 40), ("sourceTree", "f" * 40),
                             ("observedAppleUploadId", BUILD_ID),
                             ("observedAltoolResult", "pending"),
                             ("observedCodemagicResult", "success"),
                             ("inspectedIpaSha256", "e" * 64), ("inspectedIpaBytes", 654321)):
            with self.subTest(field=field):
                report = copy.deepcopy(self.reconciliation_report)
                report["uploadContext"][field] = value
                self.write_reconciliation_fixture(report)
                self.reject_before_apple("source, upload and IPA observations do not match")

    def test_reconciliation_requires_an_observed_build_id_and_truthful_upload_comparison(self):
        for identifier in (None, "", "__PENDING_APPLE_BUILD_ID__"):
            with self.subTest(identifier=identifier):
                report = copy.deepcopy(self.reconciliation_report)
                report["appleBuildId"] = identifier
                self.write_reconciliation_fixture(report)
                self.reject_before_apple("invalid resource identifier")
        for comparison in (None, True, 0):
            with self.subTest(comparison=comparison):
                report = copy.deepcopy(self.reconciliation_report)
                report["observedUploadIdMatchesBuildId"] = comparison
                self.write_reconciliation_fixture(report)
                self.reject_before_apple("misstates its observed upload/build identifier relationship")

    def test_observed_upload_and_build_identifiers_may_match_without_being_assumed_equal(self):
        report = copy.deepcopy(self.reconciliation_report)
        report["appleBuildId"] = TEST_APPLE_UPLOAD_ID
        report["observedUploadIdMatchesBuildId"] = True
        self.write_reconciliation_fixture(report)
        reviewed = module.require_verified_source_upload()
        self.assertEqual(reviewed["reconciledAppleBuildId"], TEST_APPLE_UPLOAD_ID)
        self.assertEqual(self.session.calls, [])

    def test_reconciliation_observation_must_be_dated_before_its_review(self):
        for checked_at in (None, "invalid", "2026-11-12T17:59:00",
                           "2026-11-12T18:00:01Z", []):
            with self.subTest(checked_at=checked_at):
                report = copy.deepcopy(self.reconciliation_report)
                report["checkedAt"] = checked_at
                self.write_reconciliation_fixture(report)
                self.reject_before_apple("dated observation before independent review")

    def test_reconciliation_optional_group_observation_must_match_if_present(self):
        for field, value in (("groupId", "another-group"), ("groupName", "Another Group"),
                             ("isInternalGroup", False), ("buildLinked", "false")):
            with self.subTest(field=field):
                report = copy.deepcopy(self.reconciliation_report)
                report["existingGroup"][field] = value
                self.write_reconciliation_fixture(report)
                self.reject_before_apple("different existing internal group")
        report = copy.deepcopy(self.reconciliation_report)
        report.pop("existingGroup")
        self.write_reconciliation_fixture(report)
        self.assertEqual(module.require_verified_source_upload()["reconciledAppleBuildId"], BUILD_ID)
        self.assertEqual(self.session.calls, [])

    def test_current_apple_build_must_match_the_reconciled_build_before_assignment(self):
        report = copy.deepcopy(self.reconciliation_report)
        report["appleBuildId"] = "44444444-4444-4444-8444-444444444444"
        self.write_reconciliation_fixture(report)
        self.reject_before_write("current Apple build does not match the independently reconciled build")
        self.assertTrue(self.session.calls)
        self.assertEqual(self.session.group_build_ids, {OLDER_BUILD_ID})

    def test_already_linked_is_idempotent_and_still_verifies_delivery(self):
        self.session.group_build_ids.add(BUILD_ID)
        self.session.state["internalBuildState"] = "IN_BETA_TESTING"
        for _ in range(2):
            report = self.run_assignment()
            self.assertEqual(report["action"], "already_linked")
            self.assertIs(report["deliveryVerified"], True)
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
                                      ("version", "19", "Wrong build number"),
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
