"""Local orchestration/failure checks; these do not execute a native app."""

import base64
from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import zipfile


SCRIPT = Path(__file__).resolve().parents[1] / "run_brain_native_projection.py"
SPEC = importlib.util.spec_from_file_location("brain_native_projection", SCRIPT)
gate_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate_module)
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK7sAAAAASUVORK5CYII="
)
MIGRATION_FAILURE = "[2026-11-13 15:00:00 +0000] Status=3, isTerminal=YES, Elapsed=00:01.\n    Data Migration Failed\n\n"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-Air"


def inventory(versions=("26.5", "26.2"), architecture="arm64"):
    runtimes = [{
        "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-" + version.replace(".", "-"),
        "version": version, "isAvailable": True, "buildversion": "fixture",
        "supportedArchitectures": [architecture],
        "supportedDeviceTypes": [{"identifier": DEVICE_TYPE}],
    } for version in versions]
    return {"runtimes": runtimes, "devicetypes": [{"identifier": DEVICE_TYPE, "name": "iPhone Air"}], "devices": {}}


class FakeClock:
    def __init__(self):
        self.value = 0.0

    def __call__(self):
        return self.value


class FakeRunner:
    def __init__(self, app, clock):
        self.app = app
        self.clock = clock
        self.calls = []
        self.created = []
        self.overrides = {}
        self.durations = {}
        self.architecture = "arm64"
        self.inventory = inventory()
        self.boot_output = "[fixture] Status=4294967295, isTerminal=YES\nFinished\n"
        self.state = "Booted"
        self.evidence = "complete"
        self.scenario_completed = True
        self.drive_code = 0
        self.drive_timeout = False

    def __call__(self, command, cwd, timeout):
        command = tuple(command)
        self.calls.append((command, cwd, timeout))
        self.clock.value += self.durations.get(command, 0)
        if command in self.overrides:
            value = self.overrides[command]
            return value() if callable(value) else value
        result = {"stdout": "", "stderr": "", "exitCode": 0, "timedOut": False, "elapsedSeconds": 0}
        if command == ("git", "rev-parse", "--show-toplevel"):
            result["stdout"] = str(self.app.parent.parent) + "\n"
        elif command == ("git", "rev-parse", "HEAD"):
            result["stdout"] = "a" * 40 + "\n"
        elif command[0:2] == ("git", "rev-parse"):
            result["stdout"] = "b" * 40 + "\n"
        elif command == ("uname", "-m"):
            result["stdout"] = self.architecture + "\n"
        elif command == ("sw_vers",):
            result["stdout"] = "ProductVersion: 26.2\nBuildVersion: fixture\n"
        elif command == ("xcodebuild", "-version"):
            result["stdout"] = "Xcode 26.2\nBuild version fixture\n"
        elif command == ("xcrun", "simctl", "list", "-j"):
            result["stdout"] = json.dumps(self.inventory)
        elif command[:3] == ("xcrun", "simctl", "create"):
            udid = "00000000-0000-4000-8000-" + str(len(self.created) + 1).zfill(12)
            self.created.append(udid)
            result["stdout"] = udid + "\n"
        elif command[:3] == ("xcrun", "simctl", "bootstatus"):
            result["stdout"] = self.boot_output
        elif command == ("xcrun", "simctl", "list", "devices", "-j"):
            result["stdout"] = json.dumps({"devices": {"fixture": [
                {"udid": self.created[-1], "state": self.state}
            ]}})
        elif command[:2] == ("flutter", "drive"):
            result.update({"exitCode": self.drive_code, "timedOut": self.drive_timeout})
            if self.evidence != "none":
                output = self.app / "runtime-screenshots"
                (output / "projection-runtime-evidence.json").write_text(json.dumps({
                    "projectionRuntime": {"outcome": {"scenarioCompleted": self.scenario_completed}}
                }))
                for name in gate_module.REQUIRED_SCREENSHOTS:
                    (output / name).write_bytes(PNG)
                if self.evidence == "missing":
                    (output / gate_module.REQUIRED_SCREENSHOTS[-1]).unlink()
                elif self.evidence == "empty":
                    (output / gate_module.REQUIRED_SCREENSHOTS[-1]).write_bytes(b"")
                elif self.evidence == "not-png":
                    (output / gate_module.REQUIRED_SCREENSHOTS[-1]).write_bytes(b"not an image")
        return result


class GateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name) / "apps" / "korlix_brain"
        self.app.mkdir(parents=True)
        self.clock = FakeClock()
        self.runner = FakeRunner(self.app, self.clock)
        self.gate = gate_module.NativeProjectionGate(self.app, "arm64", runner=self.runner, clock=self.clock)

    def run_gate(self):
        self.gate = gate_module.NativeProjectionGate(
            self.app, "arm64", runner=self.gate.runner, clock=self.clock,
        )
        with redirect_stdout(io.StringIO()):
            code = self.gate.run()
        self.assertTrue(self.gate.archive.is_file(), "Failure evidence must also be archived")
        with zipfile.ZipFile(self.gate.archive) as archive:
            self.assertIsNone(archive.testzip())
            self.assertIn("native-runtime-gate.json", archive.namelist())
        return code

    def has_drive(self):
        return any(command[:2] == ("flutter", "drive") for command, _, _ in self.runner.calls)

    def test_success_requires_original_drive_and_seven_current_pngs(self):
        self.assertEqual(self.run_gate(), 0)
        expected = ("flutter", "drive", "--verbose", "--no-pub", "--device-id", self.runner.created[0],
                    "--driver=test_driver/brain_projection_driver.dart",
                    "--target=integration_test/brain_projection_runtime_test.dart")
        commands = [command for command, _, _ in self.runner.calls]
        self.assertIn(expected, commands)
        self.assertIn(("flutter", "pub", "get", "--enforce-lockfile"), commands)
        keyboard = ("defaults", "write", "com.apple.iphonesimulator", "ConnectHardwareKeyboard", "-bool", "false")
        boot = ("xcrun", "simctl", "boot", self.runner.created[0])
        self.assertLess(commands.index(keyboard), commands.index(boot))
        self.assertEqual(self.gate.report["source"]["head"], "a" * 40)
        self.assertEqual(self.gate.report["source"]["appTree"], "b" * 40)
        self.assertTrue(self.gate.report["evidenceVerified"])
        self.assertEqual(len(self.gate.report["evidence"]["screenshots"]), 7)
        self.assertTrue(self.gate.report["attempts"][0]["cleanupSucceeded"])
        self.assertTrue(all(0 < cap <= 1080 for _, _, cap in self.runner.calls))

    def test_wrong_architecture_blocks_all_simulator_mutations(self):
        self.runner.architecture = "x86_64"
        self.assertNotEqual(self.run_gate(), 0)
        self.assertEqual(self.runner.created, [])
        self.assertFalse(self.has_drive())

    def test_cache_nonzero_and_timeout_block_native_and_retain_status(self):
        command = ("xcrun", "simctl", "runtime", "dyld_shared_cache", "update", "--all")
        for code, timed_out, expected in ((17, False, 17), (0, True, 124)):
            with self.subTest(code=code, timeout=timed_out):
                self.runner.overrides[command] = {"exitCode": code, "timedOut": timed_out, "stderr": "fixture failure"}
                self.assertEqual(self.run_gate(), expected)
                self.assertFalse(self.has_drive())
                self.assertEqual(self.runner.created, [])

    def test_known_migration_report_requires_actual_booted_and_retains_warning(self):
        self.runner.boot_output = MIGRATION_FAILURE
        self.assertEqual(self.run_gate(), 0)
        attempt = self.gate.report["attempts"][0]
        self.assertEqual(attempt["observedState"], "Booted")
        self.assertTrue(attempt["migrationReportedFailure"])
        self.assertFalse(attempt["cleanBootReported"])
        self.assertIn("does not declare healthy", attempt["startupWarning"])

    def test_known_report_with_nonbooted_state_never_runs_native(self):
        self.runner.boot_output = MIGRATION_FAILURE
        self.runner.state = "Shutdown"
        self.assertNotEqual(self.run_gate(), 0)
        self.assertFalse(self.has_drive())
        self.assertEqual(len(self.runner.created), 2)

    def test_nonterminal_or_unknown_failure_text_is_rejected(self):
        for text in ("Data Migration Failed\n", MIGRATION_FAILURE + "Unexpected failure\n",
                     MIGRATION_FAILURE.replace("Status=3", "Status=4")):
            with self.subTest(text=text):
                self.runner.boot_output = text
                self.assertNotEqual(self.run_gate(), 0)
                self.assertFalse(self.has_drive())

    def test_bootstatus_nonzero_is_not_accepted_with_known_failure(self):
        original = self.runner.__call__

        def run(command, cwd, timeout):
            result = original(command, cwd, timeout)
            if command[:3] == ["xcrun", "simctl", "bootstatus"]:
                result.update({"exitCode": 9, "stdout": MIGRATION_FAILURE})
            return result

        self.gate.runner = run
        self.assertNotEqual(self.run_gate(), 0)
        self.assertFalse(self.has_drive())
        self.assertEqual(len(self.runner.created), 2)

    def test_state_timeout_and_cleanup_failure_block_replacement(self):
        state = ("xcrun", "simctl", "list", "devices", "-j")
        self.runner.overrides[state] = {"exitCode": -9, "timedOut": True, "stdout": "state query partial"}
        first = "00000000-0000-4000-8000-000000000001"
        self.runner.overrides[("xcrun", "simctl", "shutdown", first)] = {"exitCode": -9, "timedOut": True}
        self.assertNotEqual(self.run_gate(), 0)
        self.assertEqual(len(self.runner.created), 1)
        self.assertTrue(self.gate.report["attempts"][0]["replacementBlocked"])
        self.assertFalse(self.has_drive())
        self.assertIn("Finished", (self.gate.output / "simulator-bootstatus-attempt-1.stdout.log").read_text())
        self.assertEqual((self.gate.output / "simulator-state-attempt-1.stdout.log").read_text(), "state query partial")

    def test_ambiguous_create_never_attempts_replacement_or_unscoped_cleanup(self):
        original = self.runner.__call__
        for create_result in (
            {"exitCode": 0, "timedOut": True, "stdout": ""},
            {"exitCode": 7, "timedOut": False, "stdout": ""},
            {"exitCode": 0, "timedOut": False, "stdout": "not-a-udid"},
        ):
            with self.subTest(result=create_result):
                self.runner.calls.clear()

                def run(command, cwd, timeout):
                    if command[:3] == ["xcrun", "simctl", "create"]:
                        self.runner.calls.append((tuple(command), cwd, timeout))
                        return create_result
                    return original(command, cwd, timeout)

                self.gate.runner = run
                self.assertNotEqual(self.run_gate(), 0)
                self.assertTrue(self.gate.report["attempts"][0]["replacementBlocked"])
                operations = [command[2] for command, _, _ in self.runner.calls if command[:2] == ("xcrun", "simctl")]
                self.assertEqual(operations.count("create"), 1)
                self.assertNotIn("shutdown", operations)
                self.assertNotIn("delete", operations)
                self.assertFalse(self.has_drive())

    def test_failed_attempt_uses_at_most_one_clean_replacement(self):
        calls = 0
        state = ("xcrun", "simctl", "list", "devices", "-j")

        def states():
            nonlocal calls
            calls += 1
            return {"exitCode": 0, "timedOut": False, "stdout": json.dumps({"devices": {"fixture": [
                {"udid": self.runner.created[-1], "state": "Shutdown" if calls == 1 else "Booted"}
            ]}})}

        self.runner.overrides[state] = states
        self.assertEqual(self.run_gate(), 0)
        self.assertEqual(len(self.runner.created), 2)
        attempts = self.gate.report["attempts"]
        self.assertTrue(attempts[0]["cleanupSucceeded"])
        self.assertNotEqual(attempts[0]["runtime"], attempts[1]["runtime"])

    def test_driver_nonzero_survives_complete_evidence_and_cleanup_failure(self):
        self.runner.drive_code = 37
        first = "00000000-0000-4000-8000-000000000001"
        self.runner.overrides[("xcrun", "simctl", "delete", first)] = {"exitCode": 19, "timedOut": False}
        self.assertEqual(self.run_gate(), 37)
        self.assertEqual(self.gate.report["native"]["exitCode"], 37)
        self.assertFalse(self.gate.report["success"])
        self.assertIn("cleanupError", self.gate.report)

    def test_driver_timeout_cannot_pass_even_with_complete_evidence(self):
        self.runner.drive_timeout = True
        self.assertEqual(self.run_gate(), 124)
        self.assertFalse(self.gate.report["evidenceVerified"])

    def test_missing_empty_invalid_or_false_evidence_blocks_success(self):
        for evidence in ("none", "missing", "empty", "not-png"):
            with self.subTest(evidence=evidence):
                self.runner.evidence = evidence
                self.assertNotEqual(self.run_gate(), 0)
        self.runner.evidence = "complete"
        for completed in (False, "true", 1, None):
            with self.subTest(completed=completed):
                self.runner.scenario_completed = completed
                self.assertNotEqual(self.run_gate(), 0)

    def test_stale_report_and_screenshots_cannot_pass_new_run(self):
        self.gate.output.mkdir()
        (self.gate.output / "projection-runtime-evidence.json").write_text(json.dumps({
            "projectionRuntime": {"outcome": {"scenarioCompleted": True}}
        }))
        for name in gate_module.REQUIRED_SCREENSHOTS:
            (self.gate.output / name).write_bytes(PNG)
        self.runner.evidence = "none"
        self.assertNotEqual(self.run_gate(), 0)
        self.assertFalse((self.gate.output / "projection-runtime-evidence.json").exists())

    def test_setup_cannot_consume_native_and_archive_reserve(self):
        command = ("xcrun", "simctl", "list", "devices", "-j")
        self.runner.durations[command] = 601
        self.assertNotEqual(self.run_gate(), 0)
        self.assertFalse(self.has_drive())
        self.assertIn("Insufficient time", self.gate.report["error"])

    def test_final_cleanup_failure_blocks_a_successful_driver(self):
        first = "00000000-0000-4000-8000-000000000001"
        self.runner.overrides[("xcrun", "simctl", "shutdown", first)] = {"exitCode": 1, "timedOut": False}
        self.assertNotEqual(self.run_gate(), 0)
        self.assertEqual(self.gate.report["native"]["exitCode"], 0)
        self.assertTrue(self.gate.report["evidenceVerified"])
        self.assertFalse(self.gate.report["success"])

    def test_archive_error_cannot_mask_driver_failure_or_make_success(self):
        for driver_code in (0, 41):
            with self.subTest(driver_code=driver_code):
                self.runner.drive_code = driver_code
                with patch.object(self.gate, "create_archive", side_effect=OSError("fixture archive failure")):
                    with redirect_stdout(io.StringIO()):
                        code = self.gate.run()
                self.assertEqual(code, driver_code or 1)
                self.assertFalse(self.gate.report["success"])
                self.assertIn("archiveError", self.gate.report)

    def test_commands_only_mutate_created_devices_and_leave_app_sources_unchanged(self):
        source = self.app / "lib" / "main.dart"
        source.parent.mkdir()
        source.write_text("fixture source must not change\n")
        self.assertEqual(self.run_gate(), 0)
        self.assertEqual(source.read_text(), "fixture source must not change\n")
        for command, cwd, _ in self.runner.calls:
            self.assertEqual(cwd, self.app)
            self.assertNotIn("shutdown-all", command)
            self.assertNotIn("download", command)
            self.assertNotIn("erase", command)
            if command[:3] in (("xcrun", "simctl", "boot"), ("xcrun", "simctl", "shutdown"), ("xcrun", "simctl", "delete")):
                self.assertEqual(len(command), 4)
                self.assertIn(command[3], self.runner.created)


