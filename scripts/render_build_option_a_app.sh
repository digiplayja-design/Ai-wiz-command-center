#!/usr/bin/env bash
set -euo pipefail

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
    rm -rf "$FLUTTER_DIR"
    git clone --depth 1 --branch "$FLUTTER_CHANNEL" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  fi

  export PATH="$FLUTTER_DIR/bin:$PATH"
else
  echo "Flutter already available."
fi

flutter --version
flutter config --enable-web

echo ""
echo "Getting dependencies..."
flutter pub get

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
if flutter build web --help 2>/dev/null | grep -q -- "--pwa-strategy"; then
  PWA_ARGS+=(--pwa-strategy=none)
fi

flutter build web \
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
