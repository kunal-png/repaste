#!/bin/bash
set -euo pipefail

# ============================================================
# create-dmg.sh — Build Repaste.app and package it into a DMG
# ============================================================
#
# Usage:
#   ./scripts/create-dmg.sh
#
# Prerequisites:
#   - Xcode command-line tools installed
#   - Run from the repo root (or adjust PROJ_DIR)
#
# Output:
#   ./build/Repaste.dmg

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJ_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/Repaste.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/Repaste.dmg"
APP_NAME="Repaste"

echo "📁 Project: $PROJ_DIR"
echo "🔨 Archiving..."

mkdir -p "$BUILD_DIR"

xcodebuild archive \
    -project "$PROJ_DIR/Repaste.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    | tail -5

echo "📦 Exporting app..."

# Export without signing
cat > "$BUILD_DIR/export-options.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>manual</string>
</dict>
</plist>
EOF

# Copy the .app directly from the archive (simpler for unsigned builds)
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$EXPORT_DIR/"

echo "💿 Creating DMG..."

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$EXPORT_DIR/$APP_NAME.app" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo ""
echo "✅ Done! DMG created at:"
echo "   $DMG_PATH"
echo ""
echo "📎 Upload this DMG to a GitHub Release."
