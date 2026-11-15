"""Draft listing fixtures; never access Apple, credentials or a real CLI."""

import copy
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import sync_apple_listing as listing


COMMIT = "b" * 40


def resource(kind, identifier, **attributes):
    return {"type": kind, "id": identifier, "attributes": attributes}


def metadata():
    return {"schema_version": 1, "locale": "en-US", "app": {"source_version": "1.0.0"}, "apple": {
        "version": "1.0.0", "subtitle": "Beauty routines, made personal", "description": "Prepared fixture description.",
        "keywords": "makeup,beauty,routine", "promotional_text": "Prepared fixture promotion.",
        "support_url": "https://www.korlixdeveloper.com/support.html",
        "privacy_url": listing.PRIVACY_URL,
        "primary_category": "LIFESTYLE", "secondary_category": "SHOPPING",
        "candidate_identifiers": {"app_store_connect_numeric_app_id": listing.APP_ID,
                                  "bundle_id": listing.BUNDLE_ID, "app_store_connect_sku": listing.SKU},
    }}


class FixtureClient:
    def __init__(self):
        self.resources = {
            "apps": resource("apps", listing.APP_ID, bundleId=listing.BUNDLE_ID, sku=listing.SKU),
            "appInfos": resource("appInfos", "INFO", appStoreState="PREPARE_FOR_SUBMISSION", appStoreAgeRating="UNRELATED"),
            "appStoreVersions": resource("appStoreVersions", "VERSION", platform="IOS", versionString="1.0",
                                          appVersionState="PREPARE_FOR_SUBMISSION", releaseType="UNRELATED"),
            "appInfoLocalizations": resource("appInfoLocalizations", "INFOLOCALE", locale="en-US", subtitle=None,
                                               name="Esha by Korlix", privacyPolicyUrl=None, privacyChoicesUrl=None,
                                               privacyPolicyText="PRIVATE-UNRELATED"),
            "appStoreVersionLocalizations": resource("appStoreVersionLocalizations", "VERSIONLOCALE", locale="en-US",
                                                       description=None, keywords=None, promotionalText=None, supportUrl=None,
                                                       whatsNew="UNRELATED", marketingUrl="PRIVATE-UNRELATED"),
        }
        self.categories = []
        for identifier in ["LIFESTYLE", "SHOPPING"]:
            value = resource("appCategories", identifier, platforms=["IOS", "TV_OS"])
            value["relationships"] = {"parent": {"data": None, "links": {"related": "unused"}}}
            self.categories.append(value)
        self.category_links = {"primaryCategory": None, "secondaryCategory": None}
        self.builds = []
        self.selected_build = None
        self.calls = []
        self.updates = []
        self.on_get = None
        self.on_update = None
        self.on_list = None
        self.extra_info_locales = []

    def get(self, path, kind, identifier):
        self.calls.append(("GET", path))
        if self.on_get:
            self.on_get(path, kind)
        return listing.resource(copy.deepcopy(self.resources[kind]), kind, identifier)

    def list(self, path, kind, *, parameters=None):
        self.calls.append(("LIST", path))
        if self.on_list:
            self.on_list(path, kind)
        if kind == "builds":
            return copy.deepcopy(self.builds)
        if kind == "appCategories":
            return copy.deepcopy(self.categories)
        value = [copy.deepcopy(self.resources[kind])]
        if kind == "appInfoLocalizations":
            value += copy.deepcopy(self.extra_info_locales)
        return value

    def linkage(self, path, kind):
        self.calls.append(("LINK", path))
        return self.selected_build if kind == "builds" else self.category_links[path.split("/")[-1]]

    def update(self, operation):
        self.updates.append(operation)
        if self.on_update:
            self.on_update(operation)
        if operation.kind == "appInfos":
            self.category_links.update(operation.after)
        else:
            self.resources[operation.kind]["attributes"].update(operation.after)


