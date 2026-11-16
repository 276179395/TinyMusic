#!/usr/bin/env bash
# 真机调试准备：把 Team ID / Bundle ID 写进 project.yml，重新生成工程并装 Pods。
#
#   ./mobile/scripts/device-setup.sh ABCDE12345
#   ./mobile/scripts/device-setup.sh ABCDE12345 com.yourname.tinymusic
#
# 找 Team ID：
#   1) Xcode → Settings → Accounts → 选中账号 → 右侧 Team 列表里的 10 位 ID
#   2) security find-identity -v -p codesigning
#      "Apple Development: you@example.com (ABCDE12345)"  ← 括号里那串
#
# 说明：这两行会改到受版本管理的 project.yml 里。之后想还原：
#   git checkout mobile/native/ios/project.yml
set -euo pipefail

TEAM_ID="${1:-}"
BUNDLE_ID="${2:-com.tinymusic.app}"
if [[ -z "$TEAM_ID" ]]; then
  echo "用法: $0 <TEAM_ID> [BUNDLE_ID]" >&2
  echo "（TEAM_ID 是 10 位，例如 ABCDE12345）" >&2
  exit 1
fi
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "看起来不像 Team ID：$TEAM_ID（应为 10 位大写字母/数字）" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS="$ROOT/mobile/native/ios"
SPEC="$IOS/project.yml"

python3 - "$SPEC" "$TEAM_ID" "$BUNDLE_ID" <<'PY'
import re, sys
path, team, bundle = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path, encoding="utf-8").read()
src = re.sub(r'(?m)^(\s*)DEVELOPMENT_TEAM:.*$', rf'\1DEVELOPMENT_TEAM: "{team}"', src)
src = re.sub(r'(?m)^(\s*)PRODUCT_BUNDLE_IDENTIFIER:.*$', rf'\1PRODUCT_BUNDLE_IDENTIFIER: {bundle}', src)
open(path, "w", encoding="utf-8").write(src)
print(f"已写入 {path}")
print(f"  DEVELOPMENT_TEAM = {team}")
print(f"  PRODUCT_BUNDLE_IDENTIFIER = {bundle}")
PY

echo "== 重新生成工程（xcodegen 会清掉 Pods 集成，必须重新 pod install）=="
cd "$IOS"
xcodegen generate > /dev/null
pod install > /tmp/tm-pod-device.log 2>&1 && echo "   pods ok" || { echo "   pod install 失败，看 /tmp/tm-pod-device.log"; exit 1; }

cat <<EOF

== 下一步 ==
1. 手机：设置 → 隐私与安全性 → 开发者模式 → 打开（需要重启）
2. open "$IOS/TinyMusic.xcworkspace"
3. Xcode 顶部选中你的 iPhone（首次要在 Window → Devices and Simulators 里配对）→ ⌘R
4. 首次启动被拦：手机 设置 → 通用 → VPN与设备管理 → 信任你的开发者证书
5. 想用热更新：./mobile/scripts/device-devserver.sh

注意：免费 Apple ID 签的 App 7 天过期，过期后重跑一次 ⌘R 即可。
EOF
