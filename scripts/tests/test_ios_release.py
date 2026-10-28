import importlib.util
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parents[1] / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


prepare = load_script("prepare_ios_release")
verify = load_script("verify_ios_ipa")


class ReleaseIdentityTests(unittest.TestCase):
    def test_exact_app_match_excludes_other_app_and_extension(self):
        apps = [
            {"id": "10", "attributes": {"bundleId": "com.korlixdeveloper.korlixai"}},
            {"id": "11", "attributes": {"bundleId": "com.korlixdeveloper.messenger"}},
            {"id": "12", "attributes": {"bundleId": "com.korlixdeveloper.messenger.extension"}},
        ]
        self.assertEqual(prepare.select_app(apps, "com.korlixdeveloper.messenger"), "11")

    def test_missing_duplicate_and_unexpected_app_ids_fail(self):
        app = {"id": "10", "attributes": {"bundleId": "com.example.app"}}
        for resources, expected in [([], None), ([app, app], None), ([app], "11")]:
            with self.subTest(resources=resources, expected=expected), self.assertRaises(ValueError):
                prepare.select_app(resources, "com.example.app", expected)

    def test_build_number_is_above_apple_and_not_below_source(self):
        self.assertEqual(prepare.next_build_number("133\n", 134, True), 134)
        self.assertEqual(prepare.next_build_number("140", 134, True), 141)
        self.assertEqual(prepare.next_build_number("2", 5), 5)

    def test_only_a_new_app_accepts_successful_empty_build_lookup(self):
        self.assertEqual(prepare.next_build_number("", 5), 5)
        with self.assertRaises(ValueError):
            prepare.next_build_number("", 134, True)

    def test_invalid_or_failed_lookup_never_becomes_build_zero(self):
        for output in ["401 Unauthorized", "null", "1.2", "-1"]:
            with self.subTest(output=output), self.assertRaises(ValueError):
                prepare.next_build_number(output, 5)
        with patch.object(prepare.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "lookup")):
            with self.assertRaises(subprocess.CalledProcessError):
                prepare.run_cli("apps", "list")

    def test_source_version_requires_positive_build(self):
        self.assertEqual(prepare.source_version("version: 12.0.3+134\n"), ("12.0.3", 134))
        for value in ["version: 12.0.3", "version: 1.0.2+0", "version: wrong+5"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                prepare.source_version(value)

    def test_export_must_match_app_version_build_and_device_platform(self):
        info = {"CFBundleIdentifier": "com.example.app", "CFBundleShortVersionString": "1.0.2",
                "CFBundleVersion": "5", "CFBundleSupportedPlatforms": ["iPhoneOS"]}
        verify.verify_info(info, "com.example.app", "1.0.2", "5")
        for key, value in [("CFBundleIdentifier", "com.other.app"), ("CFBundleVersion", "4"),
                           ("CFBundleShortVersionString", "1.0.0"),
                           ("CFBundleSupportedPlatforms", ["iPhoneSimulator"])]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                verify.verify_info({**info, key: value}, "com.example.app", "1.0.2", "5")

    def test_profile_must_be_app_store_for_correct_identity(self):
        profile = {"ApplicationIdentifierPrefix": ["TEAM"],
                   "Entitlements": {"get-task-allow": False, "application-identifier": "TEAM.com.example.app"}}
        verify.verify_profile(profile, "com.example.app")
        invalid = [
            {**profile, "ProvisionedDevices": ["device"]},
            {**profile, "ProvisionsAllDevices": True},
            {**profile, "ApplicationIdentifierPrefix": ["OTHER"]},
            {**profile, "Entitlements": {"get-task-allow": True}},
        ]
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(ValueError):
                verify.verify_profile(value, "com.example.app")

    def test_push_requires_matching_signed_profile_and_runtime_environment(self):
        signed = {"application-identifier": "TEAM.com.example.app", "get-task-allow": False,
                  "aps-environment": "production"}
        profile = {"Entitlements": signed.copy()}
        info = {"KorlixAPNsEnvironment": "production"}
        verify.verify_signed_entitlements(signed, profile, info, True)
        for bad_signed, bad_profile, bad_info in [
            ({**signed, "aps-environment": "development"}, profile, info),
            (signed, {"Entitlements": {**signed, "aps-environment": "development"}}, info),
            (signed, profile, {}),
            ({**signed, "application-identifier": "TEAM.com.other"}, profile, info),
        ]:
            with self.subTest(signed=bad_signed, profile=bad_profile, info=bad_info), self.assertRaises(ValueError):
                verify.verify_signed_entitlements(bad_signed, bad_profile, bad_info, True)


if __name__ == "__main__":
    unittest.main()
