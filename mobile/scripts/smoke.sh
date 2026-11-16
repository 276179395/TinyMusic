#!/usr/bin/env bash
# 模拟器冒烟：构建 bundle + App → 安装 → 带环境变量启动 → 截图 / 抓日志
#
#   ./mobile/scripts/smoke.sh /tmp/shot.png TM_AUTOPLAY=1 TM_OPEN_PLAYER=1
#
# 约定：
# - 只重编 bundle（pnpm build）和 App（xcodebuild），不跑 pod install；
#   native 文件有增删时先手动跑一次 xcodegen generate + pod install。
# - 日志只打含 [TinyMusic] 的行，避免被系统日志淹没。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-/tmp/tm-smoke.png}"
shift || true
APPDIR="$ROOT/mobile/native/ios"
BUNDLE_ID="com.tinymusic.app"

echo "== 1/4 构建 bundle =="
(cd "$ROOT" && pnpm -F @tinymusic/mobile build 2>&1 | grep -E 'error|lynx.bundle' || true)

echo "== 2/4 构建 App =="
(cd "$APPDIR" && xcodebuild -workspace TinyMusic.xcworkspace -scheme TinyMusic \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build > /tmp/tm-xcode.log 2>&1) \
  && echo "   build ok" || { echo "   build FAILED"; grep -E 'error:' /tmp/tm-xcode.log | head -5; exit 1; }

APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/TinyMusic-*/Build/Products/Debug-iphonesimulator/TinyMusic.app | head -1)

echo "== 3/4 安装并启动 =="
xcrun simctl terminate booted "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install booted "$APP"
# 其余参数以 SIMCTL_CHILD_ 前缀注入给 App 进程
ENVS=()
for kv in "$@"; do ENVS+=("SIMCTL_CHILD_$kv"); done
env "${ENVS[@]}" xcrun simctl launch booted "$BUNDLE_ID" >/dev/null
sleep "${TM_WAIT:-14}"

echo "== 4/4 截图 + 日志 =="
xcrun simctl io booted screenshot "$OUT" >/dev/null 2>&1
echo "   screenshot: $OUT"

# 默认跑完就退出 App，避免模拟器在后台一直放歌（设 TM_KEEP=1 可保留）
if [[ "${TM_KEEP:-0}" != "1" ]]; then
  xcrun simctl terminate booted "$BUNDLE_ID" >/dev/null 2>&1 || true
  echo "   已退出 App（TM_KEEP=1 可保留）"
fi
xcrun simctl spawn booted log show --last "${TM_LOG_WINDOW:-40s}" --predicate "process == \"TinyMusic\"" 2>/dev/null \
  | grep -F '[TinyMusic]' | tail -12 || true
