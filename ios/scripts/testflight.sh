#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="${TEAM_ID:-BCRZR3P4AP}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ENTITLEMENTS="${TM_ENTITLEMENTS:-Supporting/TinyMusic.entitlements}"
WORK="${TM_TF_WORK:-/tmp/TinyMusicTestFlight}"
ARCHIVE="$WORK/TinyMusic.xcarchive"
EXPORT="$WORK/upload"
AUTH_ARGS=()
if [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

if ! security find-identity -v -p codesigning | grep -q "Apple Development\|Apple Distribution"; then
  echo "没有可用签名证书。请先在 Xcode → Settings → Accounts 登录 Apple ID。" >&2
  exit 2
fi

rm -rf "$WORK"
mkdir -p "$WORK"
xcodegen generate >/dev/null

echo "==> 归档（entitlements: ${ENTITLEMENTS}, build ${BUILD_NUMBER}）"
xcodebuild archive \
  -project TinyMusic.xcodeproj -scheme TinyMusic \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath "$ARCHIVE" -derivedDataPath "$WORK/DerivedData" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
  CODE_SIGN_STYLE=Automatic \
  ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}

echo "==> 导出并上传到 TestFlight"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.upload.plist \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates \
  ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}

echo "==> 上传完成；App Store Connect → TestFlight 等待处理 10–30 分钟。"
