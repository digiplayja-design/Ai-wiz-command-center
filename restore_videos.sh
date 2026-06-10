#!/usr/bin/env bash
cp pubspec.yaml pubspec.yaml.video_restore.$(date +%H%M%S)

# Remove broken references
sed -i '/intro_2\.mp4/d' pubspec.yaml
sed -i '/intro_3\.mp4/d' pubspec.yaml

# Ensure sequence files exist
sed -i '/jj\/intro\.mp4/a\    - assets/characters/jj/intro_sequence.mp4' pubspec.yaml
sed -i '/yuna\/intro\.mp4/a\    - assets/characters/yuna/intro_sequence.mp4' pubspec.yaml

echo "✅ Videos restored in pubspec"
grep -E "intro_sequence|jj/|yuna/" pubspec.yaml
