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

## Provider Status

| Provider | Auth | What it shows | Status |
|----------|------|---------------|--------|
| Claude | OAuth (keychain, auto) | Session %, Weekly %, Sonnet %, Opus %, cost estimate | Tested |
| Cursor | Local DB (auto) | Usage % | Tested |
| Codex | `~/.codex/auth.json` (auto) | Usage % | Tested |
| OpenAI | API key (`sk-admin-*` or `sk-proj-*`) | Admin: monthly spend; Project: daily requests + tokens | Experimental |
| ElevenLabs | API key | Character quota % with reset time | Experimental |
| OpenRouter | API key | Credits used % or monthly/daily spend | Experimental |
| Runway | API key | Credit balance | **Untested — hidden by default** |
| Stability | API key | Credit balance | **Untested — hidden by default** |

## Definition of Done (pre-public release)

- [ ] `swift test` passes with all new integration tests
- [ ] Session % and Weekly % display correctly for a logged-in Claude account
- [ ] Cost estimate shows for current month (requires `~/.claude/projects/` with .jsonl files)
- [ ] Cursor and Codex auto-detect on a machine where they're installed
- [ ] OpenAI, ElevenLabs, OpenRouter: verified working with real keys
- [ ] Runway and Stability are hidden by default
- [ ] Default refresh interval is 5 minutes
- [ ] `make release` completes without errors from a clean build
- [ ] App signed and notarized (DMG produced)
- [ ] README complete with all sections

## Known Issues

- **Keychain password prompt**: The app reads Claude Code CLI's keychain credentials (`"Claude Code-credentials"`). macOS may prompt for permission. Clicking "Always Allow" persists for the life of the signed app identity. Fixed permanently by code signing (users never see it again after first launch).
- **Runway / Stability**: Providers are implemented but untested. Hidden by default. Enable in Settings at your own risk.

## Releasing

Required env vars (set in your shell before running `make release`):

```bash
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export TEAM_ID="YOURTEAMID"
export APPLE_ID="you@example.com"
export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # App-specific password from appleid.apple.com
```

Release steps:
1. `make test` — all tests must pass
2. `make release` — builds, signs, notarizes, produces `build/UsageTracker.dmg`
3. `git tag vX.Y.Z && git push --tags`
4. Create GitHub Release, attach `build/UsageTracker.dmg`
