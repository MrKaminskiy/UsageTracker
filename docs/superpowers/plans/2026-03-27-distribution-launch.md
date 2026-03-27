# UsageTracker v1.0 Distribution & Launch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare UsageTracker for paid distribution as a signed, notarized macOS app sold on Gumroad.

**Architecture:** The app already works as a SwiftPM executable. We need to: (1) polish rough edges in code, (2) create a proper .app bundle with signing/notarization, (3) automate the release pipeline via Makefile, (4) add an update checker. No new dependencies.

**Tech Stack:** Swift 6, SwiftUI, AppKit, SwiftPM, codesign, notarytool, hdiutil

---

## File Structure

### New files
- `Sources/UsageTracker/UpdateChecker.swift` — checks a remote JSON file for newer versions
- `scripts/release.sh` — builds, bundles, signs, notarizes, and creates DMG
- `scripts/dmg-background.png` — drag-to-Applications background image (created manually or with a tool)
- `Info.plist` — app bundle metadata (LSUIElement, version, bundle ID)
- `AppIcon.icns` — app icon (created externally)

### Modified files
- `Sources/UsageTracker/Models.swift` — add `httpErrorMessage()` helper
- `Sources/UsageTracker/Providers/*.swift` — replace `"HTTP \(statusCode)"` with user-friendly messages
- `Sources/UsageTracker/Views/SettingsView.swift` — extract sub-views, add update badge
- `Sources/UsageTracker/App.swift` — add update checker init, offline-aware refresh
- `Makefile` — add `release` target

---

## Task 1: User-Friendly Error Messages

**Files:**
- Modify: `Sources/UsageTracker/Models.swift`
- Modify: `Sources/UsageTracker/Providers/ElevenLabsProvider.swift`
- Modify: `Sources/UsageTracker/Providers/StabilityProvider.swift`
- Modify: `Sources/UsageTracker/Providers/RunwayProvider.swift`
- Modify: `Sources/UsageTracker/Providers/ClaudeProvider.swift`
- Modify: `Sources/UsageTracker/Providers/CursorProvider.swift`
- Modify: `Sources/UsageTracker/Providers/CodexProvider.swift`
- Modify: `Sources/UsageTracker/Providers/OpenAIProvider.swift`
- Modify: `Sources/UsageTracker/Providers/OpenRouterProvider.swift`

- [ ] **Step 1: Add HTTP error message helper to Models.swift**

Add after the `ProviderStatus` enum:

```swift
/// Maps HTTP status codes to user-friendly error messages.
func httpErrorMessage(_ statusCode: Int) -> String {
    switch statusCode {
    case 401: return "Invalid API key"
    case 403: return "Access denied"
    case 429: return "Rate limited"
    case 500...599: return "Service unavailable"
    default: return "Error (\(statusCode))"
    }
}
```

- [ ] **Step 2: Replace all `"HTTP \(statusCode)"` in providers**

In each provider file, replace `.error("HTTP \(httpResponse.statusCode)")` with `.error(httpErrorMessage(httpResponse.statusCode))`.

Files to update (each has 1 occurrence unless noted):
- `ElevenLabsProvider.swift:81`
- `StabilityProvider.swift:72`
- `RunwayProvider.swift:78`
- `ClaudeProvider.swift:118`
- `CursorProvider.swift:96`
- `CodexProvider.swift:132`
- `OpenAIProvider.swift:137` and `:188` (2 occurrences)
- `OpenRouterProvider.swift:140`

- [ ] **Step 3: Build and verify**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/UsageTracker/Models.swift Sources/UsageTracker/Providers/
git commit -m "fix: replace raw HTTP status codes with user-friendly error messages"
```

---

## Task 2: Offline / Network Error Handling

**Files:**
- Modify: `Sources/UsageTracker/App.swift`

Currently, when a provider fetch throws (network error), it's silently swallowed by `try?`. The provider just disappears from the list. Instead, preserve the last known data and show an error state.

- [ ] **Step 1: Add a catch block to preserve last provider data on error**

In `App.swift`, in the `refresh()` method, after building `newProviders`, before assigning to `providers`:

```swift
// Preserve last-known data for providers that failed to fetch
for existingProvider in providers {
    if !newProviders.contains(where: { $0.id == existingProvider.id }) {
        // Provider was in previous state but missing now — keep it with error status
        var preserved = existingProvider
        preserved.status = .error("Offline")
        newProviders.append(preserved)
    }
}
```

Add this block right before the `// Strip cost estimates if disabled` comment.

