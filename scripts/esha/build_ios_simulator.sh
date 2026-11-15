#!/usr/bin/env bash
# This ZIP runs in an iOS Simulator; it is not an IPA or a device installation.
set -euo pipefail
export FLUTTER_SUPPRESS_ANALYTICS=true

ESHA_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ESHA_REPO_ROOT/apps/esha"
flutter --suppress-analytics --no-version-check build ios --simulator --debug --no-codesign --no-pub
mkdir -p artifacts/ios
ditto -c -k --sequesterRsrc --keepParent \
  build/ios/iphonesimulator/Runner.app artifacts/ios/Esha-iOS-Simulator.zip
python3 "$ESHA_REPO_ROOT/scripts/esha/verify_artifact.py" ios-simulator \
  artifacts/ios/Esha-iOS-Simulator.zip --output artifacts/ios/Esha-simulator-verification.json
