# Modern Settings UI

**Status:** Design complete, ready for implementation planning
**Date:** 2026-04-17

## Goal

Replace the current single-page `Form`-based Settings window with a modern,
tabbed layout that matches the visual quality of reference apps (NotchNook,
TypeWhisper, Shottr). Keep all existing functionality and configuration —
this is a presentation-layer rewrite, not a behavioral change.

## Non-goals

- Redesigning the menu-bar popover (`MenuBarView.swift`)
- Redesigning the onboarding flow
- Schema changes to `AppConfig`
- Adding a light/dark theme override (system appearance only)
- Snapshot testing infrastructure

## Decisions

Made during brainstorming, in order:

1. **Navigation paradigm:** Top toolbar tabs (NotchNook / native macOS
   Settings pre-Ventura). Not a sidebar (TypeWhisper-style) — keeps the
   window compact.
2. **Tab structure:** Five tabs — General, Providers, Display, Help, About.
   "How It Works" is promoted from a `NavigationLink` inside Settings to a
   top-level Help tab.
3. **Provider row pattern:** Disclosure rows. Compact by default; click a
   chevron to expand and reveal the API key field. Status dot shows
   connection state without expansion.
4. **Icon and chrome style:** Monochrome SF Symbols with an accent fill on
   the active tab. Not the colored-rounded-square treatment from System
   Settings — too busy when stacked with 8 provider rows.

## Window & Navigation

A single resizable `NSWindow` replaces the current `Form`-only Settings
scene.

- **Default size:** 560 × 600
- **Minimum size:** 480 × 540 (resizable)
- **Title bar:** `NSWindow.titleVisibility = .hidden`. Traffic lights
  overlap the toolbar area. The window's `title` is set to
  `"UsageTracker · <selected tab name>"` so it shows in Mission Control
  and the Window menu.
- **Toolbar:** Borderless, centered. Five icon-tab buttons.

| Icon (SF Symbol) | Label | Purpose |
|---|---|---|
| `gearshape` | General | Launch at login, refresh interval, onboarding reset |
| `bolt.horizontal.circle` | Providers | The 8 provider rows + drag-to-reorder |
| `eye` | Display | Hide-not-connected, cost estimate, menu-bar pinned item |
| `questionmark.circle` | Help | Inlined `HelpView` content |
| `info.circle` | About | Version, update check, links, quit |

Active tab: `accentColor`-filled rounded background. Inactive: monochrome
SF Symbol in `.secondary` label color. Keyboard shortcuts ⌘1–⌘5 select
tabs.

The selected tab persists across window close/reopen via `@AppStorage`.

## Tab content

### General

- **Toggle:** Launch at login (existing `SMAppService` wiring)
- **Stepper / Picker:** Refresh interval — choices: 1, 2, 5, 10, 15, 30
  minutes. Wires to `AppConfig.refreshIntervalMinutes` (currently never
  surfaced in UI).
- **Button:** "Show Onboarding Again" — sets
  `AppConfig.hasCompletedOnboarding = false` and triggers the onboarding
  window via `StatusBarController`.

### Providers

A single rounded `SettingsCard` containing the provider list with hairline
dividers between rows. Each row is a `ProviderDisclosureRow`.

**Row anatomy** (left to right):
`[drag handle] [icon] [name + status subtitle] [status dot] [toggle] [chevron]`

- **Drag handle** (`line.3.horizontal`): keeps existing drag-to-reorder
  via `ProviderDropDelegate`. No behavioral change to reordering.
- **Icon:** existing per-provider SF Symbol, rendered monochrome in
  `.secondary` color.
- **Name + subtitle:** subtitle reflects state:
  - `via Claude Code · auto-detected` (zero-config providers)
  - `Connected · monthly spend` / `Connected · daily usage` (configured)
  - `Not configured` (key required, none stored)
  - `Invalid key` (validation failed)
- **Status dot:** 6pt circle. Colors driven by
  `enum ConnectionStatus { case connected, idle, failed, disabled }`.
  Hidden when `disabled`.
- **Toggle:** existing enable/disable.
- **Chevron:** present only when the provider has a `keyConfig`. Click
  the row → animated expand showing the existing `APIKeyInput` component
  beneath, with a top divider and 12pt inset.

Auto-detected providers (Claude/Cursor/Codex) have no chevron — there is
nothing to expand.

Untested providers (Runway, Stability) get a subtle "Untested" capsule
pill next to the name when the row is expanded, matching the warning
already documented in CLAUDE.md.

The expand state is local to the view (not persisted) — defaults to
collapsed on window open.

### Display

Pulled out of the existing General section.

- **Toggle:** Hide not connected (existing)
- **Toggle:** Show API cost estimate (existing) — keeps the current
  fine-print description below
- **Picker:** "Menu bar shows…" — choices come from currently-pinned-
  eligible items across enabled providers, plus "Auto (highest %)" as the
  default. Wires to `AppConfig.pinnedItem`. Picker rebuilds its menu
  whenever the enabled-providers set or last-fetched usage items change.

### Help

The current `HelpView` content rendered directly as the tab body — no
`NavigationLink`, no back button, no `Form` / `NavigationStack` wrapper.
Three sections preserved: Auto-Detected, API Key Services, Tips. Help
icons go monochrome to match the new system.

