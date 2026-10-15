#!/usr/bin/env bash
set -euo pipefail

highest="${1:?Usage: bash scripts/build-google-play-billing.sh HIGHEST_PLAY_VERSION_CODE}"
if [[ ! "$highest" =~ ^[1-9][0-9]{0,9}$ ]] || (( 10#$highest >= 2100000000 )); then
  echo 'Enter the highest version code verified in all Play tracks and drafts.' >&2
  exit 1
fi
next=$((10#$highest + 1))
version="$(sed -n 's/^version: *//p' pubspec.yaml)"
if [[ -z "$version" || "$version" != *+* ]]; then
  echo 'pubspec.yaml must contain the app version and build number.' >&2
  exit 1
fi
source_build="${version##*+}"
if (( next <= source_build )); then
  echo 'The supplied Play version code is older than this source; verify the tracks and drafts.' >&2
  exit 1
fi
flutter pub get
flutter analyze lib/billing/korlix_apple_billing.dart test/google_play_billing_test.dart
flutter test test/apple_billing_test.dart test/google_play_billing_test.dart test/web_billing_test.dart
flutter build appbundle --release --build-name="${version%%+*}" --build-number="$next"
echo "Built Android version ${version%%+*} ($next). Upload build/app/outputs/bundle/release/app-release.aab to Internal testing."
