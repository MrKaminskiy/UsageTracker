# UsageTracker Design

A native SwiftUI menu bar app for tracking AI coding tool usage with a JavaScript plugin system.

## Goals

- Lightweight, native macOS menu bar app
- Visual progress bars for usage quotas
- Automatic fetching from provider APIs/local data
- Periodic refresh (15-30 min) + on-demand
- Plugin system for adding providers

## Architecture

```
┌─────────────────────────────────────────┐
│  Menu Bar Icon (shows worst %)          │
├─────────────────────────────────────────┤
│ ▼ Claude                                │
│    Session     ██░░░░░░░░  2%   4h 37m  │
│    All models  █████░░░░░  27%  19h 37m │
│    Weekly      █░░░░░░░░░  8%   Wed 2PM │
├─────────────────────────────────────────┤
│ ▶ Cursor       ████░░░░░░  40%          │
│ ▶ Codex        ███░░░░░░░  30%          │
├─────────────────────────────────────────┤
│  ↻ Refresh    ⚙ Settings    ✕ Quit     │
└─────────────────────────────────────────┘
```

**Components:**

- **App Shell** - SwiftUI menu bar app
- **Plugin Engine** - JavaScriptCore (built into macOS) runs provider plugins
- **Scheduler** - Timer for periodic refresh (configurable 15/30/60 min)
- **Plugins folder** - `~/.usagetracker/plugins/` contains JS files

## Plugin System

Each provider is a single JavaScript file in `~/.usagetracker/plugins/`.

### Plugin API

```javascript
// ~/.usagetracker/plugins/claude.js
module.exports = {
  name: "Claude",
  icon: "brain",  // SF Symbol name

  async probe() {
    // Returns array of usage items (or single item)
    return [
      {
        label: "Current session",
        current: 2,
        limit: 100,
        resetLabel: "4 hr 37 min"
      },
      {
        label: "All models",
        current: 27,
        limit: 100,
        resetLabel: "19 hr 37 min"
      },
      {
        label: "Weekly",
        current: 8,
        limit: 100,
        resetLabel: "Wed 2:00 PM"
      }
    ]
  }
}
```

### Built-in Helpers

Exposed to plugins:

- `fetch(url, options)` - HTTP requests
- `readFile(path)` - Read local files (SQLite dbs, config files)
- `env(name)` - Access environment variables
- `log(message)` - Debug logging

### Plugin Loading

- App scans `~/.usagetracker/plugins/*.js` on startup
- Each plugin runs in isolated JavaScriptCore context
- Failed plugins show error state, don't crash the app

## Data Flow

### Startup

1. App loads all plugins from `~/.usagetracker/plugins/`
2. Runs `probe()` on each plugin in parallel
3. Renders results in menu bar popover
4. Menu bar icon shows the highest usage % across all providers

### Periodic Refresh

- Timer fires every N minutes (default 15, configurable)
- Re-runs all `probe()` functions
- Updates UI with new values
- Stores last-fetched timestamp

### On-demand Refresh

- Click "↻ Refresh" or keyboard shortcut
- Immediate re-probe of all plugins
- Shows spinner while fetching

### Error Handling

- Plugin timeout: 10 seconds max per probe
- Network failure: Shows "⚠ Offline" with last known value
- Plugin crash: Shows "⚠ Error" for that provider, others continue

## Storage

- `~/.usagetracker/config.json` - Settings (refresh interval, etc.)
- `~/.usagetracker/plugins/` - Plugin files
- No database needed - data is fetched fresh each time

## UI Details

### Menu Bar Icon

- Shows highest usage % as a small radial progress indicator
- Color shifts: green (<50%) → yellow (50-80%) → red (>80%)

### Popover View

- Clean list of providers with progress bars
- Providers with multiple bars are collapsible (▼/▶)
- Each row: label, progress bar, percentage, reset time
- Clicking provider header opens dashboard in browser (optional)

### Settings

- Refresh interval: 15 / 30 / 60 minutes
- Launch at login: toggle
- Plugins folder: button to open in Finder

## File Structure

```
UsageTracker/
├── UsageTracker.xcodeproj
├── UsageTracker/
│   ├── App.swift              # Entry point, menu bar setup
│   ├── PluginEngine.swift     # JavaScriptCore wrapper
│   ├── Models.swift           # Provider, UsageData structs
│   ├── Views/
│   │   ├── MenuBarView.swift  # Main popover
│   │   ├── ProviderRow.swift  # Single provider row
│   │   └── SettingsView.swift
│   └── Resources/
│       └── DefaultPlugins/    # Bundled starter plugins
└── README.md
```

## Initial Providers

Ship with example plugins for:

1. **Claude** - Session, all models, weekly limits (requires auth cookie or scraping)
2. **Cursor** - Plan usage (local SQLite or API)
3. **Codex** - Session and weekly limits