class SynchronizationTests(unittest.TestCase):
    def setUp(self):
        self.client = FixtureClient()
        self.metadata = metadata()
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.report_path = Path(self.directory.name) / listing.REPORT_FILE

    def run_sync(self, apply=True):
        return listing.synchronize(self.client, self.metadata, apply_draft=apply,
                                   report_path=self.report_path, source_commit=COMMIT)

    def test_default_plan_has_no_updates_and_only_public_report_fields(self):
        report = self.run_sync(False)
        self.assertEqual(report["status"], "plan_only_no_changes")
        self.assertEqual(len(report["planned_operations"]), 4)
        self.assertEqual(self.client.updates, [])
        text = self.report_path.read_text()
        self.assertNotIn("PRIVATE-UNRELATED", text)
        self.assertNotIn("appStoreAgeRating", text)
        for field in ["uploaded", "submitted", "published", "declarations_modified", "access_changed"]:
            self.assertFalse(report[field])

    def test_applies_only_expected_draft_fields_and_second_run_is_idempotent(self):
        report = self.run_sync()
        self.assertEqual(report["status"], "draft_listing_synchronized")
        self.assertEqual(len(self.client.updates), 4)
        self.assertEqual([operation.kind for operation in self.client.updates], [
            "appStoreVersions", "appInfoLocalizations", "appInfos", "appStoreVersionLocalizations",
        ])
        self.assertEqual(self.client.resources["appInfoLocalizations"]["attributes"]["privacyPolicyUrl"], listing.PRIVACY_URL)
        self.assertEqual(self.client.resources["appInfoLocalizations"]["attributes"]["privacyChoicesUrl"], listing.PRIVACY_URL + "#deletion")
        self.assertEqual(self.client.resources["appInfoLocalizations"]["attributes"]["privacyPolicyText"], "PRIVATE-UNRELATED")
        self.assertEqual(self.client.resources["appStoreVersions"]["attributes"]["releaseType"], "UNRELATED")
        self.assertEqual(self.client.resources["appStoreVersionLocalizations"]["attributes"]["whatsNew"], "UNRELATED")
        second = self.run_sync()
        self.assertEqual(second["planned_operations"], [])
        self.assertEqual(len(self.client.updates), 4)

    def test_wrong_app_identifier_bundle_or_sku_stops_before_updates(self):
        for key in ["id", "bundleId", "sku"]:
            with self.subTest(field=key):
                self.client = FixtureClient()
                app = self.client.resources["apps"]
                (app if key == "id" else app["attributes"])[key] = "OTHERAPP"
                with self.assertRaises(listing.ListingError):
                    self.run_sync()
                self.assertEqual(self.client.updates, [])

    def test_locked_states_or_conflicting_new_and_legacy_states_stop(self):
        for kind, field in [("appInfos", "appStoreState"), ("appStoreVersions", "appVersionState")]:
            with self.subTest(kind=kind):
                self.client = FixtureClient()
                self.client.resources[kind]["attributes"][field] = "WAITING_FOR_REVIEW"
                with self.assertRaises(listing.ListingError):
                    self.run_sync()
                self.assertEqual(self.client.updates, [])
        self.client = FixtureClient()
        self.client.resources["appInfos"]["attributes"]["state"] = "READY_FOR_DISTRIBUTION"
        with self.assertRaises(listing.ListingError):
            self.run_sync()
        self.assertEqual(self.client.updates, [])

    def test_version_rename_refuses_existing_or_selected_build(self):
        for field in ["builds", "selected_build"]:
            with self.subTest(field=field):
                self.client = FixtureClient()
                setattr(self.client, field, [resource("builds", "BUILD", version="1")] if field == "builds" else "BUILD")
                with self.assertRaisesRegex(listing.ListingError, "build exists"):
                    self.run_sync()
                self.assertEqual(self.client.updates, [])

    def test_version_already_100_allows_draft_text_with_existing_build(self):
        self.client.resources["appStoreVersions"]["attributes"]["versionString"] = "1.0.0"
        self.client.builds = [resource("builds", "BUILD", version="1")]
        report = self.run_sync()
        self.assertEqual(report["status"], "draft_listing_synchronized")
        self.assertNotIn("appStoreVersions", [operation.kind for operation in self.client.updates])

    def test_build_arriving_between_plan_and_rename_stops_before_update(self):
        lookups = []
        def appearing(path, kind):
            if kind == "builds":
                lookups.append(path)
                if len(lookups) == 2:
                    self.client.builds = [resource("builds", "BUILD", version="1")]
        self.client.on_list = appearing
        with self.assertRaisesRegex(listing.ListingError, "build exists"):
            self.run_sync()
        self.assertEqual(self.client.updates, [])

    def test_state_change_before_mutation_stops(self):
        def change(path, kind):
            if kind == "appInfos":
                self.client.resources[kind]["attributes"]["appStoreState"] = "WAITING_FOR_REVIEW"
        self.client.on_get = change
        with self.assertRaises(listing.ListingError):
            self.run_sync()
        self.assertEqual(self.client.updates, [])

    def test_concurrent_subtitle_edit_is_not_overwritten(self):
        self.client.resources["appStoreVersions"]["attributes"]["versionString"] = "1.0.0"
        def change(path, kind):
            if kind == "appInfoLocalizations":
                self.client.resources[kind]["attributes"]["subtitle"] = "Another editor's draft"
        self.client.on_get = change
        with self.assertRaisesRegex(listing.ListingError, "concurrently"):
            self.run_sync()
        self.assertEqual(self.client.updates, [])

    def test_missing_or_duplicate_en_us_locale_does_not_create_one(self):
        for duplicate in [False, True]:
            with self.subTest(duplicate=duplicate):
                self.client = FixtureClient()
                if duplicate:
                    self.client.extra_info_locales = [resource("appInfoLocalizations", "OTHERLOCALE", locale="en-US", subtitle=None)]
                else:
                    self.client.resources["appInfoLocalizations"]["attributes"]["locale"] = "en-GB"
                with self.assertRaises(listing.ListingError):
                    self.run_sync()
                self.assertEqual(self.client.updates, [])

    def test_categories_must_exist_for_ios_as_top_level_categories(self):
        for variant in ["missing", "platform", "parent"]:
            with self.subTest(variant=variant):
                self.client = FixtureClient()
                if variant == "missing":
                    self.client.categories.pop()
                elif variant == "platform":
                    self.client.categories[0]["attributes"]["platforms"] = ["MAC_OS"]
                else:
                    self.client.categories[0]["relationships"]["parent"]["data"] = {"type": "appCategories", "id": "GAMES"}
                with self.assertRaises(listing.ListingError):
                    self.run_sync()
                self.assertEqual(self.client.updates, [])

    def test_missing_metadata_and_unapproved_version_fail_before_apple_reads(self):
        for field, value in [("version", "2.0.0"), ("description", "x" * 4001), ("keywords", None),
                             ("secondary_category", "MEDICAL"), ("support_url", "https://example.com"),
                             ("privacy_url", "https://example.com")]:
            with self.subTest(field=field):
                self.client = FixtureClient()
                self.metadata = metadata()
                self.metadata["apple"][field] = value
                with self.assertRaises(listing.ListingError):
                    self.run_sync()
                self.assertEqual(self.client.calls, [])

    def test_auth_failure_after_one_change_reports_partial_progress_without_retry(self):
        def fail_second(operation):
            if len(self.client.updates) == 2:
                raise listing.ListingError("The existing Apple integration rejected authentication or access (HTTP 401). No retry was attempted.")
        self.client.on_update = fail_second
        with self.assertRaises(listing.ListingError):
            self.run_sync()
        report = json.loads(self.report_path.read_text())
        self.assertEqual(report["status"], "stopped_review_partial_progress")
        self.assertEqual(len(report["attempted_operations"]), 2)
        self.assertEqual(len(report["verified_operations"]), 1)
        self.assertEqual(len(self.client.updates), 2)
        self.assertEqual(self.client.resources["appStoreVersions"]["attributes"]["versionString"], "1.0.0")


