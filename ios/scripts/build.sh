#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="${1:-platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2}"
DERIVED="${TM_DERIVED:-/tmp/TinyMusicDerived}"
xcodegen generate >/dev/null
xcodebuild -project TinyMusic.xcodeproj -scheme TinyMusic \
  -destination "$DEST" -configuration Debug -derivedDataPath "$DERIVED" build
