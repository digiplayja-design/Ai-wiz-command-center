# Build the fixed Upgrade button and Rici background voice

Use the existing **super bassoon** Codespace. This builds the reviewed source
without switching or resetting the dirty workspace branch. It reuses the
saved public client configuration and existing Android signing setup.

First check the highest version code in **all Google Play tracks and drafts**.
The command asks for that number and builds the next one. Build 134 was created
previously; its store upload has not been verified in this session.

Paste the entire block into the Codespace **Terminal**:

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc <<'KORLIX_BUILD_AND_SAVE'
unset -f cd pushd popd 2>/dev/null || true
set -euo pipefail
builtin cd /workspaces/Ai-wiz-command-center
export KORLIX_ANDROID_BUILD_PARENT=/tmp
export KORLIX_ANDROID_DEFINES_FILE="$HOME/.config/korlix/android-build134.json"
if [[ ! -r "$KORLIX_ANDROID_DEFINES_FILE" ]]; then
  echo 'The saved Android client configuration is missing.' >&2
  exit 1
fi
KORLIX_RELEASE_REV=fc083e3e0cb0157406a578d52d2338ebb2f9f9cb
read -r -p 'Highest version code in all Play tracks and drafts: ' KORLIX_HIGHEST </dev/tty
git -c gc.auto=0 fetch --no-auto-maintenance --no-tags \
  https://github.com/digiplayja-design/Ai-wiz-command-center.git "$KORLIX_RELEASE_REV"
KORLIX_BUILD_SCRIPT="$(mktemp /tmp/korlix-rici-build.XXXXXX.sh)"
trap 'rm -f "$KORLIX_BUILD_SCRIPT"' EXIT
git show "$KORLIX_RELEASE_REV:scripts/prepare-google-play-billing-build.sh" > "$KORLIX_BUILD_SCRIPT"
bash "$KORLIX_BUILD_SCRIPT" "$KORLIX_HIGHEST" "$KORLIX_RELEASE_REV"
python3 - "$KORLIX_RELEASE_REV" "$KORLIX_HIGHEST" <<'KORLIX_DOWNLOAD'
from pathlib import Path
import subprocess
import sys

revision, highest = sys.argv[1:]
build = int(highest) + 1
matches = []
for source in Path('/tmp').glob(f'korlix-play-billing-{build}.*/source'):
    bundle = source / 'build/app/outputs/bundle/release/app-release.aab'
    head = subprocess.run(['git', '-C', str(source), 'rev-parse', 'HEAD'],
                          capture_output=True, text=True)
    if head.returncode == 0 and head.stdout.strip() == revision and bundle.is_file():
        matches.append((bundle.stat().st_mtime_ns, source, bundle))
if not matches:
    raise SystemExit('No completed AAB for this exact source was found. Keep the build output.')
_, source, bundle = max(matches, key=lambda item: item[0])
subprocess.run([sys.executable, str(source / 'scripts/download-android-aab.py'),
                str(bundle), '--build-number', str(build), '--port', '8790'], check=True)
KORLIX_DOWNLOAD
KORLIX_BUILD_AND_SAVE
```

When it says **Serving KORLIX-…aab**, keep that terminal running:

1. Open the Codespace **Ports** tab and forward **8790**.
2. Leave visibility **Private**, then select **Open in Browser**.
3. Tap **Download KORLIX-…aab**.
4. On iPad, choose **Save to Files → Downloads → Save**. If a preview opens,
   use its Share menu and **Save to Files**.
5. After saving completes, stop the server with **Ctrl+C**.

Upload the saved AAB to **Internal testing** first. Test Upgrade/My Plan and an
active Rici conversation with the device locked, including Mute and lock-screen
Stop. The microphone remains active when unmuted. Browser lock-screen playback
and iOS device behavior have not been established by the Android build.
