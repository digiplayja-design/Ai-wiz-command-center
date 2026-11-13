#!/usr/bin/env python3
"""Run the unchanged native Projection scenario before a signed release.

Only installed simulator runtimes are used. All simulator mutations name a
freshly created device; no global reset, download, signing, or upload occurs.
The default 30-minute budget reserves 18 minutes for Flutter drive and two
minutes for scoped cleanup and the diagnostic ZIP. This is a required gate:
driver failure, incomplete evidence, cleanup failure, and archive failure all
return nonzero. Local unit tests exercise orchestration, not native execution.
"""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time
import uuid
import zipfile
from datetime import datetime, timezone


NATIVE_SECONDS = 18 * 60
FINAL_RESERVE_SECONDS = 120
ARCHIVE_RESERVE_SECONDS = 40
REQUIRED_SCREENSHOTS = tuple(
    "projection-native-" + name + ".png"
    for name in (
        "portrait", "keyboard", "landscape", "paused", "stopped",
        "auto-landscape", "page-error",
    )
)
KNOWN_MIGRATION_END = re.compile(
    r"(?m)^\[[^\r\n]+\][ \t]+Status=3,[ \t]+isTerminal=YES,"
    r"[ \t]+Elapsed=[^\r\n]+\r?\n[ \t]*Data Migration Failed"
    r"[ \t]*(?:\r?\n[ \t]*)*\Z"
)


class GateFailure(Exception):
    def __init__(self, message, exit_code=1):
        super().__init__(message)
        self.exit_code = exit_code


def exit_status(returncode):
    """Preserve a positive driver exit and record signals in shell form."""
    return returncode if returncode > 0 else 128 - returncode


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


class CommandRunner:
    """Bound the process group, using files so inherited pipes cannot hang.

    No environment is printed. Known credential environment values are also
    redacted from captured tool output before it enters the artifact directory.
    """

    def __init__(self):
        sensitive = re.compile(r"TOKEN|SECRET|PASSWORD|PRIVATE_KEY|API_KEY|CREDENTIAL", re.I)
        self.secrets = sorted(
            {value for name, value in os.environ.items()
             if sensitive.search(name) and len(value) >= 8},
            key=len, reverse=True,
        )

    def redact(self, text):
        for value in self.secrets:
            text = text.replace(value, "[REDACTED]")
        return text

    def __call__(self, command, cwd, timeout):
        started = time.monotonic()
        result = {"exitCode": None, "timedOut": False, "stdout": "", "stderr": ""}
        with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
            process = None
            try:
                process = subprocess.Popen(
                    command, cwd=cwd, stdout=stdout, stderr=stderr,
                    start_new_session=True,
                )
                # Termination grace is included in the command's allocated cap.
                grace = min(2.0, timeout / 4)
                try:
                    process.wait(timeout=max(0.01, timeout - 2 * grace))
                except subprocess.TimeoutExpired:
                    result["timedOut"] = True
                    self._signal_group(process, signal.SIGTERM)
                    try:
                        process.wait(timeout=grace)
                    except subprocess.TimeoutExpired:
                        pass
                    # Kill remaining descendants even if the parent accepted TERM.
                    self._signal_group(process, signal.SIGKILL)
                    try:
                        process.wait(timeout=grace)
                    except subprocess.TimeoutExpired:
                        result["error"] = "Command process did not reap after scoped SIGKILL"
                result["exitCode"] = process.poll()
            except OSError as error:
                result["error"] = self.redact(str(error))
            finally:
                for name, stream in (("stdout", stdout), ("stderr", stderr)):
                    stream.seek(0)
                    result[name] = self.redact(stream.read().decode("utf-8", errors="replace"))
                result["elapsedSeconds"] = time.monotonic() - started
        return result

    @staticmethod
    def _signal_group(process, sig):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            pass


