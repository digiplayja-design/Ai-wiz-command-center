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

# Flutter/pub can update these files during a build. Retain those edits only
# when the reviewed update leaves both files alone; never reset or stash them.
backup_root="$(python3 - "$build_root" "$revision" <<'PY'
import os, pathlib, shutil, subprocess, sys, tempfile

root = pathlib.Path(sys.argv[1])
revision = sys.argv[2]

def git(*args):
    return subprocess.check_output(['git', '-C', str(root), *args])

def paths(*args):
    return {os.fsdecode(p) for p in git('diff', '--name-only', '-z', '--no-renames', *args).split(b'\0') if p}

if paths('--cached'):
    raise SystemExit('The prepared build has staged changes. Review them before retrying; nothing was checked out.')
changed = paths()
allowed = {'android/app/build.gradle.kts', 'pubspec.lock'}
if changed - allowed:
    raise SystemExit('The prepared build has other tracked changes; review these before retrying: ' + ', '.join(sorted(changed - allowed)))
overlap = changed & paths('HEAD', revision)
if overlap:
    raise SystemExit('The reviewed update also changes these locally edited files; review them before retrying: ' + ', '.join(sorted(overlap)))
if changed:
    for name in changed:
        file = root / name
        if not file.is_file() or file.is_symlink():
            raise SystemExit('A build file was removed or replaced; review it before retrying: ' + name)
    backup = pathlib.Path(tempfile.mkdtemp(prefix='resume-backup-', dir=root.parent))
    for name in changed:
        target = backup / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / name, target)
        target.chmod(0o600)
    (backup / 'changes.patch').write_bytes(git('diff', '--binary', '--no-ext-diff', '--no-textconv', 'HEAD', '--', *sorted(changed)))
    (backup / 'base-commit.txt').write_bytes(git('rev-parse', 'HEAD'))
    print('Preserving existing build edits: ' + ', '.join(sorted(changed)), file=sys.stderr)
    print('Private backup: ' + str(backup), file=sys.stderr)
    print(backup)
PY
)"
git -C "$build_root" checkout --detach "$revision"
if [[ -n "$backup_root" ]]; then
  for name in android/app/build.gradle.kts pubspec.lock; do
    if [[ -f "$backup_root/$name" ]] && ! cmp -s "$backup_root/$name" "$build_root/$name"; then
      echo "Build stopped: $name differs from its saved copy at $backup_root. Review before continuing." >&2
      exit 1
    fi
  done
fi
python3 "$build_root/scripts/prepare-android-firebase.py" "$source_root" "$build_root"
if [[ -n "${KORLIX_FIREBASE_ANDROID_CONFIG:-}" ]]; then
  export KORLIX_FIREBASE_ANDROID_CONFIG="$build_root/android/app/google-services.json"
fi

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
