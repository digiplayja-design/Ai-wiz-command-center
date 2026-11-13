import base64
import io
import json
from pathlib import Path
import sys
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_copybox_reviewer_acceptance as check
from read_copybox_apple_status import APP_PATH, BUNDLE_ID, ORIGIN

PASSWORD = "OFFLINE_PRIVATE_PASSWORD"
TOKEN_MARK = "OFFLINE_PRIVATE_TOKEN_SIGNATURE"
PRIVATE_ERROR = "OFFLINE_PRIVATE_PROVIDER_ERROR"
USER_ID = "OFFLINE_PRIVATE_REVIEWER_ID"


def jwt(expiry):
    body = base64.urlsafe_b64encode(json.dumps({
        "sub": USER_ID, "iss": "https://offline.example.test/auth/v1", "exp": expiry,
    }).encode()).decode().rstrip("=")
    return "eyJhbGciOiJub25lIn0." + body + "." + TOKEN_MARK


class Response:
    def __init__(self, payload, status=200, raw=None):
        self.status_code = status
        self.content = json.dumps(payload).encode() if raw is None else raw
        self.closed = False

    def json(self):
        return json.loads(self.content)

    def iter_content(self, chunk_size):
        for offset in range(0, len(self.content), chunk_size):
            yield self.content[offset:offset + chunk_size]

    def close(self):
        self.closed = True


