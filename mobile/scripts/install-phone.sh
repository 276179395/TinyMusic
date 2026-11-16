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
# Team 候选：描述文件里出现过的 Team 才是真能签的；证书可能来自已移除的账号
candidate_teams() {
  python3 - <<'PY'
import glob, os, plistlib, subprocess, sys
teams = []
# 1) 已有描述文件
for path in glob.glob(os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles/*.provisionprofile")):
    try:
        raw = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True).stdout
        data = plistlib.loads(raw)
        for t in data.get("TeamIdentifier", []) or []:
            if t not in teams:
                teams.append(t)
    except Exception:
        pass
# 2) 证书（兜底）
try:
    out = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True).stdout
    import re
    for t in re.findall(r"Apple Development: [^(]*\(([A-Z0-9]{10})\)", out):
        if t not in teams:
            teams.append(t)
except Exception:
    pass
for t in teams:
    print(t)
PY
}

TEAM="${TM_TEAM:-}"
if [[ -z "$TEAM" ]]; then
  TEAMS=$(candidate_teams || true)
  TEAM=$(printf '%s\n' "$TEAMS" | head -1)
  TEAM_LIST="$TEAMS"
else
  TEAM_LIST="$TEAM"
fi
[[ -n "$TEAM" ]] || fail "没找到可用的 Team。先在 Xcode → Settings → Accounts 登录 Apple ID，再回来跑。"
say "✓ Team 候选: $(printf '%s' "${TEAM_LIST:-$TEAM}" | paste -sd' ' -)"

BUNDLE_ID="${TM_BUNDLE_ID:-$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER: *//p' "$IOS/project.yml" | head -1 | tr -d '[:space:]')}"
BUNDLE_ID="${BUNDLE_ID:-com.tinymusic.app}"
say "✓ Bundle ID: $BUNDLE_ID"


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
  # 开发者模式没开时，安装会以「cryptex / DDI 无法挂载」失败，提前讲清楚
  if xcrun devicectl device info details --device "$DEVICE_ID" 2>&1 | grep -q 'Developer Mode is turned off'; then
    say ""
    say "! 手机的「开发者模式」还关着，安装会被系统拒绝。请先在手机上打开："
    say "   设置 → 隐私与安全性 → 开发者模式 → 打开 → 输入密码 → 重启"
    say "   重启解锁后会再问一次，点「打开」"
    [[ $CHECK_ONLY -eq 1 ]] || fail "打开开发者模式并重启后，重跑本脚本。"
  fi
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
build_with_team() {
  (cd "$IOS" && xcodebuild -workspace TinyMusic.xcworkspace -scheme TinyMusic \
    -configuration Release -destination 'generic/platform=iOS' \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$1" CODE_SIGN_STYLE=Automatic \
    build > /tmp/tm-install-build.log 2>&1)
}

# 逐个候选 Team 试，第一个能签过描述文件的就是它
build_signed() {
  local t
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    if build_with_team "$t"; then
      TEAM="$t"
      say "✓ 用 Team $t 完成签名"
      return 0
    fi
    say "  Team $t 签不过，换下一个"
  done <<< "$(printf '%s\n' "${TEAM_LIST:-$TEAM}")"
  return 1
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
if ! xcrun devicectl device install app --device "$DEVICE_ID" "$APP" > /tmp/tm-install-devicectl.log 2>&1; then
  if grep -qiE 'developer mode is not enabled|developer mode is turned off|cryptex|DDI' /tmp/tm-install-devicectl.log; then
    say ""
    fail "手机没开「开发者模式」，系统拒绝了安装。请在手机上：
   设置 → 隐私与安全性 → 开发者模式 → 打开 → 输入锁屏密码 → 重启
   重启解锁后再点一次「打开」，然后重跑本脚本。"
  fi
  tail -6 /tmp/tm-install-devicectl.log
  fail "安装失败。也可以在 Xcode 里选中手机按 ⌘R（那时会自动处理授权）。"
fi

cat <<EOF

✅ 装好了。第一次打开前：

1. 手机上 设置 → 通用 → VPN 与设备管理 → 信任你的开发者证书
2. 回桌面点 TinyMusic 图标

注意：免费 Apple ID 签的 App 7 天后过期，过期重跑：
  ./mobile/scripts/install-phone.sh
EOF
