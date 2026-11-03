"""Capture the production UI in isolated, newly created iOS simulators."""
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import time


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "build/store-captures"
BUNDLE = "com.korlix.brain"
APP = ROOT / "build/ios/iphonesimulator/Runner.app"


def run(*args, env=None):
    return subprocess.check_output(args, text=True, env=env).strip()


def sim(*args):
    return run("xcrun", "simctl", *args)


def dimensions(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError("The simulator did not return a PNG.")
    return struct.unpack(">II", data[16:24])


def capture(device_type, runtime, label, expected):
    udid = sim("create", f"Brain Store Capture {label}", device_type, runtime)
    try:
        sim("boot", udid)
        sim("bootstatus", udid, "-b")
        sim("ui", udid, "appearance", "dark")
        sim("status_bar", udid, "override", "--time", "9:41", "--dataNetwork", "wifi",
            "--wifiMode", "active", "--wifiBars", "3", "--batteryState", "charged",
            "--batteryLevel", "100")
        sim("install", udid, str(APP))
        sim("launch", udid, BUNDLE)
        container = Path(sim("get_app_container", udid, BUNDLE, "data"))
        ready = container / "tmp/brain-store-capture-ready.json"
        deadline = time.monotonic() + 120
        while not ready.exists():
            if time.monotonic() >= deadline:
                raise RuntimeError(f"{label}: the actual workspace did not load its fixture")
            time.sleep(1)
        provenance = json.loads(ready.read_text())
        # The production welcome clip lasts 14.378 seconds. Let it finish.
        time.sleep(22)
        outputs = []
        for number in (1, 2):
            path = OUTPUT / f"{label}-home-{number}.png"
            sim("io", udid, "screenshot", "--type=png", str(path))
            actual = dimensions(path)
            if actual != expected:
                raise RuntimeError(f"{label}: wrong native dimensions {actual}, expected {expected}")
            outputs.append({"file": path.name, "width": actual[0], "height": actual[1],
                            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
            if number == 1:
                time.sleep(3)
        return {"deviceType": device_type, "runtime": runtime, **provenance, "images": outputs}
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", udid], check=False)
        subprocess.run(["xcrun", "simctl", "delete", udid], check=False)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    runtimes = json.loads(sim("list", "runtimes", "-j"))["runtimes"]
    ios = [r for r in runtimes if r.get("isAvailable") and ".iOS-" in r["identifier"]]
    if not ios:
        raise RuntimeError("No available iOS simulator runtime.")
    runtime = max(ios, key=lambda r: tuple(map(int, r["version"].split("."))))["identifier"]
    types = json.loads(sim("list", "devicetypes", "-j"))["devicetypes"]
    devices = [
        ("iPhone 16 Pro", "iphone-16-pro", (1206, 2622)),
        ("iPad Pro 13-inch (M4)", "ipad-pro-13", (2064, 2752)),
    ]
    captures = []
    for name, label, expected in devices:
        matching = [d for d in types if d["name"] == name]
        if len(matching) != 1:
            raise RuntimeError(f"Required simulator unavailable: {name}")
        print(f"Capturing {name}", flush=True)
        captures.append(capture(matching[0]["identifier"], runtime, label, expected))
    metadata = {
        "productionSourceCommit": "f6d98bf5ced9df6d346ec5072df94c85d0a504cd",
        "captureCommit": os.environ.get("GITHUB_SHA", "unknown"),
        "bundleId": BUNDLE, "version": "1.0.1", "build": 14,
        "sourceUiChanged": False,
        "captures": captures,
        "limitations": ["Fictional empty-account data", "No real login or purchase testing",
                        "Visual review is required before upload"],
    }
    (OUTPUT / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print("Native screenshots saved with provenance; inspect before store upload.", flush=True)


if __name__ == "__main__":
    main()
