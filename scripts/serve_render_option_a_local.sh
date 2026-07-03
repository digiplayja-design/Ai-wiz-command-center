#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-8080}"

bash scripts/render_build_option_a_app.sh

echo ""
echo "Serving website on port $PORT"
echo "Root: /"
echo "App:  /app/"
python3 -m http.server "$PORT" --directory website
