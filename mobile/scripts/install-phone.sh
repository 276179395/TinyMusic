#!/usr/bin/env bash
# 把 TinyMusic 装到连着的 iPhone 上（Release 构建 + 自动签名 + devicectl 安装）。
#
#   ./mobile/scripts/install-phone.sh                 # 自动找证书/设备
#   ./mobile/scripts/install-phone.sh --check         # 只做检查，不动手
#   TM_TEAM=ABCDE12345 ./mobile/scripts/install-phone.sh
#   TM_BUNDLE_ID=com.yourname.tinymusic ./mobile/scripts/install-phone.sh
#
# 免费 Apple ID 也能用；签出来的 App 7 天后过期，过期重跑本脚本即可。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS="$ROOT/mobile/native/ios"
CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

say() { printf '%s\n' "$*"; }
fail() { printf '✗ %s\n' "$*" >&2; exit 1; }

# ---------- 1. 证书 / Team ----------
TEAM="${TM_TEAM:-}"
if [[ -z "$TEAM" ]]; then
  IDENT=$(security find-identity -v -p codesigning 2>/dev/null | grep -E 'Apple Development' | head -1 || true)
  TEAM=$(printf '%s' "$IDENT" | sed -n 's/.*(\([A-Z0-9]\{10\}\))".*/\1/p')
fi
[[ -n "$TEAM" ]] || fail "没找到 Apple Development 证书。先在 Xcode → Settings → Accounts 登录 Apple ID（会自动生成证书），再回来跑。"
say "✓ Team: $TEAM"

BUNDLE_ID="${TM_BUNDLE_ID:-$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER: *//p' "$IOS/project.yml" | head -1 | tr -d '[:space:]')}"
BUNDLE_ID="${BUNDLE_ID:-com.tinymusic.app}"
say "✓ Bundle ID: $BUNDLE_ID"

# Xcode 账号是否真的可用（证书在、但账号没登录时 xcodebuild 会报 No Account for Team）
if ! defaults read com.apple.dt.Xcode IDEProvisioningTeams >/dev/null 2>&1; then
  say "! 没读到 Xcode 里缓存的 Team —— 如果自动签名失败，去 Xcode → Settings → Accounts 加 Apple ID。"
fi

# ---------- 2. 设备 ----------
DEV_INFO=$(xcrun devicectl list devices --json-output /tmp/tm-devices.json >/dev/null 2>&1 && python3 - /tmp/tm-devices.json <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
for dev in data.get("result", {}).get("devices", []):
    hw = dev.get("hardwareProperties", {}) or {}
    cp = dev.get("connectionProperties", {}) or {}
    dp = dev.get("deviceProperties", {}) or {}
    if hw.get("reality") == "simulated":
        continue
    if (cp.get("transportType") or "") not in ("wired", "wireless", "localNetwork"):
        continue
    print("%s\t%s\t%s\t%s" % (
        hw.get("udid", ""),
        dp.get("name", ""),
        cp.get("pairingState", ""),
        dp.get("osVersionNumber", ""),
    ))
    break
PY
) || true

if [[ -z "$DEV_INFO" ]]; then
  say "! 没检测到已连接的真机。"
  say "  1) 用数据线把 iPhone 连到 Mac"
  say "  2) 手机上点「信任此电脑」并输入锁屏密码"
  say "  3) 手机 设置 → 隐私与安全性 → 开发者模式 → 打开（需重启）"
  [[ $CHECK_ONLY -eq 1 ]] || fail "把手机连上再来。"
else
  DEVICE_ID=$(printf '%s' "$DEV_INFO" | cut -f1)
  DEVICE_NAME=$(printf '%s' "$DEV_INFO" | cut -f2)
  DEVICE_STATE=$(printf '%s' "$DEV_INFO" | cut -f3)
  DEVICE_OS=$(printf '%s' "$DEV_INFO" | cut -f4)
  say "✓ 设备: ${DEVICE_NAME}（iOS ${DEVICE_OS}, ${DEVICE_STATE}）"
fi

