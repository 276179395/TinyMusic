#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE_ID="${TM_DEVICE_ID:-00008140-001602DA3EE0801C}"
TEAM_ID="${TEAM_ID:-BCRZR3P4AP}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
WORK="${TM_DEVICE_WORK:-/tmp/TinyMusicDevice}"
ARCHIVE="$WORK/TinyMusic.xcarchive"

rm -rf "$WORK"
mkdir -p "$WORK"
xcodegen generate >/dev/null

echo "==> 归档（开发签名，含 iCloud entitlement）"
xcodebuild archive \
  -project TinyMusic.xcodeproj -scheme TinyMusic \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath "$ARCHIVE" -derivedDataPath "$WORK/DerivedData" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_ENTITLEMENTS=Supporting/TinyMusic.entitlements \
  CODE_SIGN_STYLE=Automatic

APP="$ARCHIVE/Products/Applications/TinyMusic.app"
echo "==> 安装到 $DEVICE_ID"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
echo "==> 启动"
xcrun devicectl device process launch --device "$DEVICE_ID" cn.carljoy.tinymusic || true
echo "完成。首次启动请填 S3 endpoint/bucket/AK/SK。"
