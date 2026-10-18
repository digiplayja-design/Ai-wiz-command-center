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

# Also validate a direct release build, including an explicit public client
# file. Missing optional configuration preserves the no-FCM build path.
python3 scripts/prepare-android-firebase.py "$PWD" "$PWD"
python3 -m unittest discover -s scripts -p 'test_prepare_android_firebase.py'

# Authentication uses compile-time Flutter settings. Preserve the existing
# public client configuration; never put a Supabase service-role key in an app.
defines_file="$(mktemp)"
trap 'rm -f "$defines_file"' EXIT
chmod 600 "$defines_file"
python3 - "$defines_file" <<'PY'
import base64, json, os, pathlib, sys
from urllib.parse import urlparse

source = os.environ.get('KORLIX_ANDROID_DEFINES_FILE', '')
if source:
    try:
        config = json.loads(pathlib.Path(source).read_text())
    except (OSError, ValueError):
        raise SystemExit('Could not read KORLIX_ANDROID_DEFINES_FILE as a JSON object.')
else:
    config = {key: os.environ[key] for key in (
        'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'AI_WIZARD_BACKEND_URL'
    ) if os.environ.get(key)}
if not isinstance(config, dict):
    raise SystemExit('The Android definitions file must contain a JSON object.')
url = config.get('SUPABASE_URL', '')
key = config.get('SUPABASE_ANON_KEY', '')
if not isinstance(url, str) or not isinstance(key, str) or not url or not key:
    raise SystemExit('Set SUPABASE_URL and SUPABASE_ANON_KEY in this terminal, or set '
                     'KORLIX_ANDROID_DEFINES_FILE to your existing client JSON configuration.')
if urlparse(url).scheme != 'https' or not urlparse(url).netloc:
    raise SystemExit('SUPABASE_URL must be a valid HTTPS project URL.')
if not key.startswith('sb_publishable_'):
    try:
        payload = key.split('.')[1]
        role = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))['role']
    except (IndexError, KeyError, ValueError, TypeError):
        raise SystemExit('SUPABASE_ANON_KEY must be the public anon or publishable key.')
    if role != 'anon':
        raise SystemExit('Only the public anon key may be embedded in Android; never a service-role key.')
pathlib.Path(sys.argv[1]).write_text(json.dumps(config))
PY

flutter pub get
flutter analyze lib/analytics lib/onboarding lib/auth/korlix_signup_presentation.dart lib/auth/korlix_entry_welcome.dart lib/auth/korlix_entry_intro.dart lib/auth/korlix_entry_intro_controller.dart lib/billing/korlix_plan_prompt.dart test/korlix_onboarding_test.dart test/registration_discovery_test.dart test/korlix_entry_intro_test.dart
flutter test test/korlix_onboarding_test.dart test/registration_discovery_test.dart test/korlix_entry_intro_test.dart test/auth_welcome_test.dart test/auth_remember_login_test.dart test/auth_october_integration_test.dart test/signup_eligibility_test.dart test/auth_device_session_test.dart
flutter analyze lib/billing/korlix_apple_billing.dart test/google_play_billing_test.dart
flutter test test/apple_billing_test.dart test/google_play_billing_test.dart test/web_billing_test.dart
flutter analyze lib/navigation/home_tool_catalog.dart test/home_tool_catalog_test.dart test/home_navigation_test.dart
flutter test test/home_tool_catalog_test.dart test/home_navigation_test.dart
flutter test test/fixed_plan_bar_test.dart test/rici_background_audio_test.dart test/k136s_f5_live_convo_integration_test.dart test/korlix_smoke_screensaver_test.dart test/social_communication_upgrade_test.dart
flutter analyze lib/social/social_native_bridge.dart lib/social/social_native_actions.dart lib/social/social_push_native.dart lib/social/social_floating_chat.dart lib/social/social_notification_settings.dart test/social_native_actions_test.dart test/social_native_routing_test.dart test/social_native_settings_test.dart test/social_floating_chat_test.dart test/auth/korlix_token_store_test.dart
flutter test test/social_native_actions_test.dart test/social_native_routing_test.dart test/social_native_settings_test.dart test/social_floating_chat_test.dart test/auth/korlix_token_store_test.dart
flutter build appbundle --release --build-name="${version%%+*}" --build-number="$next" --dart-define-from-file="$defines_file"
echo "Built Android version ${version%%+*} ($next). Upload build/app/outputs/bundle/release/app-release.aab to Internal testing."