- [ ] **Step 2: Build and verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageTracker/App.swift
git commit -m "fix: preserve last-known provider data when network is unavailable"
```

---

## Task 3: Split SettingsView

**Files:**
- Modify: `Sources/UsageTracker/Views/SettingsView.swift`

The file is 770+ lines. The sub-views (`APIKeyInput`, `ProviderToggle`, `ProviderSettingsRow`, `ProviderSettingsItem`, `ProviderKeyConfig`, `ProviderDropDelegate`, `HelpView`, `HelpRow`) are already well-defined structs. Extract them into their own files.

- [ ] **Step 1: Create `Sources/UsageTracker/Views/ProviderSettingsComponents.swift`**

Move these structs from SettingsView.swift into the new file:
- `KeyValidationState` (enum, line ~398)
- `APIKeyInput` (struct, line ~406)
- `ProviderToggle` (struct, line ~528)
- `ProviderSettingsRow` (struct, line ~567)
- `ProviderSettingsItem` (struct, line ~600)
- `ProviderKeyConfig` (struct, line ~609)
- `ProviderDropDelegate` (struct, line ~620)

Add `import SwiftUI` and `import AppKit` at the top.

- [ ] **Step 2: Create `Sources/UsageTracker/Views/HelpView.swift`**

Move these structs from SettingsView.swift into the new file:
- `HelpView` (struct, line ~654)
- `HelpRow` (struct, line ~758)

Add `import SwiftUI` at the top.

- [ ] **Step 3: Remove moved code from SettingsView.swift**

Delete everything from `/// Validation state for API keys` (line ~397) to end of file, keeping only the `SettingsView` struct and its private methods.

- [ ] **Step 4: Build and verify**

Run: `swift build`
Expected: Build succeeds. All types are still accessible since they're in the same module.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageTracker/Views/
git commit -m "refactor: extract SettingsView sub-components into separate files"
```

---

## Task 4: Update Checker

**Files:**
- Create: `Sources/UsageTracker/UpdateChecker.swift`
- Modify: `Sources/UsageTracker/App.swift`
- Modify: `Sources/UsageTracker/Views/SettingsView.swift`

The update checker fetches a JSON file from a URL you control (e.g., hosted on your landing page or a GitHub Gist). Format:

```json
{"version": "1.1.0", "url": "https://yoursite.com/download"}
```

- [ ] **Step 1: Create UpdateChecker.swift**

```swift
import Foundation

@MainActor
class UpdateChecker: ObservableObject {
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String?
    @Published var downloadURL: URL?

    /// URL to a JSON file with {"version": "x.y.z", "url": "https://..."}
    private let feedURL: URL?

    init(feedURL: String = "https://usagetracker.app/version.json") {
        self.feedURL = URL(string: feedURL)
    }

    func check() async {
        guard let feedURL else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            guard let info = try? JSONDecoder().decode(VersionInfo.self, from: data) else { return }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            if info.version.compare(currentVersion, options: .numeric) == .orderedDescending {
                updateAvailable = true
                latestVersion = info.version
                downloadURL = URL(string: info.url)
            }
        } catch {
            // Silently fail — update check is best-effort
        }
    }

    private struct VersionInfo: Decodable {
        let version: String
        let url: String
    }
}
```

- [ ] **Step 2: Add UpdateChecker to AppState**

In `App.swift`, add a property to `AppState`:

```swift
let updateChecker = UpdateChecker()
```

In the `refresh()` method, after the existing refresh logic, add:

```swift
await updateChecker.check()
```

- [ ] **Step 3: Show update badge in Settings**

In `SettingsView.swift`, in the "About" section, add an update row:

```swift
Section("About") {
    if appState.updateChecker.updateAvailable,
       let version = appState.updateChecker.latestVersion,
       let url = appState.updateChecker.downloadURL {
        HStack {
            Label("Update available: v\(version)", systemImage: "arrow.down.circle.fill")
                .foregroundColor(.blue)
            Spacer()
            Link("Download", destination: url)
                .font(.system(size: 11))
        }
    }

    NavigationLink {
        HelpView()
    } label: {
        Label("How It Works", systemImage: "questionmark.circle")
    }
}
```

- [ ] **Step 4: Build and verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageTracker/UpdateChecker.swift Sources/UsageTracker/App.swift Sources/UsageTracker/Views/SettingsView.swift
git commit -m "feat: add update checker with badge in Settings"
```

---

## Task 5: App Bundle & Info.plist

**Files:**
- Create: `Info.plist` (project root)
- Modify: `Makefile`

SwiftPM builds a raw executable. To distribute as a macOS app, we need a build script that creates the `.app` bundle structure manually.

- [ ] **Step 1: Create Info.plist**

Create `Info.plist` in the project root:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>UsageTracker</string>
    <key>CFBundleDisplayName</key>
    <string>UsageTracker</string>
    <key>CFBundleIdentifier</key>
    <string>com.CHANGEME.usagetracker</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>UsageTracker</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

