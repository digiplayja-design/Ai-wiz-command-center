"""Actual pinned CLI parser/session contracts; all HTTP transport is mocked.

Run with codemagic-cli-tools==0.69.0 installed. No saved credentials are read.
"""

import contextlib
import importlib.metadata
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

import requests
from codemagic.apple.app_store_connect import AppStoreConnectApiError, AppStoreConnectApiSession
from codemagic.tools.app_store_connect.app_store_connect import AppStoreConnect
from codemagic.tools.app_store_connect.arguments import Types

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_ios_profile as setup
import prepare_ios_release as release
import sync_apple_listing as listing


class CliContractTests(unittest.TestCase):
    def setUp(self):
        self.assertEqual(importlib.metadata.version("codemagic-cli-tools"), setup.CLI_VERSION)
        self.environment = mock.patch.dict(os.environ, {}, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.no_network = mock.patch("socket.socket", side_effect=AssertionError("No network permitted"))
        self.no_network.start()
        self.addCleanup(self.no_network.stop)
        self.parser = AppStoreConnect._setup_cli_options()
        self.commands = []

    def offline_command(self, arguments, **options):
        error = io.StringIO()
        with contextlib.redirect_stderr(error):
            try:
                parsed = self.parser.parse_args(arguments[1:])
            except SystemExit as exit:
                return subprocess.CompletedProcess(arguments, exit.code, b"", error.getvalue().encode())
        self.commands.append((arguments, parsed))
        return subprocess.CompletedProcess(arguments, 0, b"[]", error.getvalue().encode())

    def test_actual_parser_rejects_zero_without_becoming_an_authentication_failure(self):
        for flag in ["--api-unauthorized-retries", "--api-server-error-retries"]:
            runner = setup.ToolRunner("app-store-connect", run=self.offline_command)
            with self.assertRaises(setup.SetupError) as error:
                runner.capture([runner.cli, "apps", "list", flag, "0"], "Fixture lookup", apple=True)
            self.assertIn("local command validation", str(error.exception))
            self.assertNotIn("(401)", str(error.exception))
        self.assertEqual(self.commands, [])

    def test_real_parser_accepts_signing_and_listing_commands_with_one_attempt(self):
        runner = setup.ToolRunner("app-store-connect", run=self.offline_command)
        for arguments in [
            ("apps", "list", "--bundle-id-identifier", setup.BUNDLE_ID, "--strict-match-identifier"),
            ("bundle-ids", "list", "--bundle-id-identifier", setup.BUNDLE_ID, "--strict-match-identifier"),
            ("certificates", "list", "--profile-type", "IOS_APP_STORE"),
            ("bundle-ids", "profiles", "--bundle-ids", "FIXTURE", "--type", "IOS_APP_STORE", "--state", "ACTIVE"),
            ("profiles", "create", "FIXTURE", "--certificate-ids", "FIXTURECERT", "--type", "IOS_APP_STORE", "--name", "Fixture"),
        ]:
            runner.api(*arguments)
        def update_command(arguments, **options):
            result = self.offline_command(arguments, **options)
            if result.returncode:
                return result
            kind = "appStoreVersions" if arguments[1] == "app-store-versions" else "appStoreVersionLocalizations"
            return subprocess.CompletedProcess(arguments, 0, json.dumps({
                "type": kind, "id": "FIXTURE", "attributes": {},
            }).encode(), b"")
        client = listing.AppleClient(lambda: {}, "app-store-connect", run_cli=update_command)
        for kind, after in [("appStoreVersions", {"versionString": "1.0.0"}),
                            ("appStoreVersionLocalizations", {"description": "Fixture description"})]:
            client.update(listing.Operation(kind, "FIXTURE", {}, after))
        for _, parsed in self.commands:
            self.assertEqual(Types.ApiUnauthorizedRetries.resolve_value(parsed.unauthorized_request_retries), 1)
            self.assertEqual(Types.ApiServerErrorRetries.resolve_value(parsed.server_error_retries), 1)
            self.assertTrue(parsed.disable_jwt_cache)
        self.assertEqual(len(self.commands), 7)

    def test_actual_session_with_one_attempt_never_retries_an_http_failure(self):
        for code in [401, 403, 500, 503]:
            with self.subTest(status=code):
                response = requests.Response()
                response.status_code = code
                response._content = json.dumps({"errors": [{"status": str(code), "code": "FIXTURE", "title": "Fixture"}]}).encode()
                response.request = requests.Request("GET", "https://api.appstoreconnect.apple.com/v1/apps").prepare()
                session = AppStoreConnectApiSession(lambda: {}, unauthorized_request_retries=1, server_error_retries=1)
                session._logger = mock.Mock()
                with mock.patch.object(requests.Session, "request", return_value=response) as request, \
                     mock.patch("codemagic.utilities.auditing.save_http_request_audit"):
                    with self.assertRaises(AppStoreConnectApiError) as error:
                        session.get(response.request.url)
                    self.assertEqual(error.exception.status_code, code)
                    request.assert_called_once()

    def test_release_preflight_uses_same_parser_without_changing_plain_build_output(self):
        def capture(runner, arguments, stage, **options):
            result = self.offline_command(arguments)
            self.assertEqual(result.returncode, 0)
            return b"42\n"
        with mock.patch.object(setup.ToolRunner, "capture", capture):
            self.assertEqual(release.app_store("get-latest-build-number", setup.APP_ID, "--platform", "IOS", "--all-versions"), "42\n")
        parsed = self.commands[0][1]
        self.assertEqual(Types.ApiUnauthorizedRetries.resolve_value(parsed.unauthorized_request_retries), 1)
        self.assertEqual(Types.ApiServerErrorRetries.resolve_value(parsed.server_error_retries), 1)


if __name__ == "__main__":
    unittest.main()
