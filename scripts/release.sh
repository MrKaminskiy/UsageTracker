#!/bin/bash
set -euo pipefail

APP_NAME="UsageTracker"
BUNDLE_DIR="build/${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
IDENTITY="${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to your Developer ID Application certificate name}"
TEAM_ID="${TEAM_ID:?Set TEAM_ID to your Apple Developer Team ID}"
APPLE_ID="${APPLE_ID:?Set APPLE_ID to your Apple ID email}"
APP_PASSWORD="${APP_PASSWORD:?Set APP_PASSWORD to an app-specific password}"

echo "==> Building release (universal binary)..."
swift build -c release
# Note: SwiftPM builds for the host architecture by default.
# For a universal binary, use: swift build -c release --triple arm64-apple-macosx && swift build -c release --triple x86_64-apple-macosx
# then lipo them together. For v1.0, building for host arch (Apple Silicon) is fine.

echo "==> Creating app bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp .build/release/UsageTracker "$BUNDLE_DIR/Contents/MacOS/"
cp Info.plist "$BUNDLE_DIR/Contents/"

# Copy app icon if it exists
if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "$BUNDLE_DIR/Contents/Resources/"
fi

echo "==> Signing..."
codesign --force --options runtime --sign "$IDENTITY" \
    --entitlements Entitlements.plist \
    "$BUNDLE_DIR"

echo "==> Notarizing..."
xcrun notarytool submit "$BUNDLE_DIR" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

echo "==> Stapling..."
xcrun stapler staple "$BUNDLE_DIR"

echo "==> Creating DMG..."
rm -f "build/$DMG_NAME"

# Create a temporary DMG directory
DMG_TMP="build/dmg_tmp"
rm -rf "$DMG_TMP"
mkdir -p "$DMG_TMP"
cp -R "$BUNDLE_DIR" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TMP" \
    -ov -format UDZO \
    "build/$DMG_NAME"

rm -rf "$DMG_TMP"

# Sign the DMG too
codesign --force --sign "$IDENTITY" "build/$DMG_NAME"

echo "==> Done! Output: build/$DMG_NAME"
