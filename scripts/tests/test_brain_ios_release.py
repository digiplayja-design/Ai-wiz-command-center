import copy
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_brain_ios as brain


class BrainSigningTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 10, 31, tzinfo=timezone.utc)
        self.profile = {
            "ApplicationIdentifierPrefix": [brain.TEAM_ID],
            "TeamIdentifier": [brain.TEAM_ID],
            "ExpirationDate": self.now + timedelta(days=30),
            "Entitlements": {
                "get-task-allow": False,
                "application-identifier": f"{brain.TEAM_ID}.{brain.BUNDLE_ID}",
                "com.apple.developer.team-identifier": brain.TEAM_ID,
            },
        }

    def test_accepts_dedicated_store_profile(self):
        brain.validate_profile(self.profile, self.now)

    def test_rejects_other_app_bootstrap_profile(self):
        self.profile["Entitlements"]["application-identifier"] = f"{brain.TEAM_ID}.com.korlixdeveloper.korlixai"
        with self.assertRaises(ValueError):
            brain.validate_profile(self.profile, self.now)

    def test_rejects_wrong_team_debug_adhoc_and_expiring_profiles(self):
        bad_values = [
            {"TeamIdentifier": ["WRONGTEAM"]},
            {"ProvisionedDevices": ["device"]},
            {"ProvisionsAllDevices": True},
            {"ExpirationDate": self.now + timedelta(hours=12)},
            {"ExpirationDate": "2027-01-01"},
        ]
        for changes in bad_values:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                brain.validate_profile({**self.profile, **changes}, self.now)
        for key, value in [("get-task-allow", True), ("com.apple.developer.team-identifier", "WRONGTEAM")]:
            profile = copy.deepcopy(self.profile)
            profile["Entitlements"][key] = value
            with self.subTest(entitlement=key), self.assertRaises(ValueError):
                brain.validate_profile(profile, self.now)

    def test_bundle_filter_never_uses_another_app(self):
        other = {"id": "OTHER", "attributes": {"identifier": "com.korlixdeveloper.korlixai"}}
        own = {"id": "BRAIN", "attributes": {"identifier": brain.BUNDLE_ID}}
        self.assertIsNone(brain.select_bundle([other]))
        self.assertEqual(brain.select_bundle([other, own]), own)
        with self.assertRaises(ValueError):
            brain.select_bundle([own, own])

    def test_candidate_can_be_signed_before_app_record_exists(self):
        latest = Mock()
        self.assertEqual(brain.resolve_release([], "version: 1.0.1+2", False, latest), (None, "1.0.1", 2))
        latest.assert_not_called()

    def test_malformed_apple_response_is_not_reported_as_missing_record(self):
        for response in [None, {}, "", False]:
            with self.subTest(response=response), self.assertRaises(ValueError):
                brain.app_record_id(response)

    def test_testflight_requires_own_app_record(self):
        for apps in [[], [{"id": "6783100102", "attributes": {"bundleId": "com.korlixdeveloper.korlixai"}}]]:
            with self.subTest(apps=apps), self.assertRaises(ValueError):
                brain.resolve_release(apps, "version: 1.0.1+2", True, Mock())

    def test_build_number_increases_for_exact_app(self):
        latest = Mock(return_value="7")
        apps = [{"id": "1234567890", "attributes": {"bundleId": brain.BUNDLE_ID}}]
        self.assertEqual(brain.resolve_release(apps, "version: 1.0.1+2", True, latest), ("1234567890", "1.0.1", 8))
        latest.assert_called_once_with("1234567890")

    def test_apple_lookup_error_does_not_reset_build_number(self):
        apps = [{"id": "1234567890", "attributes": {"bundleId": brain.BUNDLE_ID}}]
        with self.assertRaises(RuntimeError):
            brain.resolve_release(apps, "version: 1.0.1+2", True, Mock(side_effect=RuntimeError("API unavailable")))

    def test_rejected_build_is_not_reused_if_apple_omits_it(self):
        apps = [{"id": "6829319523", "attributes": {"bundleId": brain.BUNDLE_ID}}]
        for latest in ("", "2"):
            with self.subTest(latest=latest):
                self.assertEqual(brain.resolve_release(apps, "version: 1.0.1+3", True,
                                                      Mock(return_value=latest)),
                                 ("6829319523", "1.0.1", 3))


if __name__ == "__main__":
    unittest.main()
