# Build KORLIX Social floating chat and save the AAB in your browser

**Automated validation passed.** This handoff is pinned to app
commit `b24e339d36d6ec3da8d2033fdafe1059361568a6`. Its validation run is
[39140392738](https://github.com/digiplayja-design/Ai-wiz-command-center/actions/runs/39140392738).
The app regression tests, Android debug builds with and without Firebase, and
unsigned iOS simulator build passed. Complete the signed-device checks below
before store rollout; this does not establish a signed release or publication.

Use the existing **super bassoon** Codespace. The command builds a separate
detached worktree under `/tmp`, preserving your original workspace branch and
local edits. It reuses the saved public Android client configuration at
`$HOME/.config/korlix/android-build134.json` and your existing signing setup.

This update adds Android 11+ **Keep this chat floating** for direct and group
conversations, compact authenticated chat outside the main app, and native
notification/reply support when the required providers are configured. The
existing signup, fixed Upgrade/My Plan button and Rici voice changes remain.

## Optional Firebase client file

If `android/app/google-services.json` already exists in your original Codespace,
the release helper automatically validates and copies it into the isolated build.
No manual copying into the temporary worktree is needed. To use a public client
file stored elsewhere, set `KORLIX_FIREBASE_ANDROID_CONFIG` to its absolute path
in the terminal before pasting the block below. The file must belong to Android
package `com.korlixdeveloper.korlixai`. Invalid files and service-account/private
credentials are rejected without printing their contents.

**Without this optional Firebase client file, you can still test pinning and
using the floating chat. The build cannot receive new background push alerts.**
An expanded bubble can load messages through the existing authenticated chat
API; a collapsed bubble does not continuously poll. Receiving background pushes
also needs the companion backend's native-push migration, provider credentials
and deployment. See [the release guide](SOCIAL_FLOATING_CHAT_RELEASE.md).

## One paste: signed build and browser download

First check the highest version code in **all Google Play tracks and drafts**.
The last locally confirmed build was **136**; verify the current highest Play
code instead of assuming that number. The command asks for it and builds the
next code. If the highest Play code is 136, the resulting file is KORLIX-137.aab.

Paste the entire block into the Codespace **Terminal**:

```bash
env -u BASH_ENV -u ENV bash --noprofile --norc <<'KORLIX_SOCIAL_BUILD_AND_SAVE'
unset -f cd pushd popd 2>/dev/null || true
set -euo pipefail
umask 077
builtin cd /workspaces/Ai-wiz-command-center
export KORLIX_ANDROID_BUILD_PARENT=/tmp
export KORLIX_ANDROID_DEFINES_FILE="$HOME/.config/korlix/android-build134.json"
if [[ ! -r "$KORLIX_ANDROID_DEFINES_FILE" ]]; then
  echo 'The saved Android client configuration is missing.' >&2
  exit 1
fi
KORLIX_RELEASE_REV=b24e339d36d6ec3da8d2033fdafe1059361568a6
read -r -p 'Highest version code in all Play tracks and drafts: ' KORLIX_HIGHEST </dev/tty
if [[ ! "$KORLIX_HIGHEST" =~ ^[1-9][0-9]{0,9}$ ]] || (( 10#$KORLIX_HIGHEST >= 2100000000 )); then
  echo 'Enter the highest version code verified in Play Console.' >&2
  exit 1
fi
git -c gc.auto=0 fetch --no-auto-maintenance --no-tags --no-write-fetch-head \
  https://github.com/digiplayja-design/Ai-wiz-command-center.git "$KORLIX_RELEASE_REV"
KORLIX_BUILD_SCRIPT="$(mktemp /tmp/korlix-social-build.XXXXXX.sh)"
trap 'rm -f "$KORLIX_BUILD_SCRIPT"' EXIT
git show "$KORLIX_RELEASE_REV:scripts/prepare-google-play-billing-build.sh" > "$KORLIX_BUILD_SCRIPT"
bash "$KORLIX_BUILD_SCRIPT" "$KORLIX_HIGHEST" "$KORLIX_RELEASE_REV"
python3 - "$KORLIX_RELEASE_REV" "$KORLIX_HIGHEST" <<'KORLIX_SOCIAL_DOWNLOAD'
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
KORLIX_SOCIAL_DOWNLOAD
KORLIX_SOCIAL_BUILD_AND_SAVE
```

The release script runs the existing checks plus the new Social/native tests,
builds the signed AAB, and starts a server for that completed bundle. A failed
check stops the block before it starts the download server. Keep the terminal
open while the build is running.

## Save from the iPad browser

When the terminal says **Serving KORLIX-…aab**, leave it running:

1. Open the Codespace **Ports** tab. Forward **8790** if it is not already listed.
2. Keep the port visibility **Private**, then choose **Open in Browser**.
3. Tap **Download KORLIX-…aab** and check the build number matches the terminal.
4. Choose **Save to Files → Downloads → Save** on the iPad. If a preview opens,
   use its Share menu and **Save to Files**.
5. Wait for the file to finish saving before pressing **Ctrl+C** in the terminal.

The helper serves only the selected AAB, not your source tree, signing files or
backend credentials. Keep the Codespace running until the download finishes.

## Internal testing before rollout

Upload the saved AAB to **Internal testing** first. Install it on the Samsung
and verify a direct chat and group chat: choose **Keep this chat floating**,
allow notifications/bubbles, switch to another app, expand, reply, collapse and
dismiss. Check that logout/account switching invalidates old bubbles and actions.
Recheck normal Social messages/calls and Rici lock-screen Mute/Stop behavior.

For background-delivery tests, first confirm the Firebase client and companion
backend setup are enabled. Then receive a message with KORLIX backgrounded,
open its alert, and test one explicit notification reply without duplication.
A successful Android AAB does not verify iPhone/iPad push delivery. iOS requires
its separate APNs configuration and signed-device testing; video PiP is not
included in this update.
