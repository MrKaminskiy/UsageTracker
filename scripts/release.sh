#!/bin/bash
set -euo pipefail

APP_NAME="UsageTracker"
BUNDLE_DIR="build/${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
IDENTITY="${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to your Developer ID Application certificate name}"
NOTARY_PROFILE="${NOTARY_PROFILE:-usagetracker-release}"

echo "==> Building release (universal binary)..."
swift build -c release --triple arm64-apple-macosx
swift build -c release --triple x86_64-apple-macosx
lipo -create \
    .build/arm64-apple-macosx/release/UsageTracker \
    .build/x86_64-apple-macosx/release/UsageTracker \
    -output .build/release-universal-UsageTracker

echo "==> Creating app bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp .build/release-universal-UsageTracker "$BUNDLE_DIR/Contents/MacOS/UsageTracker"
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
ZIP_PATH="build/${APP_NAME}.zip"
ditto -c -k --keepParent "$BUNDLE_DIR" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
rm -f "$ZIP_PATH"

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

echo "==> Notarizing DMG..."
xcrun notarytool submit "build/$DMG_NAME" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling DMG..."
xcrun stapler staple "build/$DMG_NAME"

echo "==> Done! Output: build/$DMG_NAME"
