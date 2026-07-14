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
- **ClaudeProvider** - Reads OAuth credentials from macOS Keychain (`Claude Code-credentials`), falling back to `~/.claude/.credentials.json` for newer Claude Code CLI versions; calls `api.anthropic.com/api/oauth/usage`
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
- `Providers/ClaudeInsightsAnalyzer.swift` - Incremental transcript analysis: monthly cost + 24h usage insights (replaces ClaudeCostEstimator)
- `Views/ClaudeDetailView.swift` - Claude drill-in page: limit bars, insights, skills/agents breakdown, today stats

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
- Claude detail page: extra-usage credits, 24h insights (context size, subagent share), top skills/agents, today stats

## Provider Status

| Provider | Auth | What it shows | Status |
|----------|------|---------------|--------|
| Claude | OAuth (keychain, auto) | Session %, Weekly %, Sonnet %, Opus %, extra credits, cost estimate, usage insights | Tested |
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

Notarization credentials are stored once in the Keychain via `notarytool`, not passed as env vars:

```bash
xcrun notarytool store-credentials "usagetracker-release" \
  --apple-id "you@example.com" \
  --team-id "YOURTEAMID"
# prompts for an app-specific password from appleid.apple.com
```

`scripts/release.sh` uses that profile by default (override with `NOTARY_PROFILE`). Only the signing identity is still a required env var:

```bash
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

Release steps:
1. `make test` — all tests must pass
2. `make release` — builds, signs, notarizes, produces `build/UsageTracker.dmg`
3. `git tag vX.Y.Z && git push --tags`
4. Create GitHub Release, attach `build/UsageTracker.dmg`
