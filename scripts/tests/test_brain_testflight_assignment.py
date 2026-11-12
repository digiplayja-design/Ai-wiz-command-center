import copy
import importlib.util
from pathlib import Path
import unittest
from urllib.parse import urlparse

SCRIPT = Path(__file__).resolve().parents[1] / "assign_brain_testflight_build.py"
spec = importlib.util.spec_from_file_location("brain_testflight_assignment", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

BUILD_ID = "11111111-1111-4111-8111-111111111116"
OLDER_BUILD_ID = "11111111-1111-4111-8111-111111111115"
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
            return Response(data=[item("builds", build, version="16" if build == BUILD_ID else "15")
                                  for build in sorted(self.group_build_ids)])
        raise AssertionError("Unexpected read endpoint")


class AssignmentTests(unittest.TestCase):
    def setUp(self):
        self.session = Session()

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
        self.assertEqual(report["expectedSourceUpload"]["codemagicBuildId"], "6af5a2dd9679c85ac0af0ae2")
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
            "limit": 200, "filter[app]": module.APP_ID, "filter[version]": "16"})
        self.assertNotIn(module.EXISTING_TESTER, str(report))
        self.assertNotIn("TEST_ONLY", str(report))

    def test_read_only_default_validates_without_assigning(self):
        report = self.run_assignment(assign=False)
        self.assertEqual(report["action"], "validated_only")
        self.assertIs(report["deliveryVerified"], False)
        self.assertEqual(self.session.writes, [])

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
        for field, value, message in [("version", "15", "Wrong build number"),
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

    def test_failed_post_is_not_retried(self):
        self.session.post_status = 403
        with self.assertRaisesRegex(module.AssignmentError, "Apple POST failed: HTTP 403"):
            self.run_assignment()
        self.assertEqual(len(self.session.writes), 1)

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
