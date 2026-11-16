import plistlib
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_artifact import BUNDLE_ID, verify_ios


class ArtifactPrivacyTests(unittest.TestCase):
    def artifact(self, purposes, *, rtc=True, signed=False, build="4"):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "Esha.zip"
        root = "Payload/Runner.app/" if signed else "Runner.app/"
        info = {"CFBundleIdentifier": BUNDLE_ID,
                "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": build,
                "CFBundleSupportedPlatforms": ["iPhoneOS" if signed else "iPhoneSimulator"],
                **purposes}
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr(root + "Info.plist", plistlib.dumps(info))
            archive.writestr(root + "Frameworks/Flutter.framework/Flutter", b"fixture")
            if rtc:
                archive.writestr(root + "Frameworks/WebRTC.framework/WebRTC", b"fixture")
        return path

    def test_camera_metadata_is_required_for_the_audio_only_sdk_before_signing(self):
        path = self.artifact({"NSMicrophoneUsageDescription": "Voice conversations."}, signed=True)
        with self.assertRaisesRegex(ValueError, "NSCameraUsageDescription"):
            verify_ios(path, "ios-signed", "1.0.0", "4")

    def test_missing_blank_and_non_string_microphone_metadata_are_rejected(self):
        for value in (None, "", "  ", True):
            with self.subTest(value=value):
                purposes = {"NSCameraUsageDescription": "This version does not use your camera."}
                if value is not None:
                    purposes["NSMicrophoneUsageDescription"] = value
                with self.assertRaisesRegex(ValueError, "NSMicrophoneUsageDescription"):
                    verify_ios(self.artifact(purposes), "ios-simulator")

    def test_blank_and_non_string_camera_metadata_are_rejected(self):
        for value in ("", "  ", True):
            with self.subTest(value=value):
                purposes = {"NSCameraUsageDescription": value,
                            "NSMicrophoneUsageDescription": "Voice conversations."}
                with self.assertRaisesRegex(ValueError, "NSCameraUsageDescription"):
                    verify_ios(self.artifact(purposes), "ios-simulator")

    def test_complete_sdk_metadata_preserves_simulator_identity_checks(self):
        purposes = {"NSCameraUsageDescription": "This version does not use your camera.",
                    "NSMicrophoneUsageDescription": "Voice conversations."}
        result = verify_ios(self.artifact(purposes), "ios-simulator")
        self.assertEqual(result["application_id"], BUNDLE_ID)
        self.assertEqual(result["version_code"], "4")
        self.assertEqual(result["signing"], "simulator-only-not-an-ipa")

    def test_an_artifact_without_the_sdk_does_not_need_unused_privacy_keys(self):
        result = verify_ios(self.artifact({}, rtc=False), "ios-simulator")
        self.assertEqual(result["application_id"], BUNDLE_ID)

    def test_selfie_build_requires_photo_purpose_even_when_plugin_is_static(self):
        for value in (None, "", " ", True):
            with self.subTest(value=value):
                purposes = {} if value is None else {"NSPhotoLibraryUsageDescription": value}
                with self.assertRaisesRegex(ValueError, "NSPhotoLibraryUsageDescription"):
                    verify_ios(self.artifact(purposes, rtc=False, build="5"), "ios-simulator")

    def test_selfie_build_accepts_meaningful_photo_purpose(self):
        result = verify_ios(self.artifact({
            "NSPhotoLibraryUsageDescription": "Choose a selfie to preview colors on your device."
        }, rtc=False, build="5"), "ios-simulator")
        self.assertEqual(result["version_code"], "5")


if __name__ == "__main__":
    unittest.main()
