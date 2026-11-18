#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
DERIVED="${TM_ARCHIVE_DERIVED:-/tmp/TinyMusicArchiveDerived}"
ARCHIVE="${TM_ARCHIVE_PATH:-/tmp/TinyMusic.xcarchive}"
xcodegen generate >/dev/null
rm -rf "$ARCHIVE" "$DERIVED"
xcodebuild archive \
  -project TinyMusic.xcodeproj -scheme TinyMusic \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath "$ARCHIVE" -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO
echo "unsigned archive: $ARCHIVE"
echo "App Store upload needs a Development Team + provisioning profile; remove CODE_SIGNING_ALLOWED=NO and run:"
echo "  xcodebuild -exportArchive -archivePath \"$ARCHIVE\" -exportOptionsPlist ExportOptions.plist -exportPath /tmp/TinyMusicExport"
