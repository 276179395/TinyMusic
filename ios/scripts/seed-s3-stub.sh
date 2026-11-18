#!/usr/bin/env bash
set -euo pipefail
# Seed the local S3 stub with a 3s test track, LRC and cover.
# Usage: ./seed-s3-stub.sh [endpoint] [bucket] [prefix]
ENDPOINT="${1:-http://127.0.0.1:9100}"
BUCKET="${2:-music}"
PREFIX="${3:-TinyMusic}"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT

python3 - "$DIR/tone.wav" <<'PY'
import math, struct, sys, wave
path = sys.argv[1]
sr, dur, freq = 44100, 3, 440
with wave.open(path, "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sr)
    w.writeframes(b"".join(struct.pack("<h", int(12000 * math.sin(2 * math.pi * freq * i / sr))) for i in range(sr * dur)))
PY
afconvert -f m4af -d aac -b 128000 "$DIR/tone.wav" "$DIR/song.m4a" >/dev/null
cat > "$DIR/song.lrc" <<'LRC'
[00:00.00]TinyMusic
[00:01.00]Playing from your own S3
[00:02.00]Liquid Glass
LRC
cp "$(cd "$(dirname "$0")/../.." && pwd)/desktop/site/assets/icon.png" "$DIR/cover.jpg" 2>/dev/null || true
if [ ! -f "$DIR/cover.jpg" ]; then
  printf '\211PNG\r\n\032\n' > "$DIR/cover.jpg"
fi

KEY="${PREFIX}/Test/Artist - Song"
curl -fsS -X PUT --data-binary @"$DIR/song.m4a" "$ENDPOINT/$BUCKET/$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$KEY.m4a")" >/dev/null
curl -fsS -X PUT --data-binary @"$DIR/song.lrc" "$ENDPOINT/$BUCKET/$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$KEY.lrc")" >/dev/null
curl -fsS -X PUT --data-binary @"$DIR/cover.jpg" "$ENDPOINT/$BUCKET/$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$KEY.jpg")" >/dev/null
echo "seeded $BUCKET/$KEY.*"
