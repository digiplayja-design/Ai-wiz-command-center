#!/usr/bin/env bash
set -euo pipefail
umask 077

highest="${1:?Usage: bash resume-google-play-billing-build.sh HIGHEST_PLAY_VERSION_CODE COMMIT_SHA}"
revision="${2:?Supply the full reviewed Android fix commit SHA.}"
if [[ ! "$highest" =~ ^[1-9][0-9]{0,9}$ ]] || (( 10#$highest >= 2100000000 )); then
  echo 'Enter the highest version code verified in Play Console.' >&2
  exit 1
fi
if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'The Android source must be pinned to a full commit SHA.' >&2
  exit 1
fi
for tool in git python3 java; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required build tool is missing: $tool" >&2
    exit 1
  fi
done

source_root="$(git rev-parse --show-toplevel)"
next=$((10#$highest + 1))
build_parent="${KORLIX_ANDROID_BUILD_PARENT:-/tmp}"
# Only resume a detached worktree created by the preparation helper, belonging
# to this repository and retaining its relocated SDK and signing configuration.
build_root="$(python3 - "$source_root" "$build_parent" "$next" <<'PY'
import os, pathlib, subprocess, sys

def git(path, *args):
    return subprocess.check_output(['git', '-C', str(path), *args], text=True, stderr=subprocess.DEVNULL).strip()

source = pathlib.Path(sys.argv[1]).resolve(strict=True)
parent = pathlib.Path(sys.argv[2]).resolve(strict=True)
common = pathlib.Path(git(source, 'rev-parse', '--path-format=absolute', '--git-common-dir')).resolve()
requested = os.environ.get('KORLIX_ANDROID_RESUME_DIR', '')
candidates = [pathlib.Path(requested).resolve(strict=True)] if requested else sorted(parent.glob(f'korlix-play-billing-{sys.argv[3]}.*/source'))
matches = []
for candidate in candidates:
    if candidate.name != 'source' or not candidate.parent.name.startswith(f'korlix-play-billing-{sys.argv[3]}.'):
        continue
    if not (candidate / '.git').is_file():
        continue
    try:
        if pathlib.Path(git(candidate, 'rev-parse', '--path-format=absolute', '--git-common-dir')).resolve() != common:
            continue
        if subprocess.run(['git', '-C', str(candidate), 'symbolic-ref', '-q', 'HEAD'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 1:
            continue
    except subprocess.CalledProcessError:
        continue
    if not (candidate / 'android/key.properties').is_file():
        continue
    if not (candidate / 'scripts/build-google-play-billing.sh').is_file():
        continue
    if not os.access(candidate.parent / 'flutter-sdk/bin/flutter', os.X_OK):
        continue
    if not all((candidate.parent / folder).is_dir() for folder in ('gradle-cache', 'pub-cache', 'android-user', 'xdg-cache', 'tmp')):
        continue
    matches.append(candidate.resolve())
if not matches:
    raise SystemExit('No prepared build with its SDK and caches was found. Keep the original Codespace running and check the previous Build folder path.')
if len(matches) != 1:
    print('More than one prepared build exists. Set KORLIX_ANDROID_RESUME_DIR to the source folder to resume:', file=sys.stderr)
    for candidate in matches:
        print(candidate, file=sys.stderr)
    raise SystemExit(1)
print(matches[0])
PY
)"

if ! git -C "$build_root" diff --quiet || ! git -C "$build_root" diff --cached --quiet; then
  echo "The prepared build has tracked changes; review these before retrying: $build_root" >&2
  git -C "$build_root" status --short --untracked-files=no >&2
  exit 1
fi
if [[ -n "${KORLIX_ANDROID_DEFINES_FILE:-}" ]]; then
  KORLIX_ANDROID_DEFINES_FILE="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve(strict=True))' "$KORLIX_ANDROID_DEFINES_FILE")"
  export KORLIX_ANDROID_DEFINES_FILE
fi

# Fetch only the reviewed commit without triggering maintenance on the full
# original disk. Never reset the original worktree or discard local changes.
git -C "$source_root" -c gc.auto=0 fetch --no-auto-maintenance --no-tags --no-write-fetch-head \
  https://github.com/digiplayja-design/Ai-wiz-command-center.git "$revision"
if ! git -C "$build_root" merge-base --is-ancestor HEAD "$revision"; then
  echo 'The requested commit does not extend this prepared build. Nothing was checked out.' >&2
  exit 1
fi
git -C "$build_root" checkout --detach "$revision"

run_root="$(dirname "$build_root")"
export GRADLE_USER_HOME="$run_root/gradle-cache"
export PUB_CACHE="$run_root/pub-cache"
export ANDROID_USER_HOME="$run_root/android-user"
export XDG_CACHE_HOME="$run_root/xdg-cache"
export TMPDIR="$run_root/tmp"
export PATH="$run_root/flutter-sdk/bin:$PATH"
echo "Reusing build folder, Flutter SDK and dependency caches: $build_root"
cd "$build_root"
bash scripts/build-google-play-billing.sh "$highest"
echo "AAB ready: $build_root/build/app/outputs/bundle/release/app-release.aab"