class Response(io.BytesIO):
    def getcode(self):
        return 200


class TransportTests(unittest.TestCase):
    def client(self, open_request, run_cli=None):
        kwargs = {"open_request": open_request}
        if run_cli is not None:
            kwargs["run_cli"] = run_cli
        return listing.AppleClient(lambda: {"Authorization": "Bearer FIXTURE-TOKEN"}, "/fixture/app-store-connect", **kwargs)

    def test_http_auth_error_is_sanitized_once_and_redirects_are_disabled(self):
        for status in [401, 403]:
            with self.subTest(status=status):
                calls = []
                def failing(request, timeout):
                    calls.append(request)
                    raise urllib.error.HTTPError(request.full_url, status, "PRIVATE-RESPONSE", {}, io.BytesIO(b"SECRET"))
                with self.assertRaises(listing.ListingError) as error:
                    self.client(failing).document("GET", f"/v1/apps/{listing.APP_ID}")
                self.assertEqual(len(calls), 1)
                self.assertNotIn("PRIVATE-RESPONSE", str(error.exception))
                self.assertNotIn("SECRET", str(error.exception))
        self.assertIsNone(listing.NoRedirects().redirect_request(None, None, 307, None, None, "https://example.com"))

    def test_complete_pagination_and_missing_data_total_mismatch_or_foreign_next_fail(self):
        first_path = f"/v1/apps/{listing.APP_ID}/appInfos"
        for variant in ["complete", "missing", "total", "foreign"]:
            with self.subTest(variant=variant):
                calls = []
                def page(request, timeout):
                    calls.append(request.full_url)
                    if variant == "missing":
                        body = {"links": {}}
                    elif len(calls) == 1:
                        origin = "https://example.com" if variant == "foreign" else listing.API_ORIGIN
                        body = {"data": [resource("appInfos", "ONE", appStoreState="PREPARE_FOR_SUBMISSION")],
                                "links": {"next": origin + first_path + "?cursor=2"}, "meta": {"paging": {"total": 3 if variant == "total" else 2}}}
                    else:
                        body = {"data": [resource("appInfos", "TWO", appStoreState="READY_FOR_DISTRIBUTION")],
                                "links": {}, "meta": {"paging": {"total": 3 if variant == "total" else 2}}}
                    return Response(json.dumps(body).encode())
                client = self.client(page)
                if variant == "complete":
                    self.assertEqual(len(client.list(first_path, "appInfos")), 2)
                else:
                    with self.assertRaises(listing.ListingError):
                        client.list(first_path, "appInfos")
                    if variant == "foreign":
                        self.assertEqual(len(calls), 1)

    def test_payload_rejects_declarations_release_or_submission_endpoints(self):
        def no_request(*args, **kwargs):
            self.fail("An unapproved request reached the transport")
        client = self.client(no_request)
        for kind, field, value in [("appInfoLocalizations", "privacyPolicyText", "Unapproved declaration"),
                                   ("appInfoLocalizations", "privacyPolicyUrl", "https://example.com"),
                                   ("appStoreVersions", "releaseType", "AFTER_APPROVAL"),
                                   ("appInfos", "ageRatingDeclaration", "X")]:
            with self.subTest(field=field):
                body = {"data": {"type": kind, "id": "RESOURCE", "attributes": {field: value}}}
                with self.assertRaises(listing.ListingError):
                    client.document("PATCH", f"/v1/{kind}/RESOURCE", body=body)
        with self.assertRaises(listing.ListingError):
            client.document("POST", "/v1/appStoreVersionSubmissions", body={})

    def test_cli_version_fields_are_allowlisted_no_retry_and_temporary_logs_removed(self):
        calls = []
        def command(arguments, **options):
            calls.append((arguments, options))
            (Path(options["env"]["TMPDIR"]) / "raw.log").write_text("RAW-FIXTURE")
            return subprocess.CompletedProcess(arguments, 0,
                json.dumps(resource("appStoreVersionLocalizations", "LOCALE", locale="en-US", description="Prepared")).encode(), b"")
        client = self.client(lambda *args, **kwargs: self.fail("CLI-supported update used HTTP"), command)
        client.update(listing.Operation("appStoreVersionLocalizations", "LOCALE", {"description": None}, {"description": "Prepared"}))
        self.assertEqual(len(calls), 1)
        arguments, options = calls[0]
        self.assertIn("--description=Prepared", arguments)
        self.assertNotIn("--whats-new", arguments)
        for flag in ["--api-unauthorized-retries", "--api-server-error-retries"]:
            self.assertEqual(arguments[arguments.index(flag) + 1], "0")
        self.assertFalse(Path(options["env"]["TMPDIR"]).exists())

    def test_cli_implicit_whats_new_environment_is_removed(self):
        environment = {"APP_STORE_CONNECT_WHATS_NEW": "Unapproved notes", "APP_STORE_CONNECT_PRIVATE_KEY": "FIXTURE"}
        with mock.patch.object(subprocess, "run", return_value=None) as run:
            listing.listing_subprocess(["fixture"], env=environment)
        self.assertNotIn("APP_STORE_CONNECT_WHATS_NEW", run.call_args.kwargs["env"])
        self.assertEqual(run.call_args.kwargs["env"]["APP_STORE_CONNECT_PRIVATE_KEY"], "FIXTURE")


if __name__ == "__main__":
    unittest.main()
