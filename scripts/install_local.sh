#!/bin/bash
# Build a Developer-ID-signed app bundle and install it to /Applications for
# local use on this Mac. No notarization (not needed for a locally-built app —
# there is no com.apple.quarantine attribute, so Gatekeeper does not block it).
# For a distributable notarized DMG, use scripts/release.sh instead.
set -euo pipefail

APP_NAME="UsageTracker"
BUNDLE_DIR="build/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"
IDENTITY="${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to your Developer ID Application certificate name}"
BIN=".build/release/${APP_NAME}"

[ -x "$BIN" ] || { echo "error: $BIN not found — run 'swift build -c release' first"; exit 1; }

echo "==> Assembling app bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources"
cp "$BIN" "$BUNDLE_DIR/Contents/MacOS/${APP_NAME}"
cp Info.plist "$BUNDLE_DIR/Contents/"
cp AppIcon.icns "$BUNDLE_DIR/Contents/Resources/"

echo "==> Signing with: $IDENTITY"
codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" --entitlements Entitlements.plist "$BUNDLE_DIR"
codesign --verify --strict --verbose=2 "$BUNDLE_DIR"

echo "==> Stopping any running instance..."
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1

echo "==> Installing to ${DEST}..."
rm -rf "$DEST"
cp -R "$BUNDLE_DIR" "$DEST"

echo "==> Launching..."
open "$DEST"

echo "==> Installed:"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DEST/Contents/Info.plist"
