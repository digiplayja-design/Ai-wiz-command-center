import contextlib
from copy import deepcopy
import io
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import select_copybox_apple_build as selection

NEW_BUILD_ID = "11111111-2222-4333-8444-555555555555"
OTHER_BUILD_ID = "99999999-2222-4333-8444-555555555555"
SECRET = "PRIVATE-SERVER-OR-CREDENTIAL-VALUE"


class Response:
    def __init__(self, data=None, status=200):
        self.status_code = status
        self.data = data
        self.content = json.dumps(data).encode() if data is not None else b""

    def json(self):
        return deepcopy(self.data)


class AppleFixture:
    def __init__(self, selected=selection.PREVIOUS_BUILD_ID):
        self.calls = []
        self.app = {"type": "apps", "id": selection.APP_ID, "attributes": {
            "bundleId": selection.BUNDLE_ID, "primaryLocale": "en-US",
            "contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT",
            "privateValue": SECRET,
        }}
        self.version = {"type": "appStoreVersions", "id": selection.VERSION_ID,
                        "attributes": {
                            "versionString": "1.0.0", "platform": "IOS",
                            "appStoreState": "PREPARE_FOR_SUBMISSION",
                            "appVersionState": "PREPARE_FOR_SUBMISSION",
                            "releaseType": "AFTER_APPROVAL", "copyright": SECRET,
                        },
                        "relationships": {"app": {"data": {
                            "type": "apps", "id": selection.APP_ID}}}}
        self.build = {"type": "builds", "id": NEW_BUILD_ID, "attributes": {
            "version": "2", "processingState": "VALID", "expired": False,
            "uploadedDate": "2026-11-14T14:00:00Z", "privateValue": SECRET,
        }, "relationships": {"app": {"data": {"type": "apps", "id": selection.APP_ID}}}}
        self.prerelease = {"type": "preReleaseVersions", "id": "prerelease-1",
                           "attributes": {"version": "1.0.0", "platform": "IOS"}}
        self.selected = selected
        self.version_reads = 0
        self.before_version_read = None
        self.after_patch = None
        self.patch_status = 204
        self.patch_error = False
        self.keep_old_selection = False
        self.duplicate_build = False
        self.more_builds = False
        self.get_error_path = None

    def request(self, method, url, **kwargs):
        self.assert_transport(url, kwargs)
        path = url.removeprefix(selection.ORIGIN)
        self.calls.append((method, path, deepcopy(kwargs.get("json"))))
        if method == "GET":
            if path == self.get_error_path:
                return Response({"errors": [{"detail": SECRET}]}, 500)
            if path == f"/v1/apps/{selection.APP_ID}":
                return Response({"data": self.app})
            if path == f"/v1/apps/{selection.APP_ID}/appStoreVersions":
                self.version_reads += 1
                if self.before_version_read:
                    self.before_version_read(self.version_reads)
                return Response({"data": [self.version]})
            if path == selection.BUILD_RELATION:
                return Response({"data": {"type": "builds", "id": self.selected}})
            if path == f"/v1/apps/{selection.APP_ID}/builds":
                rows = [self.build] * (2 if self.duplicate_build else 1)
                return Response({"data": rows, "links": {
                    "next": "https://outside.invalid/" if self.more_builds else None}})
            if path == f"/v1/builds/{self.build['id']}/preReleaseVersion":
                return Response({"data": self.prerelease})
        if method == "PATCH" and path == selection.BUILD_RELATION:
            if self.patch_error:
                raise RuntimeError(SECRET)
            if self.patch_status == 204 and not self.keep_old_selection:
                self.selected = kwargs["json"]["data"]["id"]
            if self.after_patch:
                self.after_patch()
            return Response(None if self.patch_status == 204 else {"detail": SECRET},
                            self.patch_status)
        raise AssertionError("Unrecognized route")

    @staticmethod
    def assert_transport(url, kwargs):
        assert url.startswith(selection.ORIGIN + "/v1/")
        assert kwargs["allow_redirects"] is False and kwargs["timeout"] == 30
        assert kwargs["headers"] == {"Authorization": SECRET}

    @property
    def writes(self):
        return [call for call in self.calls if call[0] != "GET"]


def execute(fixture, number="2"):
    return selection.run(fixture, lambda: {"Authorization": SECRET}, number)


