#!/usr/bin/env bash
cp pubspec.yaml pubspec.yaml.backup.$(date +%H%M%S)

# Remove the missing individual files
sed -i '/jj\/intro_2\.mp4/d' pubspec.yaml
sed -i '/jj\/intro_3\.mp4/d' pubspec.yaml

# Make sure the sequence file is present
if ! grep -q "jj/intro_sequence.mp4" pubspec.yaml; then
  sed -i '/jj\/intro\.mp4/a\    - assets/characters/jj/intro_sequence.mp4' pubspec.yaml
fi

echo "✅ Cleaned pubspec.yaml"
grep -A 5 -E "jj/" pubspec.yaml
