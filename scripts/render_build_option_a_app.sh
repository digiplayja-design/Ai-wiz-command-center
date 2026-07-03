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

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found. Installing Flutter SDK into $FLUTTER_DIR..."
  if [ ! -d "$FLUTTER_DIR/.git" ]; then
    rm -rf "$FLUTTER_DIR"
    git clone --depth 1 --branch "$FLUTTER_CHANNEL" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  fi
  export PATH="$FLUTTER_DIR/bin:$PATH"
fi

flutter --version
flutter config --enable-web
flutter pub get

DART_DEFINE_ARGS=()

if [ -n "${SUPABASE_URL:-}" ]; then
  DART_DEFINE_ARGS+=(--dart-define="SUPABASE_URL=$SUPABASE_URL")
fi

if [ -n "${SUPABASE_ANON_KEY:-}" ]; then
  DART_DEFINE_ARGS+=(--dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY")
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

rm -rf website/app
mkdir -p website/app
cp -R build/web/. website/app/

echo ""
echo "KORLIX Render Option A build complete."
echo "Publish Directory: website"
echo "App path: /app/"
find website/app -maxdepth 2 -type f | sort | sed -n '1,100p'