class SelectionTests(unittest.TestCase):
    def test_valid_build_is_selected_with_only_the_exact_relationship_patch(self):
        fixture = AppleFixture()
        original_attrs = deepcopy(fixture.version["attributes"])
        report = execute(fixture)
        self.assertTrue(report["success"], report)
        self.assertEqual(fixture.writes, [
            ("PATCH", selection.BUILD_RELATION,
             {"data": {"type": "builds", "id": NEW_BUILD_ID}})
        ])
        self.assertEqual(fixture.version["attributes"], original_attrs)
        self.assertTrue(report["selectedBuildVerified"])
        self.assertTrue(report["otherVersionAttributesUnchanged"])
        self.assertFalse(report["mutationOutcomeUnknown"])
        self.assertFalse(report["submissionAttempted"])
        self.assertNotIn(SECRET, json.dumps(report))

    def test_already_selected_build_is_a_verified_idempotent_no_op(self):
        fixture = AppleFixture(selected=NEW_BUILD_ID)
        report = execute(fixture)
        self.assertTrue(report["success"], report)
        self.assertTrue(report["alreadySelected"])
        self.assertTrue(report["selectedBuildVerified"])
        self.assertEqual(fixture.writes, [])

    def test_wrong_app_version_platform_state_or_release_type_cannot_mutate(self):
        mutations = [
            lambda f: f.app.update(id="999999"),
            lambda f: f.app["attributes"].update(bundleId="com.other.app"),
            lambda f: f.version.update(id="other-version"),
            lambda f: f.version["attributes"].update(versionString="2.0.0"),
            lambda f: f.version["attributes"].update(platform="ANDROID"),
            lambda f: f.version["attributes"].update(appVersionState="WAITING_FOR_REVIEW"),
            lambda f: f.version["attributes"].update(appStoreState="READY_FOR_DISTRIBUTION"),
            lambda f: f.version["attributes"].update(releaseType="MANUAL"),
        ]
        for mutate in mutations:
            with self.subTest(mutation=mutations.index(mutate)):
                fixture = AppleFixture()
                mutate(fixture)
                report = execute(fixture)
                self.assertFalse(report["success"])
                self.assertEqual(fixture.writes, [])

    def test_wrong_expired_unprocessed_ambiguous_or_foreign_build_cannot_mutate(self):
        mutations = [
            lambda f: f.build["attributes"].update(version="3"),
            lambda f: f.build["attributes"].update(expired=True),
            lambda f: f.build["attributes"].update(expired=None),
            lambda f: f.build["attributes"].update(processingState="PROCESSING"),
            lambda f: f.build["relationships"]["app"]["data"].update(id="999"),
            lambda f: f.prerelease["attributes"].update(version="2.0.0"),
            lambda f: f.prerelease["attributes"].update(platform="MAC_OS"),
            lambda f: f.build.update(id=selection.PREVIOUS_BUILD_ID),
            lambda f: setattr(f, "duplicate_build", True),
            lambda f: setattr(f, "more_builds", True),
        ]
        for mutate in mutations:
            with self.subTest(mutation=mutations.index(mutate)):
                fixture = AppleFixture()
                mutate(fixture)
                report = execute(fixture)
                self.assertFalse(report["success"])
                self.assertEqual(fixture.writes, [])

    def test_unexpected_existing_or_concurrently_changed_selection_cannot_mutate(self):
        fixture = AppleFixture(selected=OTHER_BUILD_ID)
        self.assertEqual(execute(fixture)["failureCode"], "unexpected_current_build")
        self.assertEqual(fixture.writes, [])
        fixture = AppleFixture()
        fixture.before_version_read = lambda count: (
            setattr(fixture, "selected", OTHER_BUILD_ID) if count == 2 else None)
        self.assertEqual(execute(fixture)["failureCode"], "release_or_build_changed_during_run")
        self.assertEqual(fixture.writes, [])

    def test_failed_or_unconfirmed_patch_is_not_retried_and_does_not_leak_errors(self):
        for kind in ("transport", "http"):
            with self.subTest(kind=kind):
                fixture = AppleFixture()
                fixture.patch_error = kind == "transport"
                fixture.patch_status = 500
                report = execute(fixture)
                self.assertFalse(report["success"])
                self.assertTrue(report["mutationOutcomeUnknown"])
                self.assertEqual(len(fixture.writes), 1)
                self.assertNotIn(SECRET, json.dumps(report))

    def test_readback_and_metadata_changes_prevent_a_false_success(self):
        fixture = AppleFixture()
        fixture.keep_old_selection = True
        report = execute(fixture)
        self.assertEqual(report["failureCode"], "selection_readback_mismatch")
        self.assertTrue(report["mutationOutcomeUnknown"])
        self.assertEqual(len(fixture.writes), 1)
        fixture = AppleFixture()
        fixture.after_patch = lambda: fixture.version["attributes"].update(copyright="changed")
        report = execute(fixture)
        self.assertEqual(report["failureCode"], "other_version_attributes_changed")
        self.assertFalse(report["success"])
        self.assertTrue(report["mutationOutcomeUnknown"])
        self.assertEqual(len(fixture.writes), 1)

    def test_invalid_or_rollback_build_number_is_rejected_before_any_request(self):
        for value in ("", "1", "0", "02", "2.0", "../2", SECRET, 2, True):
            with self.subTest(value_type=type(value).__name__):
                fixture = AppleFixture()
                report = execute(fixture, value)
                self.assertEqual(report["failureCode"], "expected_build_number_invalid")
                self.assertEqual(fixture.calls, [])
                self.assertNotIn(SECRET, json.dumps(report))

    def test_direct_mutation_cannot_bypass_the_scoped_checks(self):
        fixture = AppleFixture()
        api = selection.AppleBuildSelection(
            fixture, lambda: {"Authorization": SECRET}, selection.new_report("2"), "2")
        with self.assertRaises(selection.SelectionStop):
            api.select_once(NEW_BUILD_ID)
        self.assertEqual(fixture.calls, [])

    def test_raw_get_errors_and_invalid_command_arguments_are_not_logged(self):
        fixture = AppleFixture()
        fixture.get_error_path = f"/v1/apps/{selection.APP_ID}"
        report = execute(fixture)
        self.assertFalse(report["success"])
        self.assertEqual(fixture.writes, [])
        self.assertNotIn(SECRET, json.dumps(report))
        output = io.StringIO()
        with patch.object(sys, "argv", ["script", SECRET]), contextlib.redirect_stderr(output):
            self.assertEqual(selection.main(), 2)
        self.assertNotIn(SECRET, output.getvalue())


if __name__ == "__main__":
    unittest.main()
