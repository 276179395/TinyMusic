#!/usr/bin/env bash
# 让真机上的 App 连 Mac 上的 rspeedy dev server（热更新）。
#
#   ./mobile/scripts/device-devserver.sh          # 自动取本机局域网 IP
#   ./mobile/scripts/device-devserver.sh 192.168.1.9
#
# App 侧逻辑见 Sources/TemplateProvider.swift：优先读环境变量 / UserDefaults 的 TM_DEV_SERVER。
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

IP="${1:-}"
if [[ -z "$IP" ]]; then
  IP=$(ipconfig getifaddr en0 2>/dev/null || true)
  [[ -z "$IP" ]] && IP=$(ipconfig getifaddr en1 2>/dev/null || true)
fi
if [[ -z "$IP" ]]; then
  echo "拿不到本机局域网 IP，请手动传：$0 192.168.x.x" >&2
  exit 1
fi

URL="http://$IP:3000/main.lynx.bundle"
BUNDLE_ID=$(grep -E 'PRODUCT_BUNDLE_IDENTIFIER' mobile/native/ios/project.yml | head -1 | sed 's/.*PRODUCT_BUNDLE_IDENTIFIER: *//' | tr -d '[:space:]')
BUNDLE_ID="${BUNDLE_ID:-com.tinymusic.app}"

echo "dev server: $URL"
echo "bundle id : $BUNDLE_ID"
echo
echo "已连接的设备："
xcrun devicectl list devices 2>/dev/null | sed -n '1,8p' || echo "  （没装 Xcode 命令行工具或没有设备）"

cat <<EOF

两种填法：

A. 从 Xcode 启动（最简单）
   Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables
   名称 TM_DEV_SERVER，值 $URL
   然后 ⌘R

B. 命令行启动（脱离 Xcode）
   xcrun devicectl device process launch --device <设备ID> \
     --environment-variables '{"TM_DEV_SERVER":"$URL"}' $BUNDLE_ID

确认生效：日志里应出现「Lynx bundle 来自 dev server: $URL」
   xcrun devicectl device console --device <设备ID> | grep -i tinymusic

提示：dev server 在 Mac 上跑 `pnpm dev:mobile`（默认监听 3000）；
手机和 Mac 要在同一个 Wi-Fi；首次连接手机可能弹「本地网络」权限，选允许。
EOF