### About

- App icon (64pt) + name + version + build, centered top
- Update banner (when `appState.updateChecker.updateAvailable` and a
  download URL exists): inline card with version and Download button.
  Logic unchanged.
- Links row: GitHub repo · Report issue · License
- "Quit UsageTracker" button at the bottom (matches the right-click menu
  option; gives Settings-only users a way out)

## File structure

Splitting the current ~400-line `SettingsView.swift` into focused files.
Shared components stay in `ProviderSettingsComponents.swift`.

```
Sources/UsageTracker/Views/
  Settings/
    SettingsWindow.swift          // NSWindow + toolbar host, manages selectedTab
    SettingsToolbar.swift         // The 5 icon-tab buttons + active styling
    Tabs/
      GeneralTab.swift            // Launch at login, refresh interval, reset onboarding
      ProvidersTab.swift          // Drag-reorder list of ProviderDisclosureRow
      DisplayTab.swift            // hide-not-connected, cost estimate, pinned item
      HelpTab.swift               // Inlined HelpView content
      AboutTab.swift              // Version, update check, links, quit
    Components/
      ProviderDisclosureRow.swift // The expand/collapse provider row
      StatusDot.swift             // 6pt color dot with state enum
      SettingsCard.swift          // Rounded grouped container w/ hairline rows
  ProviderSettingsComponents.swift // APIKeyInput, ProviderSettingsItem, ProviderDropDelegate (kept; lightly adapted)
```

**Files removed:**
- `SettingsView.swift` — replaced by `SettingsWindow.swift` plus the tabs
- `HelpView.swift` — content moves into `HelpTab.swift`

**Files lightly touched:**
- `StatusBarController.swift` — the existing settings-window opener now
  instantiates `SettingsWindow` instead of hosting `SettingsView` in an
  `NSHostingController`. Window lifecycle stays in
  `StatusBarController`.
- `ProviderSettingsComponents.swift` — `ProviderSettingsRow` is no longer
  used; `ProviderDisclosureRow` takes its place. `APIKeyInput`,
  `ProviderSettingsItem`, `ProviderKeyConfig`, and `ProviderDropDelegate`
  stay as-is.

**Files unchanged:**
- `Models.swift` — no schema changes; `refreshIntervalMinutes` and
  `pinnedItem` already exist
- All providers under `Sources/UsageTracker/Providers/`
- Keychain, update checker, refresh logic
- `MenuBarView.swift`, `OnboardingView.swift`

## Visual system

Centralized as static constants in `SettingsCard.swift` so all tabs share
identical spacing and colors.

| Token | Value |
|---|---|
| Window background | `Color(NSColor.windowBackgroundColor)` |
| Card background | `Color(NSColor.controlBackgroundColor)`, 10pt corner radius |
| Hairline divider | `Color.primary.opacity(0.08)`, 0.5pt |
| Row vertical padding | 10pt |
| Row horizontal padding | 14pt |
| Tab button | 32pt icon container, 6pt corner radius, accent fill when active |

Status dot colors derived from a single enum:

```swift
enum ConnectionStatus {
    case connected   // .green
    case idle        // .gray.opacity(0.5)
    case failed      // .red
    case disabled    // hidden
}
```

## Animation

- **Tab switch:** cross-fade 150ms (no slide — matches NotchNook)
- **Provider row expand:** `.easeInOut(duration: 0.18)` on height + opacity
  of the disclosure body
- **Toggle, drag, validation states:** existing SwiftUI defaults,
  unchanged

## Accessibility

- Each tab button: `accessibilityLabel("<name> settings")`,
  `accessibilityAddTraits(.isButton)`, selected state exposed via
  `.isSelected`
- Status dot: `accessibilityLabel("Status: connected" / "idle" /
  "failed")` so VoiceOver users get the same info as sighted users
- All toggles keep their existing labels
- Tab switching via ⌘1–⌘5 keyboard shortcut

## Testing

- New unit test file `Tests/UsageTrackerTests/SettingsViewModelTests.swift`
  covering:
  - Tab selection persists across window close/reopen
  - Refresh-interval picker writes to `AppConfig.refreshIntervalMinutes`
  - Status-dot derivation from provider state
  (Provider drag-reorder logic is already covered by existing tests
  against `AppConfig.providerOrder`.)
- No snapshot tests — UsageTracker doesn't use them today and we're not
  introducing the dependency for this change.

## Manual QA checklist (executed before merge)

- [ ] Drag-reorder providers persists across window reopen
- [ ] API key validation flow unchanged (debounce, ✓ / red border / Save
      button states)
- [ ] Expand/collapse animation feels right; expanded state resets on
      window reopen
- [ ] ⌘1–⌘5 select tabs; window title updates
- [ ] Dark mode parity — all five tabs
- [ ] Untested-provider pill appears for Runway/Stability when expanded
- [ ] "Show Onboarding Again" relaunches the onboarding window
- [ ] "Quit UsageTracker" in About terminates the app
- [ ] Existing keychain prompt for Claude credentials still works
- [ ] Refresh interval change takes effect on the next refresh tick

## Out of scope (explicit)

- `MenuBarView.swift`
- `OnboardingView.swift`
- `AppConfig` schema
- Light/dark theme toggle (system appearance only)
- Snapshot testing
