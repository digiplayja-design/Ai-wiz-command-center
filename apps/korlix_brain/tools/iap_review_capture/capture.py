"""Native captures of the unchanged billing UI with an approved display catalog."""
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'build/iap-review-captures'
APP = ROOT / 'build/ios/iphonesimulator/Runner.app'
BUNDLE = 'com.korlix.brain'


def run(*args, timeout=240):
    print('Running: ' + ' '.join(args), flush=True)
    return subprocess.check_output(args, text=True, timeout=timeout).strip()


def sim(*args, timeout=240):
    return run('xcrun', 'simctl', *args, timeout=timeout)


def wait_for(path):
    deadline = time.monotonic() + 120
    while not path.exists():
        if time.monotonic() >= deadline:
            raise RuntimeError(f'UI readiness marker was not created: {path.name}')
        time.sleep(0.5)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    runtimes = json.loads(sim('list', 'runtimes', '-j'))['runtimes']
    ios = [r for r in runtimes if r.get('isAvailable') and '.iOS-' in r['identifier']]
    runtime = max(ios, key=lambda r: tuple(map(int, r['version'].split('.'))))['identifier']
    types = json.loads(sim('list', 'devicetypes', '-j'))['devicetypes']
    device_type = next(d['identifier'] for d in types if d['name'] == 'iPhone 16 Pro')
    udid = sim('create', 'Brain IAP Review Capture', device_type, runtime)
    metadata = {
        'productionSourceCommit': 'f6d98bf5ced9df6d346ec5072df94c85d0a504cd',
        'captureCommit': os.environ.get('GITHUB_SHA', 'unknown'),
        'bundleId': BUNDLE, 'version': '1.0.1', 'build': 14,
        'screenSource': 'lib/brain_billing_screen.dart', 'sourceUiChanged': False,
        'deviceType': device_type, 'runtime': runtime,
        'catalogSource': 'Approved USD display fixtures; not live StoreKit responses',
        'productionNetworkUsed': False, 'purchaseTesting': 'not performed',
        'images': [],
    }
    try:
        sim('boot', udid)
        sim('bootstatus', udid, '-b', timeout=600)
        sim('ui', udid, 'appearance', 'dark')
        sim('status_bar', udid, 'override', '--time', '9:41', '--dataNetwork', 'wifi',
            '--wifiMode', 'active', '--wifiBars', '3', '--batteryState', 'charged',
            '--batteryLevel', '100')
        sim('install', udid, str(APP))
        sim('launch', udid, BUNDLE)
        container = Path(sim('get_app_container', udid, BUNDLE, 'data'))
        for stage, filename in [('top', 'brain-monthly-review.png'), ('bottom', 'brain-ai-gas-review.png')]:
            wait_for(container / f'tmp/brain-iap-{stage}-ready.json')
            path = OUTPUT / filename
            sim('io', udid, 'screenshot', '--type=png', str(path), timeout=180)
            data = path.read_bytes()
            if data[:8] != b'\x89PNG\r\n\x1a\n':
                raise RuntimeError('Screenshot is not a PNG')
            width, height = struct.unpack('>II', data[16:24])
            if (width, height) != (1206, 2622):
                raise RuntimeError(f'Unexpected native dimensions: {width}x{height}')
            metadata['images'].append({'file': filename, 'width': width, 'height': height,
                                       'sha256': hashlib.sha256(data).hexdigest()})
            (OUTPUT / 'provenance.json').write_text(json.dumps(metadata, indent=2) + '\n')
            if stage == 'top':
                (container / 'tmp/brain-iap-scroll-next').write_text('scroll\n')
        print('Both native billing UI images captured. Visual review required.', flush=True)
    finally:
        for action, timeout in [('shutdown', 45), ('delete', 30)]:
            try:
                subprocess.run(['xcrun', 'simctl', action, udid], check=False, timeout=timeout)
            except subprocess.TimeoutExpired:
                print(f'Own simulator cleanup timed out during {action}.', flush=True)


if __name__ == '__main__':
    main()