class RuntimeSelectionTests(unittest.TestCase):
    def test_prefers_26_2_then_highest_installed_compatible_runtime(self):
        selected = gate_module.runtime_candidates(inventory(), "arm64")
        self.assertEqual(selected[0]["runtimeVersion"], "26.2")
        self.assertEqual(selected[1]["runtimeVersion"], "26.5")
        selected = gate_module.runtime_candidates(inventory(("18.5", "26.4.1")), "arm64")
        self.assertEqual(selected[0]["runtimeVersion"], "26.4.1")

    def test_absent_or_incompatible_runtime_fails_without_download(self):
        for data in (inventory((), "arm64"), inventory(("26.2",), "x86_64")):
            with self.subTest(data=data), self.assertRaises(gate_module.GateFailure):
                gate_module.runtime_candidates(data, "arm64")

    def test_compatibility_requires_explicit_types_or_observed_pair(self):
        data = inventory(("26.2",))
        runtime = data["runtimes"][0]
        del runtime["supportedDeviceTypes"]
        with self.assertRaises(gate_module.GateFailure):
            gate_module.runtime_candidates(data, "arm64")
        data["devices"][runtime["identifier"]] = [{"deviceTypeIdentifier": DEVICE_TYPE, "isAvailable": True}]
        self.assertEqual(gate_module.runtime_candidates(data, "arm64")[0]["compatibilityEvidence"], "available device/runtime pair")