[[ $CHECK_ONLY -eq 1 ]] && { say ""; say "检查完毕，可以直接跑不带 --check 的命令安装。"; exit 0; }

# ---------- 3. 准备工程 ----------
say ""
say "== 构建 Lynx bundle =="
(cd "$ROOT" && pnpm -F @tinymusic/mobile build 2>&1 | grep -E 'lynx.bundle|error' | head -2 || true)

say "== 写入签名配置并重新生成工程 =="
TM_TEAM="$TEAM" TM_BUNDLE_ID="$BUNDLE_ID" "$ROOT/mobile/scripts/device-setup.sh" "$TEAM" "$BUNDLE_ID" > /tmp/tm-install-setup.log 2>&1 \
  || { tail -5 /tmp/tm-install-setup.log; fail "工程准备失败（详见 /tmp/tm-install-setup.log）"; }

# ---------- 4. 签名构建 ----------
build_signed() {
  (cd "$IOS" && xcodebuild -workspace TinyMusic.xcworkspace -scheme TinyMusic \
    -configuration Release -destination 'generic/platform=iOS' \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
    build > /tmp/tm-install-build.log 2>&1)
}

say "== 构建 Release（签名）=="

build_signed() {
  (cd "$IOS" && xcodebuild -workspace TinyMusic.xcworkspace -scheme TinyMusic \
    -configuration Release -destination 'generic/platform=iOS' \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
    build > /tmp/tm-install-build.log 2>&1)
}

if ! build_signed; then
  # Bundle ID 被别人占用 → 换成唯一后缀再试一次
  if grep -qiE 'not available|already (been )?registered|identifier.*in use|invalid.*bundle' /tmp/tm-install-build.log; then
    BUNDLE_ID="com.tinymusic.app.$(printf '%s' "$TEAM" | tr 'A-Z' 'a-z')"
    say "! Bundle ID 被占用，自动换成 $BUNDLE_ID 重试"
    "$ROOT/mobile/scripts/device-setup.sh" "$TEAM" "$BUNDLE_ID" > /tmp/tm-install-setup.log 2>&1 || {
      tail -5 /tmp/tm-install-setup.log
      fail "重新生成工程失败"
    }
    build_signed || {
      grep -E 'error:' /tmp/tm-install-build.log | head -6
      fail "换成唯一 Bundle ID 仍然失败（完整日志 /tmp/tm-install-build.log）"
    }
  fi
  if grep -q 'No Account for Team' /tmp/tm-install-build.log; then
    say ""
    fail "Xcode 里没有这个 Team 的账号。请先在 Xcode 添加 Apple ID：
   Xcode → Settings（⌘,）→ Accounts → 左下角 + → 用你的 Apple ID 登录
   登录后重跑：./mobile/scripts/install-phone.sh"
  fi
  if grep -q 'No profiles for' /tmp/tm-install-build.log; then
    fail "自动签名没拿到描述文件：确认 Xcode 已登录 Apple ID；仍失败就换一个自己唯一的 Bundle ID（TM_BUNDLE_ID=... 重跑）"
  fi
  say "构建失败，关键报错："
  grep -E 'error:' /tmp/tm-install-build.log | head -6
  fail "完整日志：/tmp/tm-install-build.log"
fi

APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/TinyMusic-*/Build/Products/Release-iphoneos/TinyMusic.app 2>/dev/null | head -1 || true)
[[ -n "$APP" ]] || fail "找不到构建产物 TinyMusic.app"

# ---------- 5. 安装到手机 ----------
say "== 安装到手机（$DEVICE_ID）=="
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" > /tmp/tm-install-devicectl.log 2>&1 || {
  tail -6 /tmp/tm-install-devicectl.log
  fail "安装失败。也可以在 Xcode 里选中手机按 ⌘R（那时会自动处理授权）。"
}

cat <<EOF

✅ 装好了。第一次打开前：

1. 手机上 设置 → 通用 → VPN 与设备管理 → 信任你的开发者证书
2. 回桌面点 TinyMusic 图标

注意：免费 Apple ID 签的 App 7 天后过期，过期重跑：
  ./mobile/scripts/install-phone.sh
EOF
