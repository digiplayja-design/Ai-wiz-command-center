#!/usr/bin/env bash
# Run from any directory. No signing material is needed for validation.
set -euo pipefail
export FLUTTER_SUPPRESS_ANALYTICS=true

ESHA_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ESHA_REPO_ROOT/apps/esha"

python3 "$ESHA_REPO_ROOT/scripts/esha/check_source.py"
flutter --suppress-analytics --no-version-check pub get --enforce-lockfile
dart --suppress-analytics format --output=none --set-exit-if-changed lib test
flutter --suppress-analytics --no-version-check analyze --no-pub
flutter --suppress-analytics --no-version-check test --no-pub --reporter expanded
