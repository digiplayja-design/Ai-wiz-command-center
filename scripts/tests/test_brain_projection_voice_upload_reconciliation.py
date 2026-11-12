import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
from urllib.parse import urlparse

SCRIPT = Path(__file__).resolve().parents[1] / "reconcile_brain_projection_voice_upload.py"
spec = importlib.util.spec_from_file_location("brain_projection_voice_upload_reconciliation", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
BUILD_ID = "11111111-1111-4111-8111-111111111120"


def item(kind, identity, **attributes):
    return {"type": kind, "id": identity, "attributes": attributes}


class Response:
    status_code = 200

    def __init__(self, data, links=None):
        self.payload = {"data": copy.deepcopy(data), "links": links or {}}

    def json(self):
        return copy.deepcopy(self.payload)


class Session:
    """Fake transport only; no sockets or mutable Apple methods exist."""

    def __init__(self):
        app = item("apps", module.APP_ID, bundleId=module.BUNDLE_ID)
        self.resources = {
            f"/v1/apps/{module.APP_ID}": app,
            f"/v1/builds/{BUILD_ID}/app": copy.deepcopy(app),
            f"/v1/builds/{BUILD_ID}/preReleaseVersion": item(
                "preReleaseVersions", "version-resource", version=module.VERSION, platform="IOS"),
            f"/v1/builds/{BUILD_ID}/buildBetaDetail": item(
                "buildBetaDetails", "detail-resource", internalBuildState="READY_FOR_BETA_TESTING"),
            module.GROUP_PATH: item("betaGroups", module.GROUP_ID,
                                    name=module.GROUP_NAME, isInternalGroup=True),
            f"{module.GROUP_PATH}/app": copy.deepcopy(app),
        }
        self.builds = [item("builds", BUILD_ID, version="20", processingState="VALID", expired=False)]
        self.group_builds = [item("builds", "previous-build", version="19")]
        self.next_url = None
        self.calls = []

    def request(self, method, url, **kwargs):
        if method != "GET":
            raise AssertionError("This transport can only read")
        path = urlparse(url).path
        self.calls.append((method, path, copy.deepcopy(kwargs)))
        if path in self.resources:
            return Response(self.resources[path])
        if path == "/v1/builds":
            return Response(self.builds, links={"next": self.next_url})
        if path == f"{module.GROUP_PATH}/builds":
            return Response(self.group_builds)
        raise AssertionError("Unexpected read")


class ReconciliationTests(unittest.TestCase):
    def setUp(self):
        self.session = Session()
        self.auth_calls = []

    def api(self):
        def auth():
            self.auth_calls.append(True)
            return {"Authorization": "Bearer TEST_ONLY"}
        return module.AppleGetOnly(self.session, auth)

    def run_observation(self, check_group=False):
        return module.run(self.api(), check_group=check_group)

    def test_exact_processed_presence_is_sanitized_read_only_and_not_delivery(self):
        report = self.run_observation(check_group=True)
        self.assertEqual(report["presenceStatus"], "found")
        self.assertIs(report["exactBuildPresent"], True)
        self.assertIs(report["processingVerified"], True)
        self.assertEqual(report["appleBuildId"], BUILD_ID)
        self.assertEqual(report["internalBuildState"], "READY_FOR_BETA_TESTING")
        self.assertIs(report["existingGroup"]["buildLinked"], False)
        self.assertIs(report["readOnly"], True)
        self.assertIs(report["deliveryVerified"], False)
        self.assertIs(report["sourceAttestedByApple"], False)
        self.assertNotIn("TEST_ONLY", str(report))
        listing = next(call for call in self.session.calls if call[1] == "/v1/builds")
        self.assertEqual(listing[2]["params"], {
            "limit": 200, "filter[app]": "6829319523", "filter[version]": "20"})
        for method, path, kwargs in self.session.calls:
            self.assertEqual(method, "GET")
            self.assertNotIn("betaTesters", path)
            self.assertFalse(kwargs["allow_redirects"])
            self.assertEqual(kwargs["timeout"], 30)

    def test_existing_link_and_testing_state_still_do_not_claim_delivery(self):
        self.session.group_builds.append(self.session.builds[0])
        self.session.resources[f"/v1/builds/{BUILD_ID}/buildBetaDetail"]["attributes"]["internalBuildState"] = "IN_BETA_TESTING"
        report = self.run_observation(check_group=True)
        self.assertTrue(report["existingGroup"]["buildLinked"])
        self.assertEqual(report["internalBuildState"], "IN_BETA_TESTING")
        self.assertFalse(report["deliveryVerified"])

    def test_missing_build_is_an_observation_without_retry_or_substitute(self):
        self.session.builds = []
        report = self.run_observation(check_group=True)
        self.assertEqual(report["presenceStatus"], "not_found")
        self.assertFalse(report["exactBuildPresent"])
        self.assertEqual(len(self.session.calls), 2)

    def test_ambiguous_results_do_not_select_a_build(self):
        self.session.builds.append(copy.deepcopy(self.session.builds[0]))
        report = self.run_observation()
        self.assertEqual(report["presenceStatus"], "ambiguous")
        self.assertFalse(report["exactBuildPresent"])
        self.assertNotIn("appleBuildId", report)
        self.assertEqual(len(self.session.calls), 2)

    def test_build19_is_never_a_fallback(self):
        self.session.builds[0]["attributes"]["version"] = "19"
        with self.assertRaisesRegex(module.ReconciliationError, "Wrong build number"):
            self.run_observation()

    def test_wrong_app_or_bundle_in_relationship_is_rejected(self):
        for path in (f"/v1/apps/{module.APP_ID}", f"/v1/builds/{BUILD_ID}/app", f"{module.GROUP_PATH}/app"):
            for field in ("id", "bundleId"):
                with self.subTest(path=path, field=field):
                    self.session = Session()
                    target = self.session.resources[path]
                    (target if field == "id" else target["attributes"])[field] = "wrong-app"
                    with self.assertRaisesRegex(module.ReconciliationError, "Wrong Apple app"):
                        self.run_observation(check_group=True)

    def test_wrong_version_or_platform_is_rejected(self):
        for field, value in (("version", "1.0.1"), ("platform", "MAC_OS")):
            with self.subTest(field=field):
                self.session = Session()
                self.session.resources[f"/v1/builds/{BUILD_ID}/preReleaseVersion"]["attributes"][field] = value
                with self.assertRaisesRegex(module.ReconciliationError, "Wrong prerelease"):
                    self.run_observation()

    def test_processing_failures_and_expiration_are_not_readiness(self):
        for state, expired in (("PROCESSING", False), ("FAILED", False), ("INVALID", False), ("VALID", True)):
            with self.subTest(state=state, expired=expired):
                self.session = Session()
                self.session.builds[0]["attributes"].update(processingState=state, expired=expired)
                report = self.run_observation()
                self.assertTrue(report["exactBuildPresent"])
                self.assertFalse(report["processingVerified"])
                self.assertFalse(report["deliveryVerified"])
                self.assertEqual(report["processingState"], state)

    def test_unknown_processing_or_missing_expiration_does_not_claim_readiness(self):
        for field, value in (("processingState", "SURPRISE"), ("expired", None)):
            with self.subTest(field=field):
                self.session = Session()
                self.session.builds[0]["attributes"][field] = value
                with self.assertRaises(module.ReconciliationError):
                    self.run_observation()

    def test_external_group_is_rejected(self):
        self.session.resources[module.GROUP_PATH]["attributes"]["isInternalGroup"] = False
        with self.assertRaisesRegex(module.ReconciliationError, "Wrong existing internal group"):
            self.run_observation(check_group=True)

    def test_every_mutating_method_is_rejected_before_credentials_or_network(self):
        api = self.api()
        for method in ("POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"):
            with self.subTest(method=method), self.assertRaisesRegex(module.ReconciliationError, "GET only"):
                api.request(method, f"{module.GROUP_PATH}/relationships/builds")
        self.assertEqual(self.auth_calls, [])
        self.assertEqual(self.session.calls, [])

    def test_unrelated_gets_and_credential_redirect_targets_are_rejected(self):
        api = self.api()
        for url in ("/v1/betaTesters", "/v1/apps/another-app", "/v1/users",
                    f"{module.GROUP_PATH}/relationships/builds",
                    "https://example.test/v1/builds", "http://api.appstoreconnect.apple.com/v1/builds",
                    "https://user@api.appstoreconnect.apple.com/v1/builds"):
            with self.subTest(url=url), self.assertRaisesRegex(module.ReconciliationError, "Unexpected Apple"):
                api.request("GET", url)
        self.assertEqual(self.auth_calls, [])
        self.assertEqual(self.session.calls, [])

    def test_external_unrelated_or_changed_filter_pagination_is_rejected(self):
        for url in ("https://example.test/v1/builds", f"/v1/apps/{module.APP_ID}",
                    "/v1/builds?filter%5Bapp%5D=wrong-app", "/v1/builds?filter%5Bversion%5D=19",
                    "/v1/builds"):
            with self.subTest(url=url):
                self.session = Session()
                self.session.next_url = url
                with self.assertRaisesRegex(module.ReconciliationError, "Unexpected Apple"):
                    self.run_observation()
                self.assertEqual(len(self.session.calls), 2)

    def test_environment_cannot_override_fixed_identity(self):
        with patch.dict(module.os.environ, {"APP_ID": "other", "BUNDLE_ID": "other",
                                           "BUILD_NUMBER": "19", "VERSION": "1.0.1"}):
            report = self.run_observation()
        self.assertEqual(report["appId"], "6829319523")
        self.assertEqual(report["buildNumber"], "20")
        self.assertEqual(report["version"], "1.0.2")

    def test_transport_failure_does_not_expose_provider_data_or_credentials(self):
        class BrokenSession:
            def request(self, *args, **kwargs):
                raise RuntimeError("authorization=TEST_ONLY private-key=TEST_ONLY")
        api = module.AppleGetOnly(BrokenSession(), lambda: {})
        with self.assertRaises(module.ReconciliationError) as caught:
            module.run(api)
        self.assertEqual(str(caught.exception), "Apple GET transport failed; no mutation was attempted")


if __name__ == "__main__":
    unittest.main()
