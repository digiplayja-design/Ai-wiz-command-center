#!/usr/bin/env bash
# Produce clearly labeled test artifacts or a separately configured signed candidate.
set -euo pipefail
export FLUTTER_SUPPRESS_ANALYTICS=true

ESHA_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ESHA_REPO_ROOT/apps/esha"
ESHA_BUILD_MODE="${1:-unsigned}"

case "$ESHA_BUILD_MODE" in
  unsigned)
    if [[ -n "${ESHA_ANDROID_STORE_FILE:-}${ESHA_ANDROID_STORE_PASSWORD:-}${ESHA_ANDROID_KEY_ALIAS:-}${ESHA_ANDROID_KEY_PASSWORD:-}" ]]; then
      printf '%s\n' 'Unsigned validation must run without Esha release signing variables.' >&2
      exit 1
    fi
    flutter --suppress-analytics --no-version-check build apk --debug --no-pub
    mkdir -p artifacts/android
    cp build/app/outputs/flutter-apk/app-debug.apk artifacts/android/Esha-debug.apk
    python3 "$ESHA_REPO_ROOT/scripts/esha/verify_artifact.py" android-debug \
      artifacts/android/Esha-debug.apk --output artifacts/android/Esha-debug-verification.json
    flutter --suppress-analytics --no-version-check build appbundle --release --no-pub
    cp build/app/outputs/bundle/release/app-release.aab artifacts/android/Esha-unsigned-release.aab
    python3 "$ESHA_REPO_ROOT/scripts/esha/verify_artifact.py" android-unsigned \
      artifacts/android/Esha-unsigned-release.aab --output artifacts/android/Esha-unsigned-verification.json
    ;;
  signed)
    # A failed rerun must not publish an earlier or unverified signed candidate.
    rm -f artifacts/android/Esha-signed-candidate.aab artifacts/android/Esha-signed-verification.json
    : "${ESHA_ANDROID_STORE_FILE:?Configure the dedicated ESHA_ANDROID_UPLOAD_KEY in Codemagic}"
    : "${ESHA_ANDROID_STORE_PASSWORD:?Esha keystore password is required}"
    : "${ESHA_ANDROID_KEY_ALIAS:?Esha upload key alias is required}"
    : "${ESHA_ANDROID_KEY_PASSWORD:?Esha key password is required}"
    : "${ESHA_ANDROID_UPLOAD_CERT_SHA256:?Configure the approved Esha upload certificate fingerprint}"
    test -f "$ESHA_ANDROID_STORE_FILE"
    test ! -e android/key.properties
    flutter --suppress-analytics --no-version-check build appbundle --release --no-pub
    mkdir -p artifacts/android
    # Verify the original export before exposing it in the publishable path.
    python3 "$ESHA_REPO_ROOT/scripts/esha/verify_artifact.py" android-signed \
      build/app/outputs/bundle/release/app-release.aab --output artifacts/android/Esha-signed-verification.json
    cp build/app/outputs/bundle/release/app-release.aab artifacts/android/Esha-signed-candidate.aab
    ;;
  *)
    printf '%s\n' 'Usage: build_android.sh unsigned|signed' >&2
    exit 2
    ;;
esac
