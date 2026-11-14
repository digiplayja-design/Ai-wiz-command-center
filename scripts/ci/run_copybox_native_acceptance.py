#!/usr/bin/env python3
"""Run two guest-only native processes on one disposable CI device.

This is an operations/test harness, not a publishing workflow. It adds the
Flutter SDK's integration_test package only to this checkout, rejects changes
to any existing locked package, and never loads signing or account credentials.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


APP_ID = "com.korlixdeveloper.copybox"
ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "apps/korlix_copy_box"
OUT = APP / "artifacts/native-acceptance"
TEST = "integration_test/native_guest_acceptance_test.dart"


def command(args, *, timeout=180, capture=False, output=None, input_text=None, env=None):
    if output is not None:
        with output.open("w", encoding="utf-8") as log:
            result = subprocess.run(args, cwd=APP, text=True, input=input_text,
                                    stdout=log, stderr=subprocess.STDOUT,
                                    timeout=timeout, check=False, env=env)
    else:
        result = subprocess.run(args, cwd=APP, text=True, input=input_text,
                                capture_output=capture, timeout=timeout, check=False, env=env)
    if result.returncode:
        raise RuntimeError("A native acceptance command failed: " + args[0])
    return result.stdout.strip() if capture else None


def locked_packages(text):
    # Lockfile package blocks always have two-space names and four-space fields.
    # Compare source, checksums, paths, descriptions, and versions as written;
    # only dependency classification is irrelevant to adding a dev-only package.
    text = text.split("\nsdks:", 1)[0]
    starts = list(re.finditer(r"(?m)^  ([A-Za-z0-9_]+):\s*$", text))
    packages = {}
    for index, start in enumerate(starts):
        end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
        block = text[start.end():end]
        if not re.search(r"(?m)^    version:", block):
            continue
        packages[start.group(1)] = "\n".join(
            line for line in block.splitlines()
            if not line.startswith("    dependency:")
        ).strip()
    if not packages:
        raise RuntimeError("No locked package records were found")
    return packages


def prepare_test_overlay(report):
    command(["flutter", "--suppress-analytics", "--no-version-check", "pub", "get", "--enforce-lockfile"], timeout=300)
    lock = (APP / "pubspec.lock").read_text()
    (OUT / "release-pubspec.lock").write_text(lock)
    before = locked_packages(lock)
    command(["flutter", "--suppress-analytics", "--no-version-check", "pub", "add", "dev:integration_test:{sdk: flutter}"], timeout=300)
    after_text = (APP / "pubspec.lock").read_text()
    after = locked_packages(after_text)
    changed = [name for name, record in before.items() if after.get(name) != record]
    if changed:
        raise RuntimeError("The test overlay changed an existing locked dependency")
    report["existingLockedPackagesUnchanged"] = True
    report["addedTestPackages"] = sorted(set(after) - set(before))
    (OUT / "test-pubspec.lock").write_text(after_text)
    command(["flutter", "analyze", "--no-pub", TEST], timeout=180)


def boot_ios(report):
    inventory = json.loads(command(["xcrun", "simctl", "list", "--json"], capture=True))
    runtimes = [row for row in inventory["runtimes"]
                if row.get("isAvailable") and row["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
    runtime = max(runtimes, key=lambda row: tuple(int(n) for n in row["version"].split(".")))
    device_type = next(row for row in inventory["devicetypes"] if row["name"] == "iPhone 17")
    device = command(["xcrun", "simctl", "create", "CopyBox native acceptance", device_type["identifier"], runtime["identifier"]], capture=True)
    if not re.fullmatch(r"[A-Fa-f0-9-]{36}", device):
        raise RuntimeError("Unexpected simulator identifier")
    report.update(deviceName=device_type["name"], operatingSystem=runtime["name"])
    command(["xcrun", "simctl", "boot", device])
    command(["xcrun", "simctl", "bootstatus", device, "-b"], timeout=240)
    return device


def android_tool(name):
    existing = shutil.which(name)
    if existing:
        return existing
    sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME") or "/usr/local/share/android-sdk")
    relative = {"emulator": "emulator/emulator", "adb": "platform-tools/adb", "avdmanager": "cmdline-tools/latest/bin/avdmanager"}[name]
    candidate = sdk / relative
    if not candidate.is_file():
        raise RuntimeError("Required Android SDK tool unavailable")
    return str(candidate)


def boot_android(report):
    avd_name = "copybox_native_" + str(os.getpid())
    # Use one explicit location for both tools; their inherited default AVD
    # directories can differ. Keep large device images outside test artifacts.
    avd_home = ROOT / "native-acceptance-device" / "avd"
    avd_home.mkdir(parents=True, exist_ok=True)
    android_env = {**os.environ, "ANDROID_AVD_HOME": str(avd_home)}
    command([android_tool("avdmanager"), "create", "avd", "--name", avd_name,
             "--package", "system-images;android-36;google_apis_playstore;x86_64",
             "--device", "pixel_6a", "--path", str(avd_home / (avd_name + ".avd"))],
            input_text="no\n", env=android_env)
    available = command([android_tool("emulator"), "-list-avds"],
                        capture=True, env=android_env)
    (OUT / "emulator-avd-list.txt").write_text(available + "\n")
    if avd_name not in available.splitlines():
        report["failureStage"] = "ANDROID_AVD_DISCOVERY"
        raise RuntimeError("The emulator cannot discover the newly created AVD")
    report["androidAvdDiscovered"] = True
    # Finish ADB's host-key initialization before the emulator imports that key.
    # Starting both on a fresh runner can race and leave the guest unauthorized.
    command([android_tool("adb"), "start-server"], env=android_env)
    report["adbServerStartedBeforeEmulator"] = True
    emulator_log = (OUT / "emulator.log").open("w", encoding="utf-8")
    process = subprocess.Popen([android_tool("emulator"), "-avd", avd_name,
                                "-port", "5554", "-no-window", "-no-audio",
                                "-no-boot-anim", "-no-snapshot", "-gpu", "swiftshader"],
                               cwd=APP, stdout=emulator_log, stderr=subprocess.STDOUT,
                               env=android_env)
    device = "emulator-5554"
    command([android_tool("adb"), "-s", device, "wait-for-device"], timeout=180)
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        value = command([android_tool("adb"), "-s", device, "shell", "getprop", "sys.boot_completed"], capture=True)
        if value == "1":
            break
        time.sleep(2)
    else:
        raise RuntimeError("Android emulator did not finish booting")
    command([android_tool("adb"), "-s", device, "shell", "input", "keyevent", "KEYCODE_WAKEUP"])
    command([android_tool("adb"), "-s", device, "shell", "wm", "dismiss-keyguard"])
    for setting in ["window_animation_scale", "transition_animation_scale", "animator_duration_scale"]:
        command([android_tool("adb"), "-s", device, "shell", "settings", "put", "global", setting, "0"])
    report.update(deviceName="Pixel 6a", operatingSystem="Android API 36", emulatorProcessId=process.pid)
    return device, process, emulator_log


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", choices=["ios", "android"])
    args = parser.parse_args()
    codemagic_checkout = Path(os.environ.get("CM_BUILD_DIR", "/nonexistent")).resolve()
    github_checkout = (Path(os.environ.get("GITHUB_WORKSPACE", "/nonexistent")) / "release-source").resolve()
    if not (codemagic_checkout == ROOT or
            (os.environ.get("GITHUB_ACTIONS") == "true" and github_checkout == ROOT)):
        raise RuntimeError("Run only in the isolated CI release-source checkout")
    OUT.mkdir(parents=True, exist_ok=True)
    version = re.search(r"(?m)^version:\s*([A-Za-z0-9._-]+)\+(\d+)\s*$", (APP / "pubspec.yaml").read_text())
    if not version:
        raise RuntimeError("Expected the app's declared version and build number")
    report = {
        "schemaVersion": 1, "startedAt": datetime.now(timezone.utc).isoformat(),
        "platform": args.platform, "bundleId": APP_ID,
        "sourceVersion": version.group(1), "sourceBuildNumber": version.group(2),
        "sourceCommit": command(["git", "rev-parse", "HEAD"], capture=True),
        "harnessSha256": hashlib.sha256((APP / TEST).read_bytes()).hexdigest(),
        "success": False, "phases": {}, "guestOnly": True,
        "productionBackend": "NOT_USED_LOCALHOST_OVERRIDE",
        "releaseArtifactTested": False,
        "nativeShareAndFilePickerUiTested": False,
        "physicalDeviceTested": False,
    }
    device = None
    android_process = android_log = None
    try:
        prepare_test_overlay(report)
        if args.platform == "ios":
            device = boot_ios(report)
        else:
            device, android_process, android_log = boot_android(report)
        for phase in ["seed", "restore"]:
            print("Running native guest acceptance phase: " + phase, flush=True)
            command(["flutter", "test", "--no-pub", "--no-uninstall", "--machine", "-d", device,
                     "--dart-define=KORLIX_BACKEND_URL=http://127.0.0.1:1",
                     "--dart-define=COPYBOX_EXPECTED_VERSION=" + version.group(1),
                     "--dart-define=COPYBOX_EXPECTED_BUILD=" + version.group(2),
                     "--dart-define=COPYBOX_ACCEPTANCE_PHASE=" + phase, TEST],
                    timeout=1200, output=OUT / ("report-" + phase + ".json"))
            report["phases"][phase] = "PASSED"
            if phase == "seed":
                if args.platform == "ios":
                    # The first flutter test normally exits its process. Ensure
                    # it is stopped before the second launch; preserve its data.
                    subprocess.run(["xcrun", "simctl", "terminate", device, APP_ID],
                                   cwd=APP, capture_output=True, timeout=30, check=False)
                else:
                    command([android_tool("adb"), "-s", device, "shell", "am", "force-stop", APP_ID])
        report["success"] = True
        report["freshProcessRestoredNativePreferences"] = True
    except Exception as error:
        # Commands and tests contain only fixed synthetic data. Avoid raw
        # environment, subprocess output, or exception text in the summary.
        report["failureClass"] = type(error).__name__
        print("Native acceptance did not complete; inspect the test artifacts.", file=sys.stderr)
    finally:
        try:
            if device and args.platform == "ios":
                subprocess.run(["xcrun", "simctl", "shutdown", device], capture_output=True, timeout=60, check=False)
            if android_process is not None:
                android_process.terminate()
                try:
                    android_process.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    android_process.kill()
                android_log.close()
        except Exception:
            report["deviceCleanupConfirmed"] = False
        report["completedAt"] = datetime.now(timezone.utc).isoformat()
        (OUT / "acceptance-summary.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    sys.exit(main())
