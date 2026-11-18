#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="${1:-platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2}"
DERIVED="${TM_DERIVED:-/tmp/TinyMusicDerived}"

if ! curl -fsS http://127.0.0.1:9100 >/dev/null 2>&1; then
  cargo run --manifest-path ../desktop/Cargo.toml -p tinymusic-server --example s3_stub -- --port 9100 --dir /tmp/tm-s3stub &
  STUB_PID=$!
  trap 'kill "$STUB_PID" 2>/dev/null || true' EXIT
  sleep 1
fi
./scripts/seed-s3-stub.sh

xcodegen generate >/dev/null
xcodebuild test -project TinyMusic.xcodeproj -scheme TinyMusic \
  -destination "$DEST" -derivedDataPath "$DERIVED" \
  -only-testing:TinyMusicTests
