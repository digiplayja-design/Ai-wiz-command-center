#!/usr/bin/env python3
"""Build a network-disabled Android WebView fixture and capture unchanged build14 UI."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import time
import zipfile

SOURCE_COMMIT = "dd1410328822501b3d5a26ae6d0f18a7e5cd2907"
SIGNED_AAB_SHA256 = "1c8f32629b6b1d0f383d04cca36674f05f44e7e6d6d79435d1f22fab4e64ac38"
ASSETS = {
    "web/index.html": "69450daa9f3ab65ac9eb81a83b0d19d785a8a565",
    "web/app.css": "e8b9d248f20c5f4505ac98abcebed227999fa9ae",
    "web/app.js": "82e44c8e026040a543d0b161dc716f53a6f01f93",
    "web/icons.js": "55a5fc72188cd2b4ac53f00a720e21e4a30e6a66",
    "web/lucide.min.js": "93c7e308c058d2758cfb2c7b67898e2ea447d161",
    "web/RAJDHANI-OFL.txt": "74605dfbd41d6e69b46c18cf00ac6c81c13537a1",
    "web/welcome-v1.wav": "6c3ab2df542709591bd77c758ae2e9f683e7c609",
    "branding/brain-icon-1024.png": "bf5780880549144cac940e0fd22552545eae8231",
}
SCENES = [("01-home", "home", [0, 180]), ("02-train-my-ai", "train", [0, 120]),
          ("03-add-memory", "memory", [0, 120]), ("04-my-brain", "brain", [0, 150])]
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / "artifacts/brain-android-capture"
BUILD = ROOT / ".brain-android-capture-build"
SDK = Path(os.environ.get("ANDROID_HOME", os.environ.get("ANDROID_SDK_ROOT", "/usr/local/lib/android/sdk")))
BT = SDK / "build-tools/35.0.0"
ANDROID_JAR = SDK / "platforms/android-34/android.jar"
ADB = SDK / "platform-tools/adb"
SERIAL = "emulator-5554"
PACKAGE = "com.korlix.capture"
DEVICE_FILES = "/sdcard/Android/data/" + PACKAGE + "/files/"
ANDROID_CONFIG = BUILD / "android-user"
AVD_HOME = ANDROID_CONFIG / "avd"
CAPTURE_ENV = dict(os.environ, ANDROID_USER_HOME=str(ANDROID_CONFIG),
                   ANDROID_EMULATOR_HOME=str(ANDROID_CONFIG), ANDROID_AVD_HOME=str(AVD_HOME))


def run(args, *, cwd=ROOT, check=True, timeout=180, data=None):
    input_options = {"input": data} if data is not None else {"stdin": subprocess.DEVNULL}
    return subprocess.run([str(x) for x in args], cwd=cwd, **input_options, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=check, timeout=timeout, env=CAPTURE_ENV)


def adb(*args, **kwargs):
    kwargs.setdefault("timeout", 30)
    return run([ADB, "-s", SERIAL, *args], **kwargs)


def diagnostic_commands(label):
    """Keep command return codes and stderr; an empty file is not a successful read."""
    checks = [("host-processes", ["ps", "-eo", "pid,ppid,pcpu,pmem,rss,stat,etime,args"]),
              ("host-memory", ["free", "-m"]),
              ("host-crash-info", ["coredumpctl", "--no-pager", "info", "--since=-10min"]),
              ("device-echo", [ADB, "-s", SERIAL, "shell", "echo", "device-responsive"]),
              ("device-files", [ADB, "-s", SERIAL, "shell", "ls", "-l", DEVICE_FILES])]
    for name, command in checks:
        try:
            result = run(command, check=False, timeout=10)
            (OUT / f"{label}-{name}.txt").write_bytes(b"returncode=" + str(result.returncode).encode() + b"\n" + result.stdout + b"\nSTDERR\n" + result.stderr)
        except subprocess.TimeoutExpired as exc:
            (OUT / f"{label}-{name}.txt").write_bytes(b"TIMEOUT\n" + (exc.stdout or b"") + (exc.stderr or b""))
        except FileNotFoundError as exc:
            (OUT / f"{label}-{name}.txt").write_text(str(exc))


def retrieve_state(name, timeout=15):
    local = OUT / (name + "-state-poll.json")
    result = adb("pull", DEVICE_FILES + "capture-state.json", local, check=False, timeout=timeout)
    (OUT / (name + "-state-transfer.txt")).write_bytes(b"returncode=" + str(result.returncode).encode() + b"\n" + result.stdout + result.stderr)
    if result.returncode == 0:
        try:
            return json.loads(local.read_bytes())
        except ValueError:
            pass
    return None


def blob_sha(content):
    return hashlib.sha1(b"blob " + str(len(content)).encode() + b"\0" + content).hexdigest()


def build_apk():
    BUILD.mkdir(exist_ok=True)
    staged = BUILD / "assets"
    classes = BUILD / "classes"
    dex = BUILD / "dex"
    for directory in (staged, classes, dex):
        directory.mkdir(exist_ok=True)
    asset_manifest = []
    for relative, expected in ASSETS.items():
        source = ROOT / "apps/korlix_brain/assets" / relative
        content = source.read_bytes()
        actual = blob_sha(content)
        if actual != expected:
            raise RuntimeError(f"Build14 asset mismatch: {relative}: {actual} != {expected}")
        destination = staged / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content)
        asset_manifest.append({"path": relative, "gitBlobSha": actual, "sha256": hashlib.sha256(content).hexdigest(), "bytes": len(content)})
    unsigned = BUILD / "fixture-unsigned.apk"
    run([BT / "aapt", "package", "-f", "-M", HERE / "AndroidManifest.xml", "-A", staged,
         "-I", ANDROID_JAR, "-F", unsigned])
    run(["javac", "--release", "8", "-classpath", ANDROID_JAR, "-d", classes, HERE / "CaptureActivity.java"])
    run([BT / "d8", "--lib", ANDROID_JAR, "--min-api", "28", "--output", dex, *sorted(classes.rglob("*.class"))])
    run([BT / "aapt", "add", unsigned, "classes.dex"], cwd=dex)
    aligned = BUILD / "fixture-aligned.apk"
    run([BT / "zipalign", "-f", "4", unsigned, aligned])
    key = BUILD / "fixture-debug.keystore"
    if not key.exists():
        run(["keytool", "-genkeypair", "-noprompt", "-keystore", key, "-alias", "androiddebugkey",
             "-storepass", "android", "-keypass", "android", "-keyalg", "RSA", "-keysize", "2048",
             "-validity", "30", "-dname", "CN=Offline UI Fixture,O=KORLIX,C=US"])
    apk = BUILD / "brain-ui-fixture.apk"
    run([BT / "apksigner", "sign", "--ks", key, "--ks-pass", "pass:android", "--key-pass", "pass:android", "--out", apk, aligned])
    run([BT / "apksigner", "verify", apk])
    permissions = run([BT / "aapt", "dump", "permissions", apk]).stdout.decode()
    if "uses-permission" in permissions:
        raise RuntimeError("Fixture unexpectedly requests Android permissions")
    with zipfile.ZipFile(apk) as archive:
        for relative, expected in ASSETS.items():
            if blob_sha(archive.read("assets/" + relative)) != expected:
                raise RuntimeError(f"Packaged asset changed: {relative}")
    (OUT / "asset-hashes.json").write_text(json.dumps(asset_manifest, indent=2) + "\n")
    return apk, asset_manifest


def start_emulator():
    AVD_HOME.mkdir(parents=True, exist_ok=True)
    avdmanager = shutil.which("avdmanager") or str(SDK / "cmdline-tools/latest/bin/avdmanager")
    created = run([avdmanager, "create", "avd", "--force", "--name", "korlix_capture", "--path", AVD_HOME / "korlix_capture.avd", "--package",
         "system-images;android-34;google_apis;x86_64", "--device", "pixel_2"], data=b"no\n")
    (OUT / "avdmanager.log").write_bytes(created.stdout + created.stderr)
    emulator_log = (OUT / "emulator.log").open("wb")
    process = subprocess.Popen([str(SDK / "emulator/emulator"), "-avd", "korlix_capture", "-port", "5554",
                               "-no-window", "-no-audio", "-no-snapshot", "-no-boot-anim", "-no-metrics", "-gpu", "swangle", "-feature", "-Vulkan",
                               "-accel", "on", "-memory", "4096", "-cores", str(min(4, os.cpu_count() or 2)), "-skin", "1080x1920"],
                              stdin=subprocess.DEVNULL, stdout=emulator_log, stderr=subprocess.STDOUT, env=CAPTURE_ENV)
    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("Android emulator exited; inspect emulator.log")
        state = adb("shell", "getprop", "sys.boot_completed", check=False, timeout=15)
        if state.returncode == 0 and state.stdout.strip() == b"1":
            break
        time.sleep(2)
    else:
        raise RuntimeError("Android emulator did not finish booting within five minutes")
    adb("shell", "wm", "size", "1080x1920")
    adb("shell", "wm", "density", "400")
    adb("shell", "settings", "put", "system", "font_scale", "1.0")
    for setting in ["window_animation_scale", "transition_animation_scale", "animator_duration_scale"]:
        adb("shell", "settings", "put", "global", setting, "0")
    adb("shell", "input", "keyevent", "82")
    adb("shell", "wm", "dismiss-keyguard", check=False)
    time.sleep(3)
    return process, emulator_log


def capture_scenes(apk):
    adb("shell", "screencap", "-p", "/sdcard/korlix-device-before.png", timeout=20)
    adb("pull", "/sdcard/korlix-device-before.png", OUT / "device-before.png", timeout=20)
    adb("install", "-r", apk, timeout=120)
    adb("shell", "am", "start", "-W", "-n", PACKAGE + "/.CaptureActivity", "--es", "screen", "probe")
    try:
        probe = None
        deadline = time.monotonic() + 50
        while time.monotonic() < deadline:
            probe = retrieve_state("00-rendering-probe")
            if probe is not None:
                break
            time.sleep(1)
        (OUT / "00-rendering-probe.json").write_text(json.dumps(probe, indent=2))
        adb("shell", "screencap", "-p", "/sdcard/korlix-rendering-probe.png", timeout=20)
        adb("pull", "/sdcard/korlix-rendering-probe.png", OUT / "00-rendering-probe.png", timeout=20)
        if not probe or not str(probe.get("error", "")).startswith("Diagnostic rendering check completed"):
            raise RuntimeError("Minimal WebView rendering check did not complete")
    except Exception:
        diagnostic_commands("00-rendering-probe")
        raise
    captures = []
    for label, screen, offsets in SCENES:
        for offset in offsets:
            name = f"{label}-y{offset:03d}"
            print(f"Capturing {name}", flush=True)
            adb("shell", "am", "force-stop", PACKAGE)
            launch = adb("shell", "am", "start", "-W", "-n", PACKAGE + "/.CaptureActivity", "--es", "screen", screen,
                "--ei", "scroll", str(offset))
            (OUT / (name + "-launch.txt")).write_bytes(launch.stdout + launch.stderr)
            deadline = time.monotonic() + 55
            state = None
            while time.monotonic() < deadline:
                try:
                    candidate = retrieve_state(name)
                except subprocess.TimeoutExpired:
                    (OUT / (name + "-transport-error.txt")).write_text("ADB metadata file transfer timed out\n")
                    break
                if candidate is not None:
                    try:
                        if candidate["screen"] == screen and candidate["requestedScrollDp"] == offset:
                            state = candidate
                            break
                    except (ValueError, KeyError):
                        pass
                time.sleep(0.5)
            if state is None or state.get("error"):
                try:
                    adb("shell", "screencap", "-p", "/sdcard/korlix-capture-failure.png", timeout=15)
                    adb("pull", "/sdcard/korlix-capture-failure.png", OUT / (name + "-failure.png"), timeout=15)
                except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
                    (OUT / (name + "-screenshot-error.txt")).write_text("Could not retrieve the diagnostic screenshot\n")
                diagnostic_commands(name)
                for filename, command in [(name + "-progress.json", ("pull", DEVICE_FILES + "capture-progress.json", OUT / (name + "-progress.json")))]:
                    try:
                        diagnostic = adb(*command, check=False, timeout=15)
                        (OUT / (filename + ".transfer.txt")).write_bytes(b"returncode=" + str(diagnostic.returncode).encode() + b"\n" + diagnostic.stdout + diagnostic.stderr)
                    except subprocess.TimeoutExpired:
                        (OUT / (filename + ".timeout.txt")).write_text("ADB diagnostic command timed out\n")
                raise RuntimeError(state.get("error") if state else f"Capture did not become ready: {name}")
            state["page"] = json.loads(state["page"])
            if state["page"]["screen"] != screen or state["page"]["account"] != "Account connected":
                raise RuntimeError(f"Wrong fixture page: {state}")
            device_png = "/sdcard/korlix-" + name + ".png"
            adb("shell", "screencap", "-p", device_png, timeout=20)
            adb("pull", device_png, OUT / (name + ".png"), timeout=20)
            png = (OUT / (name + ".png")).read_bytes()
            if png[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", png[16:24]) != (1080, 1920):
                raise RuntimeError("Native screenshot is not a 1080x1920 PNG")
            (OUT / (name + ".png")).write_bytes(png)
            state.update({"file": name + ".png", "sha256": hashlib.sha256(png).hexdigest(), "width": 1080, "height": 1920})
            (OUT / (name + ".json")).write_text(json.dumps(state, indent=2) + "\n")
            captures.append(state)
    return captures


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    process = None
    emulator_log = None
    logcat_process = None
    logcat_file = None
    try:
        apk, asset_manifest = build_apk()
        process, emulator_log = start_emulator()
        logcat_file = (OUT / "logcat.txt").open("wb")
        logcat_process = subprocess.Popen([str(ADB), "-s", SERIAL, "logcat", "-b", "main", "-b", "system", "-b", "crash", "-v", "time"], stdin=subprocess.DEVNULL, stdout=logcat_file, stderr=subprocess.STDOUT, env=CAPTURE_ENV)
        for capture_attempt in range(2):
            try:
                captures = capture_scenes(apk)
                break
            except RuntimeError:
                # A fresh Google APIs image can restart GMS during module setup.
                # Android then kills WebView clients of its fonts provider. Retry
                # only this observed infrastructure failure, once after restart.
                device_log = (OUT / "logcat.txt").read_text(errors="replace")
                provider_restart = any(
                    "Killing " in line and ":com.korlix.capture/" in line
                    and "depends on provider com.google.android.gms/.fonts.provider.FontsProvider" in line
                    for line in device_log.splitlines()
                )
                if capture_attempt != 0 or not provider_restart:
                    raise
                print("Android restarted its fonts provider and killed the fixture; retrying the capture pass once.", flush=True)
        metadata = {
            "captureType": "native-android-webview-with-local-fixture-data",
            "productionApkRuntime": False,
            "sourceCommit": SOURCE_COMMIT,
            "sourceVersion": "1.0.1+14",
            "sourcePackage": "com.korlix.brain",
            "fixturePackage": PACKAGE,
            "signedAabSha256PreviouslyVerifiedInPlayConsoleDownload": SIGNED_AAB_SHA256,
            "assetVerification": "All eight files match the source git blob hashes. The signed AAB was separately compared before this run.",
            "fixtureData": {"training": "Keep answers clear and practical.\nUse short steps when explaining a task.", "memory": "Our office closes at 4 PM on Fridays."},
            "fixtureLimitations": "Local sample account snapshot; no real sign-in, cloud persistence, voice, purchases, or production APK runtime are tested. Original UI assets and CSS remain unchanged. Existing motion toggle is paused. Add Memory contains an unsaved sample draft.",
            "androidApi": adb("shell", "getprop", "ro.build.version.sdk").stdout.decode().strip(),
            "androidFingerprint": adb("shell", "getprop", "ro.build.fingerprint").stdout.decode().strip(),
            "emulatorGraphicsBackend": "swangle (SwiftShader with ANGLE); guest Vulkan disabled",
            "workflowCommit": os.environ.get("GITHUB_SHA"),
            "workflowRun": os.environ.get("GITHUB_RUN_ID"),
            "assets": asset_manifest,
            "captures": captures,
        }
        (OUT / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n")
        (OUT / "README.txt").write_text(
            "Eight native Android screenshots of unchanged KORLIX Brain+Voice 1.0.1+14 bundled UI.\n"
            "Each core screen has a top and native-scroll variant. Select one per screen.\n"
            "Rendered in Android WebView on API34 x86_64 emulator, 1080x1920, density400.\n"
            "Local sample account data only. These are UI-fixture captures, not signed production APK runtime evidence.\n"
            "No production account, backend, voice session, purchase, or store release was modified.\n"
            "See provenance.json for full asset hashes, sample data, runtime details and limitations.\n")
    except subprocess.CalledProcessError as exc:
        (OUT / "command-error.txt").write_text(exc.stdout.decode(errors="replace") + "\n" + exc.stderr.decode(errors="replace"))
        raise
    finally:
        if logcat_process is not None:
            logcat_process.terminate()
            try:
                logcat_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                logcat_process.kill()
        if logcat_file is not None:
            logcat_file.close()
        if process is not None:
            try:
                adb("emu", "kill", check=False, timeout=15)
            except Exception:
                process.terminate()
        if emulator_log is not None:
            emulator_log.close()


if __name__ == "__main__":
    main()