class ProcessRunnerTests(unittest.TestCase):
    def test_preserves_real_exit_and_redacts_credentials_from_output(self):
        with patch.dict(os.environ, {"NATIVE_TEST_SECRET": "fixture-credential-do-not-archive"}):
            runner = gate_module.CommandRunner()
            result = runner([sys.executable, "-c", "import os,sys; print(os.environ['NATIVE_TEST_SECRET']); sys.exit(23)"], Path.cwd(), 5)
        self.assertEqual(result["exitCode"], 23)
        self.assertFalse(result["timedOut"])
        self.assertIn("[REDACTED]", result["stdout"])
        self.assertNotIn("fixture-credential", result["stdout"])

    @unittest.skipUnless(os.name == "posix", "Process groups require POSIX")
    def test_timeout_kills_command_group_without_waiting_on_inherited_output(self):
        runner = gate_module.CommandRunner()
        started = time.monotonic()
        result = runner([sys.executable, "-c",
                         "import subprocess,sys,time; subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); print('started',flush=True); time.sleep(30)"],
                        Path.cwd(), 1)
        self.assertTrue(result["timedOut"])
        self.assertLess(time.monotonic() - started, 3)
        self.assertIn("started", result["stdout"])
        self.assertIsNotNone(result["exitCode"])


if __name__ == "__main__":
    unittest.main()
