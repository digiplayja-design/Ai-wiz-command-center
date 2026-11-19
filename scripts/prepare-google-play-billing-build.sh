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
build_parent="${KORLIX_ANDROID_BUILD_PARENT:-$(dirname "$source_root")}"
build_parent="$(python3 - "$build_parent" <<'PY'
import os, pathlib, shutil, sys
parent = pathlib.Path(sys.argv[1]).resolve(strict=True)
if not parent.is_dir() or not os.access(parent, os.W_OK):
    raise SystemExit('The Android build location must be an existing writable directory.')
free = shutil.disk_usage(parent).free
if free < 4 * 1024**3:
    raise SystemExit(f'Only {free / 1024**3:.2f} GiB free at {parent}. '
                     'Set KORLIX_ANDROID_BUILD_PARENT to a disk with build space before retrying.')
print(parent)
PY
)"
# Avoid an automatic Git repack on a nearly full source disk.
git -C "$source_root" -c gc.auto=0 fetch --no-auto-maintenance --no-tags --no-write-fetch-head \
  https://github.com/digiplayja-design/Ai-wiz-command-center.git "$revision"
run_root="$(mktemp -d "$build_parent/korlix-play-billing-${next}.XXXXXX")"
build_root="$run_root/source"
git -C "$source_root" worktree add --detach "$build_root" "$revision"
echo "Build folder: $build_root"

java "$build_root/scripts/PrepareAndroidSigning.java" "$source_root" "$build_root"

if [[ -n "${KORLIX_ANDROID_BUILD_PARENT:-}" ]]; then
  # A separate worktree alone is insufficient when the home disk is also full:
  # Gradle, pub and Flutter's own SDK caches all need writable space.
  flutter_sdk="$(python3 - <<'PY'
import pathlib, shutil
executable = shutil.which('flutter')
if not executable:
    raise SystemExit('Flutter could not be located for the isolated build.')
sdk = pathlib.Path(executable).resolve(strict=True).parent.parent
if not (sdk / 'packages/flutter_tools/pubspec.yaml').is_file() or not (sdk / 'bin/internal/shared.sh').is_file():
    raise SystemExit('Flutter is behind a launcher. Put the existing Flutter SDK bin directory on PATH and retry.')
print(sdk)
PY
)"
  export GRADLE_USER_HOME="$run_root/gradle-cache"
  export PUB_CACHE="$run_root/pub-cache"
  export ANDROID_USER_HOME="$run_root/android-user"
  export XDG_CACHE_HOME="$run_root/xdg-cache"
  export TMPDIR="$run_root/tmp"
  mkdir -p "$GRADLE_USER_HOME" "$PUB_CACHE" "$ANDROID_USER_HOME" "$XDG_CACHE_HOME" "$TMPDIR"
  echo 'Copying the existing Flutter SDK onto the build disk...'
  cp -a "$flutter_sdk/." "$run_root/flutter-sdk/"
  export PATH="$run_root/flutter-sdk/bin:$PATH"
  echo 'Build, Flutter SDK, Gradle and pub caches are on the selected disk.'
fi

cd "$build_root"
bash scripts/build-google-play-billing.sh "$highest"
echo "AAB ready: $build_root/build/app/outputs/bundle/release/app-release.aab"
