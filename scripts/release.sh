#!/bin/bash
set -euo pipefail

APP_NAME="UsageTracker"
BUNDLE_DIR="build/${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
IDENTITY="${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to your Developer ID Application certificate name}"
NOTARY_PROFILE="${NOTARY_PROFILE:-usagetracker-release}"

echo "==> Building release (universal binary)..."
# The native build system on purpose: Swift 6.4's default (swiftbuild) records the deployment
# target (14.0) as the linked SDK version, so macOS draws the app in its pre-26 compatibility
# look (no floating Settings sidebar). Native records the real SDK, as every release through
# 1.4.0 did.
BUILD_SYSTEM="--build-system native"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
# Ask SwiftPM where each build lands, and copy each arch out right after its build: a hardcoded
# path once picked up stale binaries and shipped the previous release's code.
build_arch() {
    local arch="$1" triple="$1-apple-macosx" bin linked_sdk
    swift build -c release --triple "$triple" $BUILD_SYSTEM
    bin="$(swift build -c release --triple "$triple" $BUILD_SYSTEM --show-bin-path)/$APP_NAME"
    if [ "$(lipo -archs "$bin")" != "$arch" ]; then
        echo "error: $bin is '$(lipo -archs "$bin")', expected $arch" >&2
        exit 1
    fi
    linked_sdk="$(otool -l "$bin" | awk '/LC_BUILD_VERSION/ {f=1} f && $1=="sdk" {print $2; exit}')"
    if [ "$linked_sdk" != "$SDK_VERSION" ]; then
        echo "error: $bin links SDK $linked_sdk, expected $SDK_VERSION" >&2
        exit 1
    fi
    cp "$bin" ".build/release-$arch-$APP_NAME"
}
build_arch arm64
build_arch x86_64
lipo -create \
    ".build/release-arm64-$APP_NAME" \
    ".build/release-x86_64-$APP_NAME" \
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