**Important:** Replace `com.CHANGEME.usagetracker` with your actual Apple Developer reverse-domain bundle ID.

- [ ] **Step 2: Commit**

```bash
git add Info.plist
git commit -m "feat: add Info.plist for app bundle"
```

---

## Task 6: Release Build Script

**Files:**
- Create: `scripts/release.sh`
- Modify: `Makefile`

- [ ] **Step 1: Create `scripts/release.sh`**

```bash
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
```

- [ ] **Step 2: Create Entitlements.plist**

Create `Entitlements.plist` in project root:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 3: Make script executable and add Makefile target**

```bash
chmod +x scripts/release.sh
```

Add to Makefile:

```makefile
release:
	./scripts/release.sh
```

- [ ] **Step 4: Commit**

```bash
git add scripts/release.sh Entitlements.plist Makefile
git commit -m "feat: add release build script with signing, notarization, and DMG creation"
```

---

## Task 7: App Icon

This is a **manual task** — not automatable in code.

- [ ] **Step 1: Create or obtain an app icon**

Options:
- Use an AI image generator (Midjourney, DALL-E) to create a menu bar utility icon
- Commission on Fiverr ($20-50)
- Design in Figma/Sketch

The icon should work at small sizes (16x16 for menu bar) and large (512x512 for About/DMG).

- [ ] **Step 2: Generate .icns file**

Use `iconutil` to convert from a `.iconset` directory:

```bash
mkdir AppIcon.iconset
# Place icon_16x16.png, icon_16x16@2x.png, icon_32x32.png, icon_32x32@2x.png,
# icon_128x128.png, icon_128x128@2x.png, icon_256x256.png, icon_256x256@2x.png,
# icon_512x512.png, icon_512x512@2x.png in the directory
iconutil -c icns AppIcon.iconset -o AppIcon.icns
```

- [ ] **Step 3: Commit**

```bash
git add AppIcon.icns
git commit -m "feat: add app icon"
```

---

## Task 8: Final Verification & Test Release

- [ ] **Step 1: Clean build from scratch**

```bash
swift package clean && swift build
```

Expected: Build succeeds with no warnings.

- [ ] **Step 2: Run tests**

```bash
swift test
```

Expected: All tests pass.

- [ ] **Step 3: Test first-launch experience**

```bash
# Back up existing config
mv ~/.usagetracker ~/.usagetracker.bak

# Run the app
.build/debug/UsageTracker

# Verify:
# - Onboarding appears on first launch
# - Cost estimate is NOT shown (off by default)
# - Providers with no config show as "Not connected"
# - Settings opens and all toggles work

# Restore config
rm -rf ~/.usagetracker && mv ~/.usagetracker.bak ~/.usagetracker
```

- [ ] **Step 4: Test release build (requires signing creds)**

```bash
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export TEAM_ID="TEAMID"
export APPLE_ID="your@email.com"
export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
make release
```

Expected: DMG created in `build/UsageTracker.dmg`.

- [ ] **Step 5: Verify the DMG**

```bash
open build/UsageTracker.dmg
# Drag app to Applications, launch it, verify it works
# Check: spctl --assess -v build/UsageTracker.app
# Expected: "accepted" (notarized)
```

---

## Task 9: Gumroad Setup (Manual)

Not a code task — checklist for launch day:

- [ ] **Step 1:** Create Gumroad account if needed
- [ ] **Step 2:** Create product "UsageTracker for Mac"
- [ ] **Step 3:** Set price to ~$9, create launch discount code for $3.99-$4.99
- [ ] **Step 4:** Upload DMG as the deliverable
- [ ] **Step 5:** Write product description:
  - What it does (menu bar AI usage tracker)
  - Which services (Claude, Cursor, Codex, OpenAI, OpenRouter, ElevenLabs, Stability, Runway)
  - System requirements (macOS 13+)
  - 2-3 screenshots
- [ ] **Step 6:** Add cover image (screenshot or icon)
- [ ] **Step 7:** Publish and share link

---

## Task 10: Landing Page (Post-Launch)

- [ ] **Step 1:** Register domain (usagetracker.app or similar)
- [ ] **Step 2:** Create a single-page static site with:
  - Hero section: screenshot + tagline + "Buy on Gumroad" CTA
  - Feature list with provider icons
  - Price badge
- [ ] **Step 3:** Deploy to Vercel or Netlify (free tier)
- [ ] **Step 4:** Host `version.json` on the domain for the update checker:
  ```json
  {"version": "1.0.0", "url": "https://gumroad.com/l/your-product"}
  ```
- [ ] **Step 5:** Update the `UpdateChecker` feedURL to point to your domain
