# UsageTracker

macOS menu bar app for tracking AI service usage limits.

## Tech Stack
- Swift, SwiftUI, AppKit
- Swift Package Manager
- macOS 13+

## Build & Run
```bash
swift build
.build/debug/UsageTracker
```

## Architecture

### Providers
Located in `Sources/UsageTracker/Providers/`. Each provider fetches usage from a service:
- **ClaudeProvider** - Reads from `~/.claude/statsig_cache/` (auto-detected)
- **CursorProvider** - Reads from Cursor app cache (auto-detected)
- **CodexProvider** - Reads from `~/.codex/` (auto-detected)
- **OpenAIProvider** - Uses admin API key (`sk-admin-*`) for org spend, or project key for daily usage
- **ElevenLabsProvider** - API key required
- **StabilityProvider** - API key required
- **RunwayProvider** - API key required

### Key Files
- `App.swift` - AppDelegate, AppState (main state management)
- `StatusBarController.swift` - Menu bar icon, popover, context menu, settings/onboarding windows
- `Models.swift` - Provider, UsageItem, AppConfig
- `Views/MenuBarView.swift` - Main popover content
- `Views/ProviderRow.swift` - Individual provider display with usage bars
- `Views/SettingsView.swift` - Settings with provider toggles, API keys, drag-to-reorder
- `Views/OnboardingView.swift` - First-launch welcome screen

### Config
User config stored in `~/.usagetracker/`:
- `config.json` - App settings (provider order, enabled providers, hide not connected)
- `openai.json`, `elevenlabs.json`, etc. - API keys per provider

## Features
- Left-click menu bar icon: Show usage popover
- Right-click menu bar icon: Settings, Clear Cache, Quit
- Green dot indicator: Shows which usage item is displayed in menu bar
- Drag-to-reorder providers in Settings
- Live API key validation
- "How It Works" help page in Settings
- Onboarding on first launch
