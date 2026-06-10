#!/usr/bin/env bash
echo "=== Checking all character video files ==="

for char in jj yuna phil ji-a chee_chai_chee; do
  echo "→ $char:"
  ls -la assets/characters/$char/ 2>/dev/null || echo "  Folder not found"
  grep -E "$char/" pubspec.yaml || echo "  Not in pubspec.yaml"
  echo ""
done

echo "=== Done ==="