class Apple:
    def __init__(self, name="Reviewer@korlixdeveloper.com", bundle=BUNDLE_ID,
                 version=check.VERSION_ID, detail=check.REVIEW_DETAIL_ID):
        self.calls = []
        self.responses = {
            ORIGIN + APP_PATH: {"data": {"type": "apps", "id": check.APP_ID,
                "attributes": {"bundleId": bundle, "primaryLocale": "en-US"}}},
            ORIGIN + APP_PATH + "/appStoreVersions": {"data": [{
                "type": "appStoreVersions", "id": version,
                "attributes": {"platform": "IOS", "versionString": "1.0.0"},
                "relationships": {"app": {"data": {"type": "apps", "id": check.APP_ID}}},
            }]},
            ORIGIN + f"/v1/appStoreVersions/{check.VERSION_ID}/appStoreReviewDetail": {
                "data": {"type": "appStoreReviewDetails", "id": detail,
                    "attributes": {"demoAccountRequired": True,
                        "demoAccountName": name, "demoAccountPassword": PASSWORD,
                        "notes": PRIVATE_ERROR}}},
        }

    def request(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        return Response(self.responses[url])


class Backend:
    def __init__(self, failure=None, short_session=False):
        self.calls = []
        self.failure = failure
        self.short_session = short_session

    def request(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        path = url.removeprefix(check.BACKEND_ORIGIN)
        if self.failure == (path, "transport"):
            raise RuntimeError(PASSWORD + TOKEN_MARK + PRIVATE_ERROR)
        if self.failure == (path, "rejected"):
            return Response({"error": PASSWORD + TOKEN_MARK + PRIVATE_ERROR}, 403)
        if path == "/api/auth/signin":
            device = kwargs["json"]["device_id"]
            return Response({"success": True,
                "user": {"id": USER_ID, "email": check.EXPECTED_REVIEWER},
                "session": {"access_token": jwt(time.time() + (120 if self.short_session else 3600)),
                            "refresh_token": "OFFLINE_PRIVATE_REFRESH_TOKEN"},
                "profile": {"private": PRIVATE_ERROR},
                "deviceSession": {"user_id": USER_ID, "device_id": device, "status": "active"}})
        if path == "/api/generate":
            return Response({"content": "OFFLINE_PRIVATE_GENERATED_TEXT", "searched": False,
                "fileRequested": False, "fallbackUsed": False, "creditsUsed": 1,
                "generationId": "OFFLINE_PRIVATE_GENERATION_ID", "authenticated": True})
        if path == "/api/auth/signout":
            return Response({"success": True})
        raise AssertionError("Unexpected endpoint")


class AcceptanceTests(unittest.TestCase):
    def run_check(self, apple=None, backend=None):
        apple, backend = apple or Apple(), backend or Backend()
        captured = io.StringIO()
        with redirect_stdout(captured), redirect_stderr(captured):
            report = check.run(apple, lambda: {"Authorization": "Bearer OFFLINE_APPLE_JWT"}, backend)
        serialized = json.dumps(report) + captured.getvalue()
        for value in (PASSWORD, TOKEN_MARK, PRIVATE_ERROR, USER_ID, check.EXPECTED_REVIEWER,
                      "OFFLINE_PRIVATE_REFRESH_TOKEN", "OFFLINE_PRIVATE_GENERATED_TEXT",
                      "OFFLINE_PRIVATE_GENERATION_ID", "OFFLINE_APPLE_JWT"):
            self.assertNotIn(value, serialized)
        for method, url, args in apple.calls:
            self.assertEqual(method, "GET")
            self.assertTrue(url.startswith(ORIGIN + "/v1/"))
            self.assertIs(args["allow_redirects"], False)
        for method, url, args in backend.calls:
            self.assertEqual(method, "POST")
            self.assertIn(url, {check.BACKEND_ORIGIN + p for p in check.ALLOWED_POSTS})
            self.assertIs(args["allow_redirects"], False)
            self.assertNotIn("OFFLINE_APPLE_JWT", str(args))
        return report, apple, backend

    def test_success_is_one_synthetic_request_and_only_own_logout(self):
        report, apple, backend = self.run_check()
        self.assertTrue(report["success"])
        self.assertTrue(report["rewrite"]["oneCreditReported"])
        self.assertEqual(len(apple.calls), 3)
        self.assertEqual([url.removeprefix(check.BACKEND_ORIGIN) for _, url, _ in backend.calls],
                         ["/api/auth/signin", "/api/generate", "/api/auth/signout"])
        login, generation, logout = [args for _, _, args in backend.calls]
        self.assertEqual(login["json"]["email"], check.EXPECTED_REVIEWER)
        self.assertEqual(login["json"]["password"], PASSWORD)
        self.assertRegex(login["json"]["device_id"], r"^korlix_copybox_[a-f0-9]{48}$")
        self.assertEqual(generation["json"], check.rewrite_body())
        self.assertEqual(logout["json"], {})
        self.assertEqual(generation["headers"]["Authorization"], logout["headers"]["Authorization"])
        self.assertEqual(login["headers"]["X-Korlix-Device-Id"], logout["headers"]["X-Korlix-Device-Id"])
        self.assertNotIn(PASSWORD, json.dumps(generation))
        self.assertNotIn("refresh_token", json.dumps(generation))

    def test_saved_reviewer_mismatch_prevents_all_backend_requests(self):
        report, _, backend = self.run_check(apple=Apple(name="different@example.test"))
        self.assertEqual(report["failureCode"], "reviewer_identity_mismatch")
        self.assertEqual(backend.calls, [])

    def test_app_version_and_review_scope_are_checked_before_credentials_leave(self):
        for changed in ({"bundle": "another.bundle"}, {"version": "other-version"},
                        {"detail": "other-review-detail"}):
            with self.subTest(changed=changed):
                report, _, backend = self.run_check(apple=Apple(**changed))
                self.assertFalse(report["success"])
                self.assertEqual(backend.calls, [])

    def test_rejected_signin_does_not_retry_or_touch_existing_sessions(self):
        report, _, backend = self.run_check(backend=Backend(("/api/auth/signin", "rejected")))
        self.assertEqual(report["signin"]["httpStatusClass"], "4xx")
        self.assertEqual(len(backend.calls), 1)
        self.assertFalse(report["signout"]["attempted"])

    def test_rewrite_transport_or_http_failure_still_logs_out_once(self):
        for failure in ("transport", "rejected"):
            with self.subTest(failure=failure):
                report, _, backend = self.run_check(backend=Backend(("/api/generate", failure)))
                self.assertFalse(report["success"])
                self.assertTrue(report["signout"]["success"])
                self.assertEqual(len(backend.calls), 3)

    def test_short_session_skips_generation_but_cleans_up(self):
        report, _, backend = self.run_check(backend=Backend(short_session=True))
        self.assertEqual(report["failureCode"], "session_too_short_for_bounded_test")
        self.assertFalse(report["rewrite"]["attempted"])
        self.assertTrue(report["signout"]["success"])
        self.assertEqual(len(backend.calls), 2)

    def test_failed_cleanup_is_not_reported_as_complete(self):
        report, _, backend = self.run_check(backend=Backend(("/api/auth/signout", "rejected")))
        self.assertTrue(report["rewrite"]["success"])
        self.assertFalse(report["success"])
        self.assertEqual(report["failureCode"], "session_cleanup_unconfirmed")
        self.assertEqual(len(backend.calls), 3)

    def test_transport_rejects_arbitrary_endpoints_and_repeat_posts(self):
        backend = Backend()
        api = check.BackendOnce(backend)
        with self.assertRaises(check.SmokeStop):
            api.post("https://unrelated.example.test", {}, {})
        api.post("/api/auth/signout", {}, {}, token="offline")
        with self.assertRaises(check.SmokeStop):
            api.post("/api/auth/signout", {}, {}, token="offline")
        self.assertEqual(len(backend.calls), 1)


if __name__ == "__main__":
    unittest.main()
