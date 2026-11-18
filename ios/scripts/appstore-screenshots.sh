#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="docs/screenshots"
OUT="docs/appstore/screenshots"
mkdir -p "$OUT/6.9" "$OUT/6.7" "$OUT/6.1"

python3 - "$SRC" "$OUT" <<'PY'
import os, sys
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
names = [
    "native-library", "native-playlist", "native-player", "native-cache",
    "native-eq", "native-settings", "native-onboarding", "native-offline", "native-lyrics",
]
sizes = {"6.9": (1320, 2868), "6.7": (1290, 2796), "6.1": (1179, 2556)}
for name in names:
    image = Image.open(os.path.join(src, name + ".png")).convert("RGB")
    for folder, (width, height) in sizes.items():
        image.resize((width, height), Image.LANCZOS).save(
            os.path.join(out, folder, name + ".png"), "PNG", optimize=True
        )
print("App Store screenshots:", out)
PY
