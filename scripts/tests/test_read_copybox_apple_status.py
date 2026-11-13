import importlib.util
import json
from pathlib import Path
import unittest

MODULE = Path(__file__).resolve().parents[1] / "read_copybox_apple_status.py"
spec = importlib.util.spec_from_file_location("copybox_status", MODULE)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def entity(kind, ident, attrs=None, relationships=None):
    return {"type": kind, "id": ident, "attributes": attrs or {},
            "relationships": relationships or {}}


class Response:
    def __init__(self, payload, status=200, body=None):
        self.payload = payload
        self.status_code = status
        self.content = body if body is not None else json.dumps(payload).encode()

    def json(self):
        return self.payload


class Session:
    def __init__(self, routes):
        self.routes = routes
        self.calls = []

    def request(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        if url not in self.routes:
            raise AssertionError("Unplanned request")
        item = self.routes[url]
        if isinstance(item, Exception):
            raise item
        return item


def fixture():
    root = audit.ORIGIN + audit.APP_PATH
    routes = {}

    def put(path, data, next_url=None):
        routes[audit.ORIGIN + path] = Response({"data": data, "links": {"next": next_url}})

    put(audit.APP_PATH, entity("apps", audit.APP_ID, {
        "bundleId": audit.BUNDLE_ID, "name": "Ignored private app name",
        "primaryLocale": "en-US", "contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT",
    }))
    put(audit.APP_PATH + "/appStoreVersions", [entity("appStoreVersions", "version-1", {
        "platform": "IOS", "versionString": "1.0.0", "appStoreState": "PREPARE_FOR_SUBMISSION",
        "appVersionState": "PREPARE_FOR_SUBMISSION", "releaseType": "MANUAL",
        "copyright": "PRIVATE COPYRIGHT VALUE", "secret": "EXTRA_VERSION_SECRET",
    })])
    put("/v1/appStoreVersions/version-1/relationships/build", {"type": "builds", "id": "build-1"})
    put("/v1/appStoreVersions/version-1/appStoreReviewDetail", entity("appStoreReviewDetails", "review-1", {
        "demoAccountRequired": True, "demoAccountName": "REVIEWER_IDENTIFIER_SECRET",
        "demoAccountPassword": "REVIEWER_PASSWORD_SECRET", "contactFirstName": "CONTACT_FIRST_SECRET",
        "contactLastName": "CONTACT_LAST_SECRET", "contactPhone": "CONTACT_PHONE_SECRET",
        "contactEmail": "CONTACT_EMAIL_SECRET", "notes": "NOTES_SECRET",
        "unexpectedCredential": "EXTRA_REVIEW_SECRET",
    }))
    put(audit.APP_PATH + "/appInfos", [entity("appInfos", "info-1", {
        "appStoreState": "PREPARE_FOR_SUBMISSION", "state": "PREPARE_FOR_SUBMISSION",
        "appStoreAgeRating": "SIXTEEN_PLUS",
    })])
    put("/v1/appInfos/info-1/ageRatingDeclaration", entity("ageRatingDeclarations", "age-1", {
        "advertising": False, "gambling": None, "ageRatingOverrideV2": "SIXTEEN_PLUS",
        "developerAgeRatingInfoUrl": "https://private.invalid/SECRET_URL",
        "unknownPrivateField": "EXTRA_AGE_SECRET",
    }))
    put(audit.APP_PATH + "/builds", [entity("builds", "build-1", {
        "version": "1", "processingState": "VALID", "expired": False,
        "usesNonExemptEncryption": False, "uploadedDate": "2026-11-04T12:00:00Z",
        "expirationDate": "2027-02-02T12:00:00Z", "minOsVersion": "15.0",
        "iconAssetToken": {"token": "ICON_SECRET"},
    })])
    put("/v1/builds/build-1/preReleaseVersion", entity("preReleaseVersions", "pre-1", {
        "version": "1.0.0", "platform": "IOS",
    }))
    put("/v1/builds/build-1/buildBetaDetail", entity("buildBetaDetails", "beta-detail-1", {
        "internalBuildState": "READY_FOR_BETA_TESTING", "externalBuildState": "READY_FOR_BETA_SUBMISSION",
        "autoNotifyEnabled": False,
    }))
    put(audit.APP_PATH + "/betaGroups", [entity("betaGroups", "group-1", {
        "name": "GROUP_NAME_SECRET", "isInternalGroup": True, "hasAccessToAllBuilds": False,
        "publicLinkEnabled": False, "publicLink": "https://secret.invalid/",
    })])
    put("/v1/betaGroups/group-1/relationships/betaTesters", [{"type": "betaTesters", "id": "TESTER-ID-SECRET"}])
    put("/v1/betaGroups/group-1/relationships/builds", [{"type": "builds", "id": "build-1"}])
    put(audit.APP_PATH + "/reviewSubmissions", [entity("reviewSubmissions", "submission-1", {
        "platform": "IOS", "state": "READY_FOR_REVIEW", "submittedDate": None,
        "privateNote": "SUBMISSION_SECRET",
    })])
    return routes


class ReadOnlyAuditTests(unittest.TestCase):
    def make_api(self, routes=None):
        session = Session(routes or fixture())
        return audit.AppleReadOnly(session, lambda: {"Authorization": "Bearer SYNTHETIC"}), session

    def test_only_app_identity_route_before_identity_verification(self):
        api, session = self.make_api()
        for path in (audit.APP_PATH + "/builds", "/v1/apps/999", audit.ORIGIN + audit.APP_PATH,
                     audit.APP_PATH + "?include=users", "/v1/users"):
            with self.assertRaises(audit.AuditError):
                api.get(path)
        self.assertEqual(session.calls, [])

    def test_identity_mismatch_stops_before_any_related_read(self):
        routes = fixture()
        routes[audit.ORIGIN + audit.APP_PATH].payload["data"]["attributes"]["bundleId"] = "other.app"
        session = Session(routes)
        with self.assertRaisesRegex(audit.AuditError, "identity did not match"):
            audit.run(session, lambda: {})
        self.assertEqual(len(session.calls), 1)

    def test_related_ids_are_not_allowed_until_seen_in_app_list(self):
        api, session = self.make_api()
        api.verify_app()
        with self.assertRaises(audit.AuditError):
            api.get("/v1/appStoreVersions/version-1/appStoreReviewDetail")
        api.app_list("appStoreVersions")
        api.get("/v1/appStoreVersions/version-1/appStoreReviewDetail")
        with self.assertRaises(audit.AuditError):
            api.get("/v1/appStoreVersions/unknown/appStoreReviewDetail")
        with self.assertRaises(audit.AuditError):
            api.get("/v1/appStoreVersions/version-1/other")

    def test_cross_app_relationship_fails_before_registration(self):
        api, session = self.make_api()
        api.verify_app()
        item = entity("builds", "foreign", relationships={"app": {"data": {"type": "apps", "id": "999"}}})
        with self.assertRaises(audit.AuditError):
            api.register_from_app_list("builds", item)
        with self.assertRaises(audit.AuditError):
            api.get("/v1/builds/foreign/buildBetaDetail")

    def test_invalid_identifiers_cannot_create_routes(self):
        api, session = self.make_api()
        api.verify_app()
        for invalid in ("../users", "a?x=1", "a/b", "", "x" * 129):
            with self.assertRaises(audit.AuditError):
                api.register_from_app_list("builds", entity("builds", invalid))

    def test_requests_are_get_only_no_redirect_no_body(self):
        session = Session(fixture())
        report = audit.run(session, lambda: {"Authorization": "Bearer SYNTHETIC"})
        self.assertTrue(report["readOnly"])
        for method, url, options in session.calls:
            self.assertEqual(method, "GET")
            self.assertTrue(url.startswith(audit.ORIGIN + "/v1/"))
            self.assertIs(options["allow_redirects"], False)
            self.assertEqual(options["timeout"], 30)
            self.assertNotIn("json", options)
            self.assertNotIn("data", options)
        self.assertEqual(report["requestCount"], len(session.calls))

    def test_report_contains_presence_only_no_private_values(self):
        report = audit.run(Session(fixture()), lambda: {})
        encoded = json.dumps(report)
        for private in ("REVIEWER_IDENTIFIER_SECRET", "REVIEWER_PASSWORD_SECRET", "CONTACT_FIRST_SECRET",
                        "CONTACT_LAST_SECRET", "CONTACT_PHONE_SECRET", "CONTACT_EMAIL_SECRET",
                        "NOTES_SECRET", "EXTRA_REVIEW_SECRET", "EXTRA_VERSION_SECRET", "EXTRA_AGE_SECRET",
                        "ICON_SECRET", "GROUP_NAME_SECRET", "TESTER-ID-SECRET", "SUBMISSION_SECRET",
                        "PRIVATE COPYRIGHT VALUE", "SECRET_URL", "secret.invalid", "Ignored private app name"):
            self.assertNotIn(private, encoded)
        detail = report["appStoreVersions"][0]["reviewDetails"]
        self.assertIs(detail["demoAccountNamePresent"], True)
        self.assertIs(detail["demoAccountPasswordPresent"], True)
        self.assertEqual(report["betaGroups"][0]["testers"]["countOnFirstPage"], 1)

    def test_missing_review_fields_reported_without_false_ready(self):
        routes = fixture()
        attrs = routes[audit.ORIGIN + "/v1/appStoreVersions/version-1/appStoreReviewDetail"].payload["data"]["attributes"]
        attrs["demoAccountPassword"] = "  "
        attrs["contactEmail"] = None
        report = audit.run(Session(routes), lambda: {})
        self.assertIn("target_review_demoAccountPassword_missing", report["detectedMissingFields"])
        self.assertIn("target_review_contactEmail_missing", report["detectedMissingFields"])
        self.assertEqual(report["overallSubmissionReadiness"], "NOT_ESTABLISHED_BY_READ_ONLY_AUDIT")

    def test_missing_age_values_distinguished_from_not_returned(self):
        report = audit.run(Session(fixture()), lambda: {})
        declaration = report["appInfos"][0]["ageDeclaration"]
        self.assertEqual(declaration["unansweredReturnedDescriptors"], ["gambling"])
        self.assertIn("socialMedia", declaration["notReturnedDescriptors"])
        self.assertIs(declaration["observedAttributes"]["advertising"], False)

    def test_pagination_is_reported_never_followed(self):
        routes = fixture()
        routes[audit.ORIGIN + audit.APP_PATH + "/builds"].payload["links"]["next"] = "https://untrusted.invalid/SECRET"
        session = Session(routes)
        report = audit.run(session, lambda: {})
        self.assertTrue(report["completeness"]["buildsHasMore"])
        self.assertFalse(any("untrusted" in call[1] for call in session.calls))
        self.assertNotIn("untrusted", json.dumps(report))

    def test_response_errors_do_not_reveal_body_or_transport_details(self):
        for value in (Response({"errors": [{"detail": "RESPONSE_SECRET"}]}, status=403),
                      Response({"data": None}, status=302),
                      RuntimeError("TRANSPORT_SECRET")):
            api, session = self.make_api({audit.ORIGIN + audit.APP_PATH: value})
            with self.assertRaises(audit.AuditError) as caught:
                api.verify_app()
            self.assertNotIn("SECRET", str(caught.exception))

    def test_overlarge_response_is_rejected(self):
        api, session = self.make_api({audit.ORIGIN + audit.APP_PATH: Response(
            {"data": None}, body=b"x" * (audit.MAX_RESPONSE_BYTES + 1))})
        with self.assertRaisesRegex(audit.AuditError, "size limit"):
            api.verify_app()


if __name__ == "__main__":
    unittest.main()
