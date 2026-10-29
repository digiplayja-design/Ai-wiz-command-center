#!/usr/bin/env bash
# Build the independent app in /tmp, using the Codespace's existing upload key.
# No changes are made to the original checkout or signing configuration.
set -euo pipefail
umask 077

original_root=${1:-/workspaces/Ai-wiz-command-center}
source_commit=${2:?Pass the exact source commit to build}
flutter_commit=abaf9c523780a608bd46686fd5e53740a07077f8
bundletool_sha=a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29
original_sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/home/codespace/android-sdk}}
test -f "$original_root/android/key.properties"
test -d "$original_sdk"
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || exit 1
run_root=$(mktemp -d /tmp/korlix-receipt-play-3.XXXXXX)
printf 'Build workspace: %s\n' "$run_root"
printf '%s\n' "$run_root" > /tmp/korlix-receipt-play-latest-path
trap 'printf "Build stopped. Logs and intermediate files remain in %s\n" "$run_root" >&2' ERR

export CI=true FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true
export GRADLE_USER_HOME="$run_root/gradle-cache"
export PUB_CACHE="$run_root/pub-cache"
export ANDROID_USER_HOME="$run_root/android-user"
export XDG_CACHE_HOME="$run_root/cache" XDG_CONFIG_HOME="$run_root/config"
export TMPDIR="$run_root/tmp"
mkdir -p "$GRADLE_USER_HOME" "$PUB_CACHE" "$ANDROID_USER_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$TMPDIR"

git -c gc.auto=0 clone --shared --no-checkout "$original_root" "$run_root/source"
git -C "$run_root/source" remote set-url origin https://github.com/digiplayja-design/Ai-wiz-command-center.git
git -C "$run_root/source" -c gc.auto=0 fetch --depth=1 --no-tags origin "$source_commit"
git -C "$run_root/source" checkout --detach "$source_commit"
test "$(git -C "$run_root/source" rev-parse HEAD)" = "$source_commit"
app_root="$run_root/source/apps/receipt_wiz"
java "$run_root/source/scripts/PrepareAndroidSigning.java" "$original_root" "$app_root"
git -c gc.auto=0 clone --depth=1 --branch 3.47.7 https://github.com/flutter/flutter.git "$run_root/flutter-sdk"
test "$(git -C "$run_root/flutter-sdk" rev-parse HEAD)" = "$flutter_commit"
export PATH="$run_root/flutter-sdk/bin:$PATH"
flutter config --no-analytics
dart --disable-analytics
flutter --version

# Copy the SDK and already-accepted licenses; never accept new licenses here.
mkdir "$run_root/android-sdk"
cp -aL "$original_sdk/." "$run_root/android-sdk/"
export ANDROID_SDK_ROOT="$run_root/android-sdk" ANDROID_HOME="$run_root/android-sdk"
printf 'sdk.dir=%s\n' "$ANDROID_SDK_ROOT" > "$app_root/android/local.properties"

cd "$run_root/source/packages/korlix_receipt_core"
flutter pub get --enforce-lockfile
cd "$app_root"
flutter pub get --enforce-lockfile
flutter build appbundle --release --no-pub --build-name=1.2.0 --build-number=3
bundle="$app_root/build/app/outputs/bundle/release/app-release.aab"
test -s "$bundle"
jarsigner -verify "$bundle" > "$run_root/signature-verification.txt"
grep -q 'jar verified' "$run_root/signature-verification.txt"
curl --fail --location --retry 2 https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar --output "$run_root/bundletool.jar"
printf '%s  %s\n' "$bundletool_sha" "$run_root/bundletool.jar" | sha256sum --check --status
java -jar "$run_root/bundletool.jar" validate --bundle="$bundle" > "$run_root/bundle-validation.txt"
java -jar "$run_root/bundletool.jar" dump manifest --bundle="$bundle" > "$run_root/AndroidManifest.xml"
python3 - "$run_root/AndroidManifest.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
ns = '{http://schemas.android.com/apk/res/android}'
assert root.get('package') == 'com.korlixdeveloper.receiptwiz'
assert root.get(ns+'versionCode') == '3'
assert root.get(ns+'versionName') == '1.2.0'
sdk = root.find('uses-sdk')
assert int(sdk.get(ns+'targetSdkVersion')) >= 36
assert root.find('application').get(ns+'debuggable', 'false') == 'false'
print('Verified Receipt Wiz package, version, API target and release mode.')
PY

output="$original_root/release_uploads/receipt-wiz-3-$(date -u +%Y%m%d-%H%M%S)"
mkdir -p "$output"
cp "$bundle" "$output/KORLIX-Receipt-Wiz-3.aab"
cp "$run_root/AndroidManifest.xml" "$run_root/signature-verification.txt" "$run_root/bundle-validation.txt" "$output/"
printf '%s\n' "$source_commit" > "$output/source-commit.txt"
cd "$output"
sha256sum KORLIX-Receipt-Wiz-3.aab > SHA256SUMS
printf 'Signed release bundle: %s/KORLIX-Receipt-Wiz-3.aab\n' "$output"
cat SHA256SUMS
printf '%s\n' "$output" > /tmp/korlix-receipt-play-output-path
