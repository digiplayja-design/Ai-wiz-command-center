#!/usr/bin/env bash
echo "=== Checking featured character video settings ==="

grep -n "setVolume\|autoplay\|VideoPlayerController" lib/main.dart | head -15

echo ""
echo "✅ Check complete"
