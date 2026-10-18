#!/usr/bin/env bash
set -euo pipefail

runner="${1:?Run through sudo unshare --net and supply the unprivileged runner name.}"
if [[ "$(id -u)" != 0 || "$(id -u "$runner")" == 0 ]]; then
  echo 'An isolated root launcher and an unprivileged test user are required.' >&2
  exit 1
fi
# Fail closed if someone invokes the script without unshare --net.
if [[ "$(readlink /proc/self/ns/net)" == "$(readlink /proc/1/ns/net)" ]]; then
  echo 'Refusing to run Flutter in the host network namespace.' >&2
  exit 1
fi
ip link set lo up
python3 - <<'PY'
import ipaddress
import json
import subprocess

interfaces = json.loads(subprocess.check_output(['ip', '-j', 'address', 'show']))
assert len(interfaces) == 1 and interfaces[0]['ifname'] == 'lo', interfaces
for address in interfaces[0].get('addr_info', []):
    assert ipaddress.ip_address(address['local']).is_loopback, address
for family in ['-4', '-6']:
    routes = json.loads(subprocess.check_output(['ip', family, '-j', 'route', 'show', 'table', 'all']))
    for route in routes:
        assert route.get('dev') == 'lo' and 'gateway' not in route, route
        assert route.get('dst') not in (None, 'default', '0.0.0.0/0', '::/0'), route
        assert ipaddress.ip_network(route['dst'], strict=False).network_address.is_loopback, route
print('Verified loopback-only namespace: no external interfaces or routes.')
PY

runuser -u "$runner" -- env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  -u http_proxy -u https_proxy -u all_proxy \
  PATH="$PATH" PUB_CACHE="$PUB_CACHE" bash <<'CHECKS'
set -uo pipefail
mkdir -p validation-logs
export KORLIX_DISCOVERY_REVIEW="$PWD/validation-logs/screens"
export KORLIX_NAVIGATION_REVIEW="$PWD/validation-logs/home-screens"
export KORLIX_FLUTTER_ROOT="$(dirname "$(dirname "$(command -v flutter)")")"
result=0
check() {
  local label="$1"
  shift
  if ! "$@" 2>&1 | tee "validation-logs/$label.log"; then
    result=1
  fi
}
flutter_cmd=(flutter --suppress-analytics --no-version-check)
# Release builds do not export screenshot-review variables. Exercise that
# path in a separate Flutter process so font loading cannot leak from review.
check discovery-build-mode env -u KORLIX_DISCOVERY_REVIEW -u KORLIX_FLUTTER_ROOT \
  "${flutter_cmd[@]}" test --no-pub --reporter expanded \
  test/registration_discovery_test.dart \
  --plain-name 'review welcome, registration and starter layouts'
check onboarding-analysis "${flutter_cmd[@]}" analyze --no-pub \
  lib/analytics lib/onboarding lib/auth/korlix_signup_presentation.dart lib/auth/korlix_entry_welcome.dart lib/auth/korlix_entry_intro.dart lib/auth/korlix_entry_intro_controller.dart \
  lib/billing/korlix_plan_prompt.dart test/korlix_onboarding_test.dart \
  test/registration_discovery_test.dart test/korlix_entry_intro_test.dart
check onboarding-tests "${flutter_cmd[@]}" test --no-pub --reporter expanded \
  test/korlix_onboarding_test.dart test/registration_discovery_test.dart test/korlix_entry_intro_test.dart \
  test/auth_welcome_test.dart test/auth_remember_login_test.dart \
  test/auth_october_integration_test.dart test/signup_eligibility_test.dart \
  test/auth_device_session_test.dart
check billing-analysis "${flutter_cmd[@]}" analyze --no-pub \
  lib/billing/korlix_apple_billing.dart test/google_play_billing_test.dart
check billing-tests "${flutter_cmd[@]}" test --no-pub --reporter expanded \
  test/apple_billing_test.dart test/google_play_billing_test.dart test/web_billing_test.dart
check home-catalog-analysis "${flutter_cmd[@]}" analyze --no-pub \
  lib/navigation/home_tool_catalog.dart test/home_tool_catalog_test.dart test/home_navigation_test.dart
check home-navigation-tests "${flutter_cmd[@]}" test --no-pub --reporter expanded \
  test/home_tool_catalog_test.dart test/home_navigation_test.dart
check fixed-plan-analysis "${flutter_cmd[@]}" analyze --no-pub   lib/billing/korlix_fixed_plan_bar.dart lib/social/social_call_background.dart test/fixed_plan_bar_test.dart
check voice-and-plan-tests "${flutter_cmd[@]}" test --no-pub --reporter expanded   test/fixed_plan_bar_test.dart test/rici_background_audio_test.dart test/k136s_f5_live_convo_integration_test.dart   test/live_convo/nova_live_voice_workspace_test.dart test/korlix_smoke_screensaver_test.dart   test/social_communication_upgrade_test.dart
# Analyze the touched production voice screen without turning unrelated legacy
# informational lints in this large file into release failures.
check voice-analysis "${flutter_cmd[@]}" analyze --no-pub --no-fatal-infos   lib/live_convo/korlix_live_convo_test_screen.dart lib/live_convo/korlix_live_convo_character_stage.dart

git diff --exit-code -- pubspec.lock || result=1
exit "$result"
CHECKS
