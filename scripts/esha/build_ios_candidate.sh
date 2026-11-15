#!/usr/bin/env bash
# The signing preflight must have written ESHA_IOS_* to CM_ENV first.
set -euo pipefail
export FLUTTER_SUPPRESS_ANALYTICS=true

ESHA_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ESHA_REPO_ROOT/apps/esha"
# A failed rerun must not leave a prior IPA available to artifact publishing.
rm -f artifacts/ios/Esha-signed-candidate.ipa artifacts/ios/Esha-signed-verification.json
: "${ESHA_IOS_VERSION:?Run prepare_ios_release.py first}"
: "${ESHA_IOS_BUILD_NUMBER:?Run prepare_ios_release.py first}"
: "${ESHA_APPLE_TEAM_ID:?Configure the Apple Developer team ID for Esha}"
: "${ESHA_APP_STORE_PROFILE_PATH:?Configure the dedicated ESHA_APP_STORE_PROFILE}"
test -f "$ESHA_APP_STORE_PROFILE_PATH"
flutter --suppress-analytics --no-version-check build ios --release --config-only --no-codesign --no-pub \
  --build-name="$ESHA_IOS_VERSION" --build-number="$ESHA_IOS_BUILD_NUMBER"
xcode-project use-profiles --project ios/Runner.xcodeproj \
  --export-options-plist "$ESHA_REPO_ROOT/esha-ios-export.plist" \
  --custom-export-options '{"manageAppVersionAndBuildNumber": false}'
flutter --suppress-analytics --no-version-check build ipa --release --no-pub \
  --build-name="$ESHA_IOS_VERSION" --build-number="$ESHA_IOS_BUILD_NUMBER" \
  --export-options-plist="$ESHA_REPO_ROOT/esha-ios-export.plist"
ESHA_IPA_FILES=(build/ios/ipa/*.ipa)
test "${#ESHA_IPA_FILES[@]}" -eq 1
test -s "${ESHA_IPA_FILES[0]}"
mkdir -p artifacts/ios
python3 "$ESHA_REPO_ROOT/scripts/esha/verify_artifact.py" ios-signed \
  "${ESHA_IPA_FILES[0]}" --version "$ESHA_IOS_VERSION" \
  --build "$ESHA_IOS_BUILD_NUMBER" --output artifacts/ios/Esha-signed-verification.json
# Expose only a verified IPA at the path collected by Codemagic for publishing.
cp "${ESHA_IPA_FILES[0]}" artifacts/ios/Esha-signed-candidate.ipa
