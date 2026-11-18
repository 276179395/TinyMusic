#!/usr/bin/env bash
set -euo pipefail
# Seed a fictional demo library into an S3-compatible endpoint.
# Usage: ./seed-demo-library.sh [endpoint] [bucket] [prefix]
ENDPOINT="${1:-http://127.0.0.1:9100}"
BUCKET="${2:-music}"
PREFIX="${3:-TinyMusic}"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT

python3 - "$DIR" <<'PY'
import math, os, struct, sys, wave
from PIL import Image, ImageDraw, ImageFont

root = sys.argv[1]
tracks = [
    ("01 夜航", "Luna - 夜航", "Luna", "夜航", (27, 42, 74), (255, 90, 95), 220.0),
    ("01 夜航", "Luna - 潮汐", "Luna", "潮汐", (18, 60, 58), (126, 224, 195), 277.2),
    ("01 夜航", "Kite - 城市微光", "Kite", "城市微光", (43, 27, 58), (255, 179, 71), 329.6),
    ("01 夜航", "Kite - 凌晨四点", "Kite", "凌晨四点", (15, 27, 45), (138, 182, 255), 392.0),
    ("02 原声", "Mori - 木吉他", "Mori", "木吉他", (58, 42, 27), (232, 184, 109), 246.9),
    ("02 原声", "Mori - 雨停之后", "Mori", "雨停之后", (29, 42, 27), (168, 213, 162), 293.7),
]

font_path = "/System/Library/Fonts/PingFang.ttc"
try:
    title_font = ImageFont.truetype(font_path, 58)
    small_font = ImageFont.truetype(font_path, 26)
except Exception:
    title_font = ImageFont.load_default()
    small_font = ImageFont.load_default()

sr, dur = 44100, 8
for folder, stem, artist, title, c1, c2, freq in tracks:
    out = os.path.join(root, folder)
    os.makedirs(out, exist_ok=True)
    base = os.path.join(out, stem)

    img = Image.new("RGB", (900, 900))
    px = img.load()
    for y in range(900):
        for x in range(900):
            t = (x + y) / 1800
            px[x, y] = tuple(int(c1[i] * (1 - t) + c2[i] * t) for i in range(3))
    draw = ImageDraw.Draw(img, "RGBA")
    draw.ellipse((80, 80, 820, 820), outline=(255, 255, 255, 40), width=2)
    draw.ellipse((170, 170, 730, 730), outline=(255, 255, 255, 30), width=1)
    draw.ellipse((300, 300, 600, 600), fill=(0, 0, 0, 45))
    draw.text((70, 600), title, font=title_font, fill=(255, 255, 255, 235))
    draw.text((72, 680), artist.upper() + "  ·  NIGHT DRIVE", font=small_font, fill=(255, 255, 255, 150))
    img.save(base + ".jpg", quality=92)

    with open(base + ".lrc", "w", encoding="utf-8") as f:
        f.write("[00:00.00] " + title + "\n")
        f.write("[00:01.00] " + artist + "\n")
        f.write("[00:02.50] 夜色落在窗边\n")
        f.write("[00:04.00] 让节拍慢慢靠近\n")
        f.write("[00:06.00] TinyMusic · 只播放你的音乐\n")

    with wave.open(base + ".wav", "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        frames = bytearray()
        for i in range(sr * dur):
            amp = 11000
            env = min(1.0, i / (sr * 0.08), (sr * dur - i) / (sr * 0.35))
            sample = int(amp * env * (math.sin(2 * math.pi * freq * i / sr) + 0.28 * math.sin(2 * math.pi * freq * 2 * i / sr)))
            frames += struct.pack("<h", max(-32768, min(32767, sample)))
        w.writeframes(bytes(frames))
PY

for wav in "$DIR"/*/*.wav; do
  afconvert -f m4af -d aac -b 128000 "$wav" "${wav%.wav}.m4a" >/dev/null
  rm -f "$wav"
done

while IFS= read -r file; do
  rel="${file#"$DIR"/}"
  key="$PREFIX/$rel"
  encoded="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$key")"
  curl -fsS -X PUT --data-binary "@$file" "$ENDPOINT/$BUCKET/$encoded" >/dev/null
  echo "seeded $key"
done < <(find "$DIR" -type f | sort)
