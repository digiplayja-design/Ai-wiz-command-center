#!/usr/bin/env bash
set -euo pipefail
umask 077

highest="${1:?Usage: bash prepare-google-play-billing-build.sh HIGHEST_PLAY_VERSION_CODE COMMIT_SHA}"
revision="${2:?Supply the full reviewed Android fix commit SHA.}"
if [[ ! "$highest" =~ ^[1-9][0-9]{0,9}$ ]] || (( 10#$highest >= 2100000000 )); then
  echo 'Enter the highest version code verified in Play Console.' >&2
  exit 1
fi
if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'The Android source must be pinned to a full commit SHA.' >&2
  exit 1
fi
for tool in git python3 flutter java; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required build tool is missing: $tool" >&2
    exit 1
  fi
done

source_root="$(git rev-parse --show-toplevel)"
if [[ ! -f "$source_root/android/key.properties" ]]; then
  echo 'Run this from the existing signed Android Codespace with android/key.properties.' >&2
  exit 1
fi
# Resolve an optional relative config path before entering the new worktree.
if [[ -n "${KORLIX_ANDROID_DEFINES_FILE:-}" ]]; then
  KORLIX_ANDROID_DEFINES_FILE="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve(strict=True))' "$KORLIX_ANDROID_DEFINES_FILE")"
  export KORLIX_ANDROID_DEFINES_FILE
fi

next=$((10#$highest + 1))
git -C "$source_root" fetch --no-tags --no-write-fetch-head \
  https://github.com/digiplayja-design/Ai-wiz-command-center.git "$revision"
build_root="$(mktemp -d "$(dirname "$source_root")/korlix-play-billing-${next}.XXXXXX")"
git -C "$source_root" worktree add --detach "$build_root" "$revision"
echo "Build folder: $build_root"

java "$build_root/scripts/PrepareAndroidSigning.java" "$source_root" "$build_root"
cd "$build_root"
bash scripts/build-google-play-billing.sh "$highest"
echo "AAB ready: $build_root/build/app/outputs/bundle/release/app-release.aab"
