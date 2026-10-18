"""Release-build Firebase client validation and isolated-copy checks."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


HELPER = Path(__file__).with_name("prepare-android-firebase.py")
SPEC = importlib.util.spec_from_file_location("prepare_android_firebase", HELPER)
firebase = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(firebase)


def client_config(package=firebase.PACKAGE):
    return {
        "project_info": {"project_id": "korlix-client-fixture", "project_number": "123456789012"},
        "client": [{
            "client_info": {
                "mobilesdk_app_id": "1:123456789012:android:0123456789abcdef",
                "android_client_info": {"package_name": package},
            },
            "api_key": [{"current_key": "AIza" + "0" * 35}],
            "oauth_client": [],
        }],
        "configuration_version": "1",
    }


class FirebaseClientPreparationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source, self.build = self.root / "source", self.root / "build"
        for root in (self.source, self.build):
            (root / "android/app").mkdir(parents=True)
        self.original = self.source / firebase.CLIENT_PATH
        self.target = self.build / firebase.CLIENT_PATH

    def write(self, path, value):
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_public_client_auto_copies_without_altering_original(self):
        self.write(self.original, client_config())
        before = self.original.read_bytes()
        self.assertTrue(firebase.prepare(self.source, self.build))
        self.assertEqual(self.target.read_bytes(), before)
        self.assertEqual(self.original.read_bytes(), before)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertTrue(firebase.prepare(self.build, self.build))

    def test_missing_optional_file_leaves_fcm_disabled(self):
        self.assertFalse(firebase.prepare(self.source, self.build))
        self.assertFalse(self.target.exists())

    def test_resume_preserves_validated_file_when_original_is_absent(self):
        self.write(self.target, client_config())
        before = self.target.read_bytes()
        self.assertTrue(firebase.prepare(self.source, self.build))
        self.assertEqual(self.target.read_bytes(), before)

    def test_explicit_path_overrides_default_and_missing_path_fails(self):
        self.write(self.original, client_config("different.app"))
        explicit = self.write(self.root / "selected-client.json", client_config())
        self.assertTrue(firebase.prepare(self.source, self.build, str(explicit)))
        before = self.target.read_bytes()
        with self.assertRaisesRegex(firebase.ConfigError, "KORLIX_FIREBASE_ANDROID_CONFIG"):
            firebase.prepare(self.source, self.build, str(self.root / "missing.json"))
        self.assertEqual(self.target.read_bytes(), before)

    def test_wrong_android_package_never_copies(self):
        self.write(self.original, client_config("com.example.other"))
        with self.assertRaisesRegex(firebase.ConfigError, firebase.PACKAGE):
            firebase.prepare(self.source, self.build)
        self.assertFalse(self.target.exists())

    def test_service_account_and_nested_private_key_are_rejected(self):
        bad = client_config()
        bad["provider"] = {"private_key": "DO-NOT-PRINT-ME"}
        for value in ({"type": "service_account", "private_key": "DO-NOT-PRINT-ME"}, bad):
            with self.subTest(value_type=list(value)):
                self.write(self.original, value)
                with self.assertRaisesRegex(firebase.ConfigError, "private credential"):
                    firebase.prepare(self.source, self.build)
                self.assertFalse(self.target.exists())
        completed = subprocess.run(
            [sys.executable, str(HELPER), str(self.source), str(self.build)],
            capture_output=True, text=True,
            env={key: value for key, value in os.environ.items() if key != "KORLIX_FIREBASE_ANDROID_CONFIG"},
            check=False,
        )
        self.assertEqual(completed.returncode, 1)
        self.assertNotIn("DO-NOT-PRINT-ME", completed.stdout + completed.stderr)
        self.assertNotIn("Traceback", completed.stderr)

    def test_private_pem_or_incomplete_client_cannot_replace_existing_file(self):
        self.write(self.target, client_config())
        before = self.target.read_bytes()
        for value in (client_config(), {"project_info": {}, "client": []}):
            if value["project_info"]:
                value["note"] = "-----BEGIN PRIVATE KEY-----\nDO-NOT-PRINT-ME"
            self.write(self.original, value)
            with self.assertRaises(firebase.ConfigError):
                firebase.prepare(self.source, self.build)
            self.assertEqual(self.target.read_bytes(), before)

    def test_target_symlink_is_not_overwritten(self):
        self.write(self.original, client_config())
        outside = self.root / "keep.txt"
        outside.write_text("unchanged", encoding="utf-8")
        self.target.symlink_to(outside)
        with self.assertRaisesRegex(firebase.ConfigError, "symbolic link"):
            firebase.prepare(self.source, self.build)
        self.assertEqual(outside.read_text(encoding="utf-8"), "unchanged")


if __name__ == "__main__":
    unittest.main()
