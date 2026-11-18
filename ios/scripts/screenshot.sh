#!/usr/bin/env bash
set -euo pipefail
OUT="${1:-docs/screenshot.png}"
mkdir -p "$(dirname "$OUT")"
xcrun simctl io booted screenshot "$OUT"
echo "saved $OUT"
