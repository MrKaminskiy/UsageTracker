# UsageTracker

A native macOS menu bar app that tracks usage limits across AI services.

## Features

- Per-provider usage display in a popover
- Auto refresh with configurable interval and manual refresh
- Login launch and "hide not connected" settings
- Local-only config and keys, no external telemetry

## Supported providers

- Claude (Claude Code credentials in Keychain)
- Cursor (local Cursor DB + API)
- Codex (via `~/.codex/auth.json`)
- ElevenLabs (API key)
- Stability AI (API key)
- Runway (API key)
- OpenAI API (API key)

## Installation and run

Minimum version: macOS 14.

Xcode:

1. Open `Package.swift` in Xcode.
2. Select the `UsageTracker` scheme.
3. Run.

CLI:

```bash
swift build
```

## Settings and files

- General config: `~/.usagetracker/config.json`
- API keys: `~/.usagetracker/<provider>.json`
  - `elevenlabs.json`, `stability.json`, `runway.json`, `openai.json`
- Settings and keys can be configured in the Settings window

## Browser extension

The `Extension/` folder contains a browser extension that sends usage data to
`localhost:19284`. The receiver is implemented in `ExtensionServer`, but wiring
extension data into the main UI may need extra setup.

See `Extension/README.md` for installation.

## Development and tests

```bash
swift test
```

## Project structure (brief)

- `Sources/UsageTracker/` — app and UI
- `Sources/UsageTracker/Providers/` — providers and usage logic
- `Extension/` — browser extension
- `Tests/` — model tests

## Context7

1. Goal: quick overview of AI usage limits in the menu bar
2. Platform: macOS 14+, SwiftUI, SwiftPM
3. Data: local files, Keychain, API calls
4. Refresh: timer + manual refresh
5. Settings: interval, launch at login, provider toggles
6. Security: everything stays local
7. Extension: browser usage collection via localhost