def runtime_candidates(inventory, architecture):
    """Use explicit supported types, or an observed available device/type pair."""
    types = {item["identifier"]: item for item in inventory.get("devicetypes", [])
             if item.get("name", "").startswith("iPhone")}
    candidates = []
    for runtime in inventory.get("runtimes", []):
        if (runtime.get("isAvailable") is not True
                or ".iOS-" not in runtime.get("identifier", "")
                or architecture not in runtime.get("supportedArchitectures", [])):
            continue
        supported = runtime.get("supportedDeviceTypes")
        if isinstance(supported, list):
            identifiers = {item.get("identifier") for item in supported}
            compatibility = "runtime.supportedDeviceTypes"
        else:
            identifiers = {item.get("deviceTypeIdentifier")
                           for item in inventory.get("devices", {}).get(runtime["identifier"], [])
                           if item.get("isAvailable") is True}
            compatibility = "available device/runtime pair"
        version = tuple(int(part) for part in re.findall(r"\d+", runtime.get("version", "")))
        if not version:
            continue
        for identifier in identifiers & types.keys():
            candidates.append({
                "runtime": runtime["identifier"], "runtimeVersion": runtime["version"],
                "runtimeBuildVersion": runtime.get("buildversion"),
                "runtimeSupportedArchitectures": runtime["supportedArchitectures"],
                "deviceType": identifier, "model": types[identifier]["name"],
                "compatibilityEvidence": compatibility, "versionParts": version,
            })
    candidates.sort(key=lambda item: (
        item["versionParts"][:2] == (26, 2), item["versionParts"], item["model"],
    ), reverse=True)
    if not candidates:
        raise GateFailure("No installed available iPhone runtime/type pair supports " + architecture)
    primary = candidates[0]
    replacement = next((item for item in candidates if item["runtime"] != primary["runtime"]), primary)
    return [primary, replacement]


