#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-8080}"

echo "Building website/app using Render Option A script..."
bash scripts/render_build_option_a_app.sh

echo ""
echo "Serving website/ on port $PORT"
echo "Root website: /"
echo "Flutter app: /app/"
echo ""
echo "Open Codespaces PORTS tab, open port $PORT, then test / and /app/."

python3 -m http.server "$PORT" --directory website
