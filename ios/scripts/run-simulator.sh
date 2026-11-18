#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-iPhone 18 Pro}"
DEST="platform=iOS Simulator,name=$DEVICE"
DERIVED="${TM_DERIVED:-/tmp/TinyMusicDerived}"
xcodegen generate >/dev/null
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator 2>/dev/null || true
xcodebuild -project TinyMusic.xcodeproj -scheme TinyMusic -destination "$DEST" \
  -configuration Debug -derivedDataPath "$DERIVED" build >/dev/null
APP="$DERIVED/Build/Products/Debug-iphonesimulator/TinyMusic.app"
xcrun simctl install booted "$APP"
xcrun simctl launch booted cn.carljoy.tinymusic