class NativeProjectionGate:
    def __init__(self, app_dir, expected_architecture, maximum_minutes=30,
                 runner=None, clock=time.monotonic):
        self.app = Path(app_dir).resolve()
        self.architecture = expected_architecture
        self.runner = runner or CommandRunner()
        self.clock = clock
        self.started = clock()
        self.deadline = self.started + maximum_minutes * 60
        self.setup_deadline = self.deadline - NATIVE_SECONDS - FINAL_RESERVE_SECONDS
        self.output = self.app / "runtime-screenshots"
        self.archive = self.app / "artifacts" / "BrainVoice-native-runtime.zip"
        self.run_id = uuid.uuid4().hex
        self.active_attempt = None
        self.report = {
            "schemaVersion": 1, "runId": self.run_id, "startedAt": utc_now(),
            "appDirectory": str(self.app), "expectedArchitecture": expected_architecture,
            "maximumSeconds": maximum_minutes * 60, "nativeMaximumSeconds": NATIVE_SECONDS,
            "finalReserveSeconds": FINAL_RESERVE_SECONDS, "commands": [], "attempts": [],
            "native": {"started": False, "exitCode": None, "timedOut": False},
            "evidenceVerified": False, "success": False,
        }

    def checkpoint(self):
        write_json(self.output / "native-runtime-gate.json", self.report)

    def command(self, name, arguments, cap=30, deadline=None, required=True):
        deadline = self.setup_deadline if deadline is None else deadline
        timeout = min(cap, deadline - self.clock())
        record = {"name": name, "command": arguments, "timeoutSeconds": max(0, timeout),
                  "stdoutFile": name + ".stdout.log", "stderrFile": name + ".stderr.log"}
        print("Native gate: " + name, flush=True)
        if timeout <= 0:
            result = {"exitCode": None, "timedOut": True, "stdout": "", "stderr": "",
                      "error": "Insufficient time budget before command", "elapsedSeconds": 0}
        else:
            result = self.runner(arguments, self.app, timeout)
        for stream in ("stdout", "stderr"):
            (self.output / record[stream + "File"]).write_text(result.get(stream, ""))
        record.update({key: value for key, value in result.items() if key not in ("stdout", "stderr")})
        self.report["commands"].append(record)
        self.checkpoint()
        print("Native gate status: " + json.dumps(record), flush=True)
        if required and (result.get("timedOut") or result.get("exitCode") != 0):
            code = 124 if result.get("timedOut") else exit_status(result.get("exitCode") or 1)
            raise GateFailure(name + " failed; see captured command output", code)
        return result

    def prepare_output(self):
        if not self.app.is_dir():
            raise GateFailure("App directory does not exist")
        # Retain old data outside the current evidence root; it cannot pass this run.
        self.archive.parent.mkdir(parents=True, exist_ok=True)
        if self.output.exists() or self.output.is_symlink():
            self.output.rename(self.app / ("runtime-screenshots.previous-" + self.run_id))
        self.output.mkdir()
        if self.archive.exists() or self.archive.is_symlink():
            self.archive.rename(self.archive.with_name("BrainVoice-native-runtime.previous-" + self.run_id + ".zip"))
        self.checkpoint()

    def prerequisites(self):
        repository = Path(self.command("git-repository", ["git", "rev-parse", "--show-toplevel"])["stdout"].strip()).resolve()
        relative_app = self.app.relative_to(repository).as_posix()
        head = self.command("git-head", ["git", "rev-parse", "HEAD"])["stdout"].strip()
        tree = self.command("git-app-tree", ["git", "rev-parse", "HEAD:" + relative_app])["stdout"].strip()
        if not all(re.fullmatch(r"[0-9a-f]{40}", item) for item in (head, tree)):
            raise GateFailure("Invalid observed git source identity")
        self.report["source"] = {"head": head, "appTree": tree, "appPath": relative_app}
        architecture = self.command("host-architecture", ["uname", "-m"])["stdout"].strip()
        self.report["host"] = {"architecture": architecture}
        if architecture != self.architecture:
            raise GateFailure("Observed host architecture " + architecture + " differs from " + self.architecture)
        self.report["host"]["os"] = self.command("host-os", ["sw_vers"])["stdout"].strip()
        self.report["host"]["xcode"] = self.command("xcode-version", ["xcodebuild", "-version"])["stdout"].strip()
        self.command("simctl-runtime-help", ["xcrun", "simctl", "help", "runtime"])
        # Apple Xcode 26.4 release notes, issue 170836966, document cache completion.
        # This prerequisite is not a claim about the cause of any migration failure.
        self.command("dyld-shared-cache-update", ["xcrun", "simctl", "runtime", "dyld_shared_cache", "update", "--all"], cap=600)
        self.report["cacheCompleted"] = True
        self.command("simulator-software-keyboard", ["defaults", "write", "com.apple.iphonesimulator", "ConnectHardwareKeyboard", "-bool", "false"])
        inventory = json.loads(self.command("simulator-inventory", ["xcrun", "simctl", "list", "-j"], cap=60)["stdout"])
        write_json(self.output / "simulator-inventory.json", inventory)
        self.command("flutter-pub-get", ["flutter", "pub", "get", "--enforce-lockfile"], cap=180)
        return runtime_candidates(inventory, self.architecture)

    def cleanup(self, attempt, deadline):
        results = []
        for operation in ("shutdown", "delete"):
            result = self.command(
                "simulator-" + operation + "-attempt-" + str(attempt["attempt"]),
                ["xcrun", "simctl", operation, attempt["udid"]],
                cap=30, deadline=deadline, required=False,
            )
            results.append({"operation": operation, "exitCode": result.get("exitCode"),
                            "timedOut": result.get("timedOut", False)})
        attempt["cleanup"] = results
        attempt["cleanupSucceeded"] = all(item["exitCode"] == 0 and not item["timedOut"] for item in results)
        self.active_attempt = None
        self.checkpoint()
        return attempt["cleanupSucceeded"]

    def prepare_device(self, candidates):
        for number, candidate in enumerate(candidates[:2], 1):
            attempt = dict(candidate, attempt=number, nativeExecutionPermitted=False,
                           cleanBootReported=False, migrationReportedFailure=False,
                           creationConfirmed=False)
            self.report["attempts"].append(attempt)
            try:
                udid = self.command("simulator-create-attempt-" + str(number), [
                    "xcrun", "simctl", "create", "Brain Projection " + self.run_id + " " + str(number),
                    candidate["deviceType"], candidate["runtime"],
                ], cap=60)["stdout"].strip()
                uuid.UUID(udid)
                attempt["udid"] = udid
                attempt["creationConfirmed"] = True
                self.active_attempt = attempt
                self.command("simulator-boot-attempt-" + str(number), ["xcrun", "simctl", "boot", udid], cap=60)
                boot = self.command("simulator-bootstatus-attempt-" + str(number), ["xcrun", "simctl", "bootstatus", udid, "-b"], cap=240, required=False)
                attempt["bootstatusExitCode"] = boot.get("exitCode")
                attempt["bootstatusTimedOut"] = boot.get("timedOut", False)
                boot_output = boot.get("stdout", "") + boot.get("stderr", "")
                failure_lines = [line.strip() for line in boot_output.splitlines()
                                 if re.search(r"\b(?:failed|failure)\b", line, re.I)]
                attempt["bootstatusFailureLines"] = failure_lines
                attempt["migrationReportedFailure"] = "Data Migration Failed" in failure_lines
                if boot.get("timedOut") or boot.get("exitCode") != 0:
                    raise GateFailure("Simulator bootstatus timed out or returned nonzero")
                observed = json.loads(self.command("simulator-state-attempt-" + str(number), ["xcrun", "simctl", "list", "devices", "-j"], cap=60)["stdout"])
                state = next((item.get("state") for group in observed.get("devices", {}).values()
                              for item in group if item.get("udid") == udid), None)
                attempt["observedState"] = state
                if state != "Booted":
                    raise GateFailure("Fresh simulator is not independently observed Booted: " + repr(state))
                if failure_lines:
                    if (not KNOWN_MIGRATION_END.search(boot_output)
                            or any(line != "Data Migration Failed" for line in failure_lines)):
                        raise GateFailure("Unknown simulator bootstatus failure text")
                    attempt["startupWarning"] = (
                        "CoreSimulator reported terminal Data Migration Failed with exit 0. "
                        "This exact device is independently observed Booted. Running the "
                        "unchanged native scenario does not declare healthy simulator setup."
                    )
                    print("WARNING: " + attempt["startupWarning"], flush=True)
                attempt["cleanBootReported"] = not failure_lines
                attempt["nativeExecutionPermitted"] = True
                self.checkpoint()
                return udid
            except (GateFailure, ValueError, KeyError, TypeError) as error:
                attempt["error"] = str(error)
                if not attempt["creationConfirmed"]:
                    attempt["replacementBlocked"] = True
                    attempt["cleanupNotAttempted"] = "Creation did not confirm a valid UDID; no unscoped cleanup is permitted"
                    self.checkpoint()
                    raise GateFailure("Ambiguous simulator creation; refusing a replacement") from error
                self.checkpoint()
                if self.active_attempt is not None:
                    if not self.cleanup(attempt, self.setup_deadline):
                        attempt["replacementBlocked"] = True
                        raise GateFailure("Scoped cleanup failed; refusing a replacement simulator") from error
        raise GateFailure("Both bounded fresh-device preparation attempts failed")

    def verify_evidence(self):
        path = self.output / "projection-runtime-evidence.json"
        if path.is_symlink() or not path.is_file():
            raise GateFailure("Native driver evidence report is missing")
        data = json.loads(path.read_text())
        completed = data.get("projectionRuntime", {}).get("outcome", {}).get("scenarioCompleted")
        if completed is not True:
            raise GateFailure("Native scenario did not report scenarioCompleted: true")
        screenshots = []
        for name in REQUIRED_SCREENSHOTS:
            image = self.output / name
            if image.is_symlink() or not image.is_file() or image.stat().st_size == 0:
                raise GateFailure("Required current-run screenshot is missing or empty: " + name)
            content = image.read_bytes()
            if not content.startswith(b"\x89PNG\r\n\x1a\n"):
                raise GateFailure("Required screenshot is not a PNG: " + name)
            screenshots.append({"file": name, "bytes": len(content),
                                "sha256": hashlib.sha256(content).hexdigest()})
        self.report["evidence"] = {"report": path.name, "scenarioCompleted": True,
                                   "reportSha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                                   "screenshots": screenshots}
        self.report["evidenceVerified"] = True

    def exercise(self, udid):
        if self.deadline - self.clock() < NATIVE_SECONDS + FINAL_RESERVE_SECONDS:
            raise GateFailure("Insufficient time for the full native window and cleanup/archive reserve")
        self.report["native"]["started"] = True
        result = self.command("native-runtime", [
            "flutter", "drive", "--verbose", "--no-pub", "--device-id", udid,
            "--driver=test_driver/brain_projection_driver.dart",
            "--target=integration_test/brain_projection_runtime_test.dart",
        ], cap=NATIVE_SECONDS, deadline=self.deadline - FINAL_RESERVE_SECONDS, required=False)
        self.report["native"].update({key: value for key, value in result.items()
                                      if key not in ("stdout", "stderr")})
        if result.get("timedOut"):
            raise GateFailure("Native Flutter drive exceeded its bounded execution window", 124)
        if result.get("exitCode") != 0:
            raise GateFailure("Native Flutter drive failed", exit_status(result.get("exitCode") or 1))
        self.verify_evidence()

    def create_archive(self):
        temporary = self.archive.with_suffix(".zip.partial")
        try:
            with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as archive:
                for path in sorted(self.output.rglob("*")):
                    if path.is_symlink():
                        raise GateFailure("Refusing to archive a symlink in native evidence")
                    if not path.is_file():
                        continue
                    with path.open("rb") as source, archive.open(str(path.relative_to(self.output)), "w") as target:
                        while True:
                            if self.clock() >= self.deadline:
                                raise GateFailure("Native archive exceeded the total helper budget", 124)
                            chunk = source.read(1024 * 1024)
                            if not chunk:
                                break
                            target.write(chunk)
            temporary.replace(self.archive)
        finally:
            if temporary.exists():
                temporary.unlink()
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        print("Native runtime artifact: " + json.dumps({"path": str(self.archive), "sha256": digest}), flush=True)

    def run(self):
        code = 1
        try:
            self.prepare_output()
            udid = self.prepare_device(self.prerequisites())
            self.exercise(udid)
            code = 0
        except (GateFailure, OSError, ValueError, KeyError, TypeError) as error:
            code = error.exit_code if isinstance(error, GateFailure) else 1
            self.report["error"] = str(error)
            print("Native gate failed: " + str(error), flush=True)
        finally:
            if self.active_attempt is not None:
                try:
                    if not self.cleanup(self.active_attempt, self.deadline - ARCHIVE_RESERVE_SECONDS):
                        self.report["cleanupError"] = "Scoped simulator cleanup did not complete"
                        code = code or 1
                except Exception as error:
                    self.report["cleanupError"] = str(error)
                    code = code or 1
            self.report.update({"finishedAt": utc_now(), "elapsedSeconds": self.clock() - self.started,
                                "exitCode": code, "success": code == 0})
            try:
                self.output.mkdir(parents=True, exist_ok=True)
                self.checkpoint()
                self.create_archive()
            except Exception as error:
                code = code or 1
                self.report.update({"archiveError": str(error), "exitCode": code, "success": False})
                try:
                    self.checkpoint()
                except OSError:
                    pass
                print("Native gate archive failed: " + str(error), flush=True)
        return code


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-dir", type=Path, required=True)
    parser.add_argument("--expected-architecture", choices=("arm64", "x86_64"), required=True)
    parser.add_argument("--maximum-minutes", type=float, default=30)
    args = parser.parse_args(argv)
    if not args.app_dir.is_absolute():
        parser.error("--app-dir must be absolute")
    if (not math.isfinite(args.maximum_minutes) or not 20 < args.maximum_minutes <= 30):
        parser.error("--maximum-minutes must be greater than 20 and at most 30")
    return NativeProjectionGate(args.app_dir, args.expected_architecture, args.maximum_minutes).run()


if __name__ == "__main__":
    raise SystemExit(main())
