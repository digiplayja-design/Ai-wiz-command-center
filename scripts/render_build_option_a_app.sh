#!/usr/bin/env bash
set -euo pipefail

# Keep build diagnostics local; deployment does not need analytics reporting.
export DASH__SUPPRESS_ANALYTICS=true
export FLUTTER_SUPPRESS_ANALYTICS=true
export DART_SUPPRESS_ANALYTICS=true

echo "============================================================"
echo "KORLIX Render Option A Build"
echo "Publishing existing website at /"
echo "Publishing Flutter app at /app/"
echo "============================================================"

APP_BASE_HREF="${KORLIX_WEB_BASE_HREF:-/app/}"
FLUTTER_CHANNEL="${KORLIX_FLUTTER_CHANNEL:-stable}"
FLUTTER_DIR="${KORLIX_FLUTTER_DIR:-$HOME/flutter}"

echo "Base href: $APP_BASE_HREF"
echo "Flutter channel: $FLUTTER_CHANNEL"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found. Installing Flutter SDK into $FLUTTER_DIR..."

  if [ ! -d "$FLUTTER_DIR/.git" ]; then
    if [ -e "$FLUTTER_DIR" ]; then
      echo "Flutter SDK path already exists and is not a Git checkout: $FLUTTER_DIR" >&2
      echo "Choose an unused KORLIX_FLUTTER_DIR or provide Flutter on PATH." >&2
      exit 1
    fi
    git clone --depth 1 --branch "$FLUTTER_CHANNEL" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  fi

  export PATH="$FLUTTER_DIR/bin:$PATH"
else
  echo "Flutter already available."
fi

flutter --suppress-analytics --no-version-check --version
flutter --suppress-analytics --no-version-check config --enable-web

echo ""
echo "Getting dependencies..."
flutter --suppress-analytics --no-version-check pub get

echo "Checking the public web launch countdown..."
node --test test/web_launch_countdown_test.cjs

echo "Checking account security, billing, privacy, sharing and location flows..."
RELEASE_TESTS=(
  test/home_tool_catalog_test.dart
  test/camera_ask_test.dart
  test/camera_flashlight_test.dart
  test/logo_studio_test.dart
  test/logo_studio_upgrade_test.dart
  test/logo_client_upgrade_test.dart
  test/logo_export_upgrade_test.dart
  test/logo_catalog_expansion_test.dart
  test/logo_astra_test.dart
  test/logo_processing_test.dart
  test/bookkeeping_plan_access_test.dart
  test/fieldproof_plan_access_test.dart
  test/auth_device_session_test.dart
  test/signup_eligibility_test.dart
  test/auth/korlix_token_store_test.dart
  test/apple_billing_test.dart
  test/korlix_ad_consent_test.dart
  test/korlix_share_test.dart
  test/account_deletion_dialog_test.dart
  test/video_download_test.dart
  test/locator_test.dart
  test/privacy/korlix_third_party_ai_consent_test.dart
  test/privacy/korlix_third_party_ai_privacy_statement_test.dart
  test/privacy/korlix_privacy_settings_test.dart
  test/launch/korlix_launch_countdown_test.dart
  test/support/ai_output_report_test.dart
  test/korlix_review_activity_test.dart
  test/korlix_review_host_test.dart
  test/korlix_store_review_test.dart
  test/review_invitation_test.dart
  test/reviews/korlix_app_feedback_dialog_test.dart
  test/korlix_smoke_screensaver_test.dart
  test/social_auto_dump_test.dart
  test/social_dump_truck_test.dart
  test/social_presence_model_test.dart
  test/social_presence_ui_test.dart
  test/social_attachment_lifetime_test.dart
  test/meeting_copilot/k135z_ai_sharing_consent_test.dart
  test/workforce/workforce_location_test.dart
  test/workforce/workforce_test.dart
)

# This is a repeatable source-test gate. A passing web build does not replace
# the signed iPhone/iPad archive and device checks required before submission.
flutter --suppress-analytics --no-version-check test --no-pub "${RELEASE_TESTS[@]}"

echo ""
echo "Building Flutter web release for $APP_BASE_HREF..."

DART_DEFINE_ARGS=()

if [ -n "${SUPABASE_URL:-}" ]; then
  DART_DEFINE_ARGS+=(--dart-define="SUPABASE_URL=$SUPABASE_URL")
fi

if [ -n "${SUPABASE_ANON_KEY:-}" ]; then
  DART_DEFINE_ARGS+=(--dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY")
fi

if [ -n "${KORLIX_OPENAI_PREMIUM_MODEL:-}" ]; then
  DART_DEFINE_ARGS+=(--dart-define="KORLIX_OPENAI_PREMIUM_MODEL=$KORLIX_OPENAI_PREMIUM_MODEL")
fi

if [ -n "${KORLIX_OPENAI_TEXT_MODEL:-}" ]; then
  DART_DEFINE_ARGS+=(--dart-define="KORLIX_OPENAI_TEXT_MODEL=$KORLIX_OPENAI_TEXT_MODEL")
fi

if [ -n "${KORLIX_OPENAI_IMAGE_MODEL:-}" ]; then
  DART_DEFINE_ARGS+=(--dart-define="KORLIX_OPENAI_IMAGE_MODEL=$KORLIX_OPENAI_IMAGE_MODEL")
fi

PWA_ARGS=()
if flutter --suppress-analytics --no-version-check build web --help 2>/dev/null | grep -q -- "--pwa-strategy"; then
  PWA_ARGS+=(--pwa-strategy=none)
fi

flutter --suppress-analytics --no-version-check build web \
  --release \
  --base-href "$APP_BASE_HREF" \
  "${PWA_ARGS[@]}" \
  "${DART_DEFINE_ARGS[@]}"

echo ""
echo "Copying Flutter build into website/app..."
rm -rf website/app
mkdir -p website/app
cp -R build/web/. website/app/

echo ""
echo "KORLIX Render Option A build complete."
echo "Render Publish Directory: website"
echo "Flutter app path: /app/"
find website/app -maxdepth 2 -type f | sort | sed -n '1,120p'
