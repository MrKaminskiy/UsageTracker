# UsageTracker v1.0 — Distribution & Launch Plan

## Overview

Prepare UsageTracker for public distribution as a paid macOS menu bar app. Sell on Gumroad with a custom landing page to follow. Timeline: ~1.5 weeks.

**Pricing:** ~$9 regular, $3.99-$4.99 launch discount
**Distribution:** Gumroad (DMG download), no Mac App Store
**License/DRM:** None — trust-based at this price point

---

## 1. App Packaging & Distribution

### 1.1 App Bundle Structure

Create a proper macOS .app bundle (currently builds as a raw executable via SwiftPM).

- **Bundle identifier:** Use your Apple Developer team's reverse-domain (e.g. `com.yourname.usagetracker`)
- **Info.plist:** CFBundleName, CFBundleVersion (1.0.0), CFBundleShortVersionString, LSUIElement=true (menu bar app), minimum macOS version
- **App icon:** .icns file in the bundle. Options: AI-generated, self-designed, or Fiverr ($20-50)
- **Entitlements:** Network access, Keychain access

### 1.2 Code Signing & Notarization

Using the existing Apple Developer account:

- Sign with Developer ID Application certificate
- Submit to Apple notarization service
- Staple the notarization ticket to the app

### 1.3 DMG Packaging

- Create a DMG with drag-to-Applications background image
- App icon on left, Applications folder alias on right
- Compressed DMG for smaller download

### 1.4 Build Automation

Single `make release` command that:

1. Builds the app in Release configuration
2. Creates the .app bundle with proper structure
3. Code signs the bundle
4. Submits for notarization and waits
5. Staples the ticket
6. Creates the DMG
7. Signs the DMG

---

## 2. Polish Pass

### 2.1 Must Fix

- **Bar width consistency** — DONE. Reset label column now always reserves space even when empty.
- **User-friendly error messages** — Replace raw HTTP status codes with human-readable messages ("API key expired", "Connection failed, retrying...")
- **Offline handling** — Graceful behavior when network is unavailable; show last cached data with "offline" indicator
- **Split SettingsView** — 770 lines is too large; break into sub-components (ProviderSettings, AppearanceSettings, AboutSection)

### 2.2 Should Fix

- **Update checker** — On launch, check GitHub releases (or a simple JSON file) for newer version. Show badge in Settings if update available. No auto-install, just link to download.
- **Version number in Settings** — Display current version in the Settings window
- **About window** — Version, credits, support email/link
- **Verify onboarding flow** — Test first-launch experience end-to-end from a clean state

### 2.3 Explicitly Out of Scope for v1.0

- License keys / DRM — not worth the complexity at $5
- Analytics / telemetry — privacy-first is a selling point
- Auto-update installation — notify only
- Browser extension — not ready, ship without
- Mac App Store — maybe later

---

## 3. Sales & Landing Page

### 3.1 Gumroad Product Page (Launch Day)

- **Product name:** UsageTracker for Mac
- **Price:** ~$9 with launch discount to $3.99-$4.99
- **Assets needed:**
  - 2-3 polished screenshots (the viral screenshot is already compelling)
  - Short product description: what it tracks, which services supported
  - System requirements: macOS 13+
- **Deliverable:** Signed, notarized DMG

### 3.2 Custom Landing Page (Shortly After Launch)

- Single-page static site
- Hero section with screenshot, tagline, "Buy on Gumroad" CTA
- Feature list with provider icons
- Hosted on Vercel or Netlify (free tier)
- Domain: `usagetracker.app` or similar

### 3.3 Launch Channels

In order of priority (leverage existing proof of demand):

1. Same channels where the screenshot went viral
2. Twitter/X with short demo GIF
3. r/macapps, r/ChatGPT, r/ClaudeAI
4. Product Hunt
5. Hacker News (Show HN)

### 3.4 Support

- Support email on the Gumroad page
- Consider a simple public GitHub Issues repo (separate from source code)

---

## 4. Implementation Order

1. **App icon** — need this before anything else visual
2. **Polish pass** (error messages, offline handling, SettingsView split, about/version)
3. **App bundle + signing + notarization + DMG** (build script)
4. **Update checker**
5. **Screenshots & marketing copy**
6. **Gumroad product page**
7. **Launch**
8. **Landing page** (can come after launch)
