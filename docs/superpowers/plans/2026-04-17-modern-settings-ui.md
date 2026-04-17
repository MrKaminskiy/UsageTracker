# Modern Settings UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current `Form`-based Settings window with a tabbed window (General · Providers · Display · Help · About) using monochrome SF Symbol toolbar tabs and disclosure rows for providers.

**Architecture:** A single SwiftUI `SettingsContent` root view contains a custom top tab bar (`SettingsToolbar`) and a body region that swaps between five tab views. The root view is hosted in an `NSWindow` configured with hidden title bar and full-size content view, instantiated by the existing `SettingsWindowController` in `StatusBarController.swift`. No `AppConfig` schema changes; all new UI binds to existing `AppState` mutators. A new `ConnectionStatus` enum derives connection-dot color from `ProviderStatus`. The standalone `Settings { ... }` Scene in `App.swift` is removed so there is exactly one settings-window code path.

**Tech Stack:** Swift 5.9+, SwiftUI (macOS 13+), AppKit (`NSWindow`, `NSHostingController`), Swift Testing framework (`@Suite` / `@Test` / `#expect`), Swift Package Manager.

---

## Spec Reference

This plan implements `docs/superpowers/specs/2026-04-17-modern-settings-ui-design.md`. Read it before starting if anything below is ambiguous.

## File Map

**Created:**
- `Sources/UsageTracker/Views/Settings/SettingsDesign.swift` — `SettingsTabKind` enum, `ConnectionStatus` enum, `SettingsDesign` tokens
- `Sources/UsageTracker/Views/Settings/Components/StatusDot.swift` — 6pt connection-status dot
- `Sources/UsageTracker/Views/Settings/Components/SettingsCard.swift` — rounded grouped container with hairline-divided rows
- `Sources/UsageTracker/Views/Settings/Components/ProviderDisclosureRow.swift` — expandable provider row
- `Sources/UsageTracker/Views/Settings/SettingsToolbar.swift` — top tab bar
- `Sources/UsageTracker/Views/Settings/SettingsContent.swift` — root view (toolbar + selected tab body)
- `Sources/UsageTracker/Views/Settings/Tabs/GeneralTab.swift`
- `Sources/UsageTracker/Views/Settings/Tabs/ProvidersTab.swift`
- `Sources/UsageTracker/Views/Settings/Tabs/DisplayTab.swift`
- `Sources/UsageTracker/Views/Settings/Tabs/HelpTab.swift`
- `Sources/UsageTracker/Views/Settings/Tabs/AboutTab.swift`
- `Tests/UsageTrackerTests/SettingsViewModelTests.swift`

**Modified:**
- `Sources/UsageTracker/StatusBarController.swift` — `SettingsWindowController.showSettings()` hosts `SettingsContent` and configures hidden title bar; observes new `.showOnboarding` notification; sets new default size 560×600
- `Sources/UsageTracker/App.swift` — removes `Settings { SettingsView(...) }` scene
- `Sources/UsageTracker/Views/ProviderSettingsComponents.swift` — removes the now-unused `ProviderSettingsRow` and `ProviderToggle` views (keeps `APIKeyInput`, `ProviderSettingsItem`, `ProviderKeyConfig`, `ProviderDropDelegate`)

**Deleted:**
- `Sources/UsageTracker/Views/SettingsView.swift`
- `Sources/UsageTracker/Views/HelpView.swift`

## TDD Strategy

SwiftUI views are not directly testable without snapshot infra (out of scope per spec). The plan uses TDD for the testable pure logic:
- `ConnectionStatus.from(providerStatus:enabled:)` — pure
- `pinnedSelection` round-trip with `AppConfig.pinnedItem` — pure
- Existing `AppState.updateRefreshInterval(_:)` — already exists, add a test
- `SettingsTabKind.persistedTab` round-trip via `@AppStorage` — small helper

UI components (rows, tabs, toolbar) are built without tests but verified via `swift build` and the manual QA checklist at the end.

---

## Task 1: Foundation — `SettingsDesign.swift` (enums + tokens)

**Files:**
- Create: `Sources/UsageTracker/Views/Settings/SettingsDesign.swift`
- Test: `Tests/UsageTrackerTests/SettingsViewModelTests.swift` (created here, expanded later)

- [ ] **Step 1: Write failing test for `ConnectionStatus.from(...)`**

Create the test file:

```swift
// Tests/UsageTrackerTests/SettingsViewModelTests.swift
import Foundation
import Testing
@testable import UsageTracker

@Suite("ConnectionStatus")
struct ConnectionStatusTests {

    @Test("Disabled provider yields .disabled regardless of status")
    func disabled() {
        let status = ConnectionStatus.from(providerStatus: .loaded, enabled: false)
        #expect(status == .disabled)
    }

    @Test("Loaded + enabled yields .connected")
    func connected() {
        let status = ConnectionStatus.from(providerStatus: .loaded, enabled: true)
        #expect(status == .connected)
    }

    @Test("Loading + enabled yields .idle")
    func loadingIsIdle() {
        let status = ConnectionStatus.from(providerStatus: .loading, enabled: true)
        #expect(status == .idle)
    }

    @Test("notConnected + enabled yields .idle")
    func notConnectedIsIdle() {
        let url = URL(string: "https://example.com")!
        let status = ConnectionStatus.from(providerStatus: .notConnected(url: url), enabled: true)
        #expect(status == .idle)
    }

    @Test("Error + enabled yields .failed")
    func errorIsFailed() {
        let status = ConnectionStatus.from(providerStatus: .error("boom"), enabled: true)
        #expect(status == .failed)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConnectionStatusTests`
Expected: FAIL with "cannot find 'ConnectionStatus' in scope"

- [ ] **Step 3: Create `SettingsDesign.swift`**

```swift
// Sources/UsageTracker/Views/Settings/SettingsDesign.swift
import SwiftUI

/// Connection status for a provider, used to drive the row status dot.
enum ConnectionStatus: Equatable {
    case connected   // Loaded with data
    case idle        // Loading or no auth yet
    case failed      // Error fetching
    case disabled    // Toggled off — dot hidden

    static func from(providerStatus: ProviderStatus, enabled: Bool) -> ConnectionStatus {
        guard enabled else { return .disabled }
        switch providerStatus {
        case .loaded: return .connected
        case .loading: return .idle
        case .notConnected: return .idle
        case .error: return .failed
        }
    }

    var color: Color? {
        switch self {
        case .connected: return .green
        case .idle: return .gray.opacity(0.5)
        case .failed: return .red
        case .disabled: return nil
        }
    }

    var voiceOverLabel: String {
        switch self {
        case .connected: return "Status: connected"
        case .idle: return "Status: idle"
        case .failed: return "Status: failed"
        case .disabled: return "Status: disabled"
        }
    }
}

/// The five tabs in the Settings window, in display order.
enum SettingsTabKind: String, CaseIterable, Identifiable {
    case general
    case providers
    case display
    case help
    case about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .providers: return "Providers"
        case .display: return "Display"
        case .help: return "Help"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .providers: return "bolt.horizontal.circle"
        case .display: return "eye"
        case .help: return "questionmark.circle"
        case .about: return "info.circle"
        }
    }

    /// Keyboard shortcut character: "1"..."5".
    var shortcut: Character {
        switch self {
        case .general: return "1"
        case .providers: return "2"
        case .display: return "3"
        case .help: return "4"
        case .about: return "5"
        }
    }
}

/// Shared layout/style tokens for the Settings window.
enum SettingsDesign {
    static let windowDefaultWidth: CGFloat = 560
    static let windowDefaultHeight: CGFloat = 600
    static let windowMinWidth: CGFloat = 480
    static let windowMinHeight: CGFloat = 540

    static let cardCornerRadius: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 14
    static let hairlineColor = Color.primary.opacity(0.08)
    static let hairlineWidth: CGFloat = 0.5

    static let tabIconSize: CGFloat = 32
    static let tabCornerRadius: CGFloat = 6

    static let statusDotSize: CGFloat = 6
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ConnectionStatusTests`
Expected: PASS — 5 tests passing

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageTracker/Views/Settings/SettingsDesign.swift Tests/UsageTrackerTests/SettingsViewModelTests.swift
git commit -m "feat(settings): add design tokens, tab enum, and ConnectionStatus"
```

---

## Task 2: `StatusDot` component

**Files:**
- Create: `Sources/UsageTracker/Views/Settings/Components/StatusDot.swift`

- [ ] **Step 1: Implement `StatusDot.swift`**

```swift
// Sources/UsageTracker/Views/Settings/Components/StatusDot.swift
import SwiftUI

/// Small colored dot indicating a provider's connection status.
/// Returns an empty view when status is `.disabled`.
struct StatusDot: View {
    let status: ConnectionStatus

    var body: some View {
        if let color = status.color {
            Circle()
                .fill(color)
                .frame(width: SettingsDesign.statusDotSize, height: SettingsDesign.statusDotSize)
                .accessibilityElement()
                .accessibilityLabel(status.voiceOverLabel)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        StatusDot(status: .connected)
        StatusDot(status: .idle)
        StatusDot(status: .failed)
        StatusDot(status: .disabled)
    }
    .padding()
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds, no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageTracker/Views/Settings/Components/StatusDot.swift
git commit -m "feat(settings): add StatusDot component"
```

---

## Task 3: `SettingsCard` container

**Files:**
- Create: `Sources/UsageTracker/Views/Settings/Components/SettingsCard.swift`

- [ ] **Step 1: Implement `SettingsCard.swift`**

```swift
// Sources/UsageTracker/Views/Settings/Components/SettingsCard.swift
import SwiftUI

/// Rounded grouped container for settings rows. Children are stacked
/// vertically with hairline dividers between them.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(SettingsDesign.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesign.cardCornerRadius)
                .stroke(SettingsDesign.hairlineColor, lineWidth: SettingsDesign.hairlineWidth)
        )
    }
}

/// Hairline divider used between rows inside a `SettingsCard`.
struct SettingsCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsDesign.hairlineColor)
            .frame(height: SettingsDesign.hairlineWidth)
    }
}

/// Standard horizontal/vertical padding for a single row inside a `SettingsCard`.
struct SettingsRowPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, SettingsDesign.rowVerticalPadding)
            .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
    }
}

extension View {
    func settingsRowPadding() -> some View {
        modifier(SettingsRowPadding())
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageTracker/Views/Settings/Components/SettingsCard.swift
git commit -m "feat(settings): add SettingsCard container with hairline divider helpers"
```

---

## Task 4: `ProviderDisclosureRow`

**Files:**
- Create: `Sources/UsageTracker/Views/Settings/Components/ProviderDisclosureRow.swift`

This row replaces `ProviderSettingsRow` from `ProviderSettingsComponents.swift`. Drag/drop continues to use `ProviderDropDelegate`.

- [ ] **Step 1: Implement `ProviderDisclosureRow.swift`**

```swift
// Sources/UsageTracker/Views/Settings/Components/ProviderDisclosureRow.swift
import SwiftUI

/// One row in the Providers tab. Displays the toggle, status dot, and an
/// optional API key field that expands when the chevron is clicked.
struct ProviderDisclosureRow: View {
    let provider: ProviderSettingsItem
    @ObservedObject var appState: AppState
    @State private var isExpanded: Bool = false

    private var enabled: Bool {
        appState.config.isProviderEnabled(provider.id)
    }

    private var liveProvider: Provider? {
        appState.providers.first(where: { $0.id == provider.id })
    }

    private var connectionStatus: ConnectionStatus {
        guard let live = liveProvider else {
            return enabled ? .idle : .disabled
        }
        return ConnectionStatus.from(providerStatus: live.status, enabled: enabled)
    }

    private var subtitle: String {
        if !enabled { return provider.hint }
        if provider.keyConfig == nil {
            return provider.hint
        }
        switch connectionStatus {
        case .connected: return "Connected"
        case .idle: return "Not configured"
        case .failed: return "Connection failed"
        case .disabled: return provider.hint
        }
    }

    private var hasKeyField: Bool { provider.keyConfig != nil }

    private var isUntested: Bool {
        provider.id == "runway" || provider.id == "stability"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            if isExpanded, let key = provider.keyConfig {
                SettingsCardDivider()
                expandedBody(keyConfig: key)
            }
        }
    }

    private var headerRow: some View {
        Button {
            if hasKeyField {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 14)

                Image(systemName: provider.icon)
                    .frame(width: 22)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.system(size: 13))
                        if isUntested && isExpanded {
                            Text("Untested")
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundColor(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                StatusDot(status: connectionStatus)

                Toggle("", isOn: Binding(
                    get: { enabled },
                    set: { appState.updateProviderEnabled(provider.id, enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

                if hasKeyField {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 14)
                } else {
                    Color.clear.frame(width: 14)
                }
            }
            .settingsRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func expandedBody(keyConfig: ProviderKeyConfig) -> some View {
        APIKeyInput(
            placeholder: keyConfig.placeholder,
            hint: keyConfig.hint,
            linkTitle: keyConfig.linkTitle,
            linkURL: keyConfig.linkURL,
            key: keyConfig.key,
            saved: keyConfig.saved,
            onSave: keyConfig.onSave,
            validateKey: keyConfig.validateKey
        )
        .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
        .padding(.vertical, SettingsDesign.rowVerticalPadding + 2)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds. (`ProviderSettingsItem`, `ProviderKeyConfig`, `APIKeyInput`, `AppState`, `Provider` all already exist.)

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageTracker/Views/Settings/Components/ProviderDisclosureRow.swift
git commit -m "feat(settings): add ProviderDisclosureRow with status dot + expand"
```

---

## Task 5: `SettingsToolbar` (top tab bar)

**Files:**
- Create: `Sources/UsageTracker/Views/Settings/SettingsToolbar.swift`

- [ ] **Step 1: Implement `SettingsToolbar.swift`**

```swift
// Sources/UsageTracker/Views/Settings/SettingsToolbar.swift
import SwiftUI

/// Top tab bar with five icon buttons. Active tab gets accent fill.
struct SettingsToolbar: View {
    @Binding var selected: SettingsTabKind

    var body: some View {
        HStack(spacing: 16) {
            ForEach(SettingsTabKind.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SettingsDesign.hairlineColor)
                .frame(height: SettingsDesign.hairlineWidth)
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: SettingsTabKind) -> some View {
        let isActive = (selected == tab)
        Button {
            selected = tab
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: SettingsDesign.tabCornerRadius)
                        .fill(isActive ? Color.accentColor : Color.clear)
                        .frame(width: SettingsDesign.tabIconSize, height: SettingsDesign.tabIconSize)
                    Image(systemName: tab.icon)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(isActive ? .white : .secondary)
                }
                Text(tab.label)
                    .font(.system(size: 10))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                    .fontWeight(isActive ? .medium : .regular)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(tab.shortcut), modifiers: .command)
        .accessibilityLabel("\(tab.label) settings")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageTracker/Views/Settings/SettingsToolbar.swift
git commit -m "feat(settings): add SettingsToolbar with keyboard shortcuts"
```

---

## Task 6: `GeneralTab`

**Files:**
- Create: `Sources/UsageTracker/Views/Settings/Tabs/GeneralTab.swift`
- Modify (header only): `Sources/UsageTracker/StatusBarController.swift` — add `.showOnboarding` notification declaration (in next task)

This tab uses `NotificationCenter.default.post(name: .showOnboarding, ...)` to ask `StatusBarController` to relaunch onboarding. The notification is declared in Task 12 alongside the observer; for this task, declare it locally to keep the task self-contained.

- [ ] **Step 1: Add `.showOnboarding` Notification.Name extension**

Modify `Sources/UsageTracker/StatusBarController.swift`. Find the existing extension at the top of the file (lines 4-6):

```swift
extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}
```

Replace with:

```swift
extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let showOnboarding = Notification.Name("showOnboarding")
}
```

- [ ] **Step 2: Implement `GeneralTab.swift`**

```swift
// Sources/UsageTracker/Views/Settings/Tabs/GeneralTab.swift
import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLogin: Bool = false

    private let refreshOptions: [Int] = [1, 2, 5, 10, 15, 30]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCard {
                    HStack {
                        Text("Launch at login")
                        Spacer()
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: launchAtLogin) { _, newValue in
                                setLaunchAtLogin(newValue)
                            }
                    }
                    .settingsRowPadding()

                    SettingsCardDivider()

                    HStack {
                        Text("Refresh interval")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { appState.config.refreshIntervalMinutes },
                            set: { appState.updateRefreshInterval($0) }
                        )) {
                            ForEach(refreshOptions, id: \.self) { minutes in
                                Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }
                    .settingsRowPadding()
                }

                SettingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Onboarding")
                            Text("Show the welcome screen again.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("Show Again") {
                            NotificationCenter.default.post(name: .showOnboarding, object: nil)
                        }
                        .controlSize(.small)
                    }
                    .settingsRowPadding()
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.error("Failed to set launch at login: \(error)")
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds. (`Log` is the existing logger from `Sources/UsageTracker/Log.swift`; if it doesn't exist, replace with `print(...)`.)

- [ ] **Step 4: Commit**

```bash
git add Sources/UsageTracker/Views/Settings/Tabs/GeneralTab.swift Sources/UsageTracker/StatusBarController.swift
git commit -m "feat(settings): add GeneralTab with refresh interval picker"
```

---

## Task 7: `DisplayTab`

**Files:**
- Create: `Sources/UsageTracker/Views/Settings/Tabs/DisplayTab.swift`

This tab includes the menu-bar pinned-item picker per the spec. The picker shares state with the popover's right-click pinning via `AppConfig.pinnedItem`.

- [ ] **Step 1: Implement `DisplayTab.swift`**

```swift
// Sources/UsageTracker/Views/Settings/Tabs/DisplayTab.swift
import SwiftUI

/// Tag type for the menu-bar pinned-item Picker.
enum PinnedSelection: Hashable {
    case auto
    case pinned(providerId: String, itemLabel: String)

    init(from pinnedItem: PinnedItem?) {
        if let pin = pinnedItem {
            self = .pinned(providerId: pin.providerId, itemLabel: pin.itemLabel)
        } else {
            self = .auto
        }
    }

    var asPinnedItem: PinnedItem? {
        switch self {
        case .auto: return nil
        case .pinned(let providerId, let itemLabel):
            return PinnedItem(providerId: providerId, itemLabel: itemLabel)
        }
    }
}

struct DisplayTab: View {
    @ObservedObject var appState: AppState

    private var pinnedSelection: Binding<PinnedSelection> {
        Binding(
            get: { PinnedSelection(from: appState.config.pinnedItem) },
            set: { newValue in
                appState.config.pinnedItem = newValue.asPinnedItem
                appState.saveConfig()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCard {
                    HStack {
                        Text("Hide not connected")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { appState.config.hideNotConnected },
                            set: { appState.updateHideNotConnected($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .settingsRowPadding()

                    SettingsCardDivider()

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show API cost estimate")
                            Text("Rough estimate based on Claude Code conversation logs. Not actual billing data — may differ significantly from real costs.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { appState.config.showCostEstimate },
                            set: { appState.updateShowCostEstimate($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .settingsRowPadding()
                }

                SettingsCard {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Menu bar shows")
                            Text("Which usage item appears in the menu bar.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Picker("", selection: pinnedSelection) {
                            Text("Auto (highest %)").tag(PinnedSelection.auto)
                            ForEach(menuBarOptions(), id: \.self) { option in
                                Text("\(option.providerName) · \(option.itemLabel)")
                                    .tag(PinnedSelection.pinned(providerId: option.providerId, itemLabel: option.itemLabel))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220)
                    }
                    .settingsRowPadding()
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    private struct MenuBarOption: Hashable {
        let providerId: String
        let providerName: String
        let itemLabel: String
    }

    private func menuBarOptions() -> [MenuBarOption] {
        appState.visibleProviders.flatMap { provider in
            provider.items.map { item in
                MenuBarOption(providerId: provider.id, providerName: provider.name, itemLabel: item.label)
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Add round-trip test for `PinnedSelection`**

Append to `Tests/UsageTrackerTests/SettingsViewModelTests.swift`:

```swift
@Suite("PinnedSelection round-trip")
struct PinnedSelectionTests {

    @Test("nil pinned item maps to .auto")
    func nilToAuto() {
        let selection = PinnedSelection(from: nil)
        #expect(selection == .auto)
        #expect(selection.asPinnedItem == nil)
    }

    @Test("pinned item round-trips")
    func pinnedRoundTrip() {
        let pin = PinnedItem(providerId: "claude", itemLabel: "Session")
        let selection = PinnedSelection(from: pin)
        #expect(selection == .pinned(providerId: "claude", itemLabel: "Session"))
        #expect(selection.asPinnedItem == pin)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter PinnedSelectionTests`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageTracker/Views/Settings/Tabs/DisplayTab.swift Tests/UsageTrackerTests/SettingsViewModelTests.swift
git commit -m "feat(settings): add DisplayTab with menu-bar pinned-item picker"
```

---

## Task 8: `HelpTab` — inline the existing HelpView content

**Files:**
- Create: `Sources/UsageTracker/Views/Settings/Tabs/HelpTab.swift`

The current `HelpView` uses a `Form` and `NavigationStack`. The new tab inlines the same three sections (Auto-Detected, API Key Services, Tips) into `SettingsCard`s with monochrome icons. The `HelpRow` struct from `HelpView.swift` is re-defined locally here so we can delete `HelpView.swift` later.

- [ ] **Step 1: Implement `HelpTab.swift`**

```swift
// Sources/UsageTracker/Views/Settings/Tabs/HelpTab.swift
import SwiftUI

struct HelpTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section(title: "Auto-Detected Services", rows: [
                    HelpEntry(icon: "brain", title: "Claude",
                              description: "Detected from Claude Code CLI. Run 'claude' in terminal to sign in."),
                    HelpEntry(icon: "cursorarrow.rays", title: "Cursor",
                              description: "Detected from Cursor app. Sign in to Cursor to see your usage."),
                    HelpEntry(icon: "terminal.fill", title: "Codex",
                              description: "Detected from Codex CLI. Run 'codex login' in terminal to sign in.")
                ])

                section(title: "API Key Services", rows: [
                    HelpEntry(icon: "sparkles", title: "OpenAI",
                              description: "Add API key from platform.openai.com/api-keys"),
                    HelpEntry(icon: "waveform", title: "ElevenLabs",
                              description: "Add API key from elevenlabs.io/app/settings/api-keys"),
                    HelpEntry(icon: "paintbrush", title: "Stability AI",
                              description: "Add API key from platform.stability.ai/account/keys"),
                    HelpEntry(icon: "film", title: "Runway",
                              description: "Add API key from dev.runwayml.com"),
                    HelpEntry(icon: "arrow.trianglehead.branch", title: "OpenRouter",
                              description: "Add API key from openrouter.ai/settings/keys")
                ])

                section(title: "Tips", rows: [
                    HelpEntry(icon: "cursorarrow.click.2", title: "View Usage",
                              description: "Left-click the menu bar icon to see your usage stats."),
                    HelpEntry(icon: "contextualmenu.and.cursorarrow", title: "Quick Access",
                              description: "Right-click for Settings, Clear Cache, and Quit options."),
                    HelpEntry(icon: "line.3.horizontal", title: "Reorder",
                              description: "Drag providers in Settings to change display order."),
                    HelpEntry(icon: "eye.slash", title: "Hide Services",
                              description: "Toggle off services you don't use in Settings.")
                ])

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func section(title: String, rows: [HelpEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)

            SettingsCard {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, entry in
                    helpRow(entry)
                    if index < rows.count - 1 {
                        SettingsCardDivider()
                    }
                }
            }
        }
    }

    private func helpRow(_ entry: HelpEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                Text(entry.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .settingsRowPadding()
    }

    private struct HelpEntry: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageTracker/Views/Settings/Tabs/HelpTab.swift
git commit -m "feat(settings): inline help content as HelpTab"
```

---

## Task 9: `AboutTab`

**Files:**
- Create: `Sources/UsageTracker/Views/Settings/Tabs/AboutTab.swift`

- [ ] **Step 1: Implement `AboutTab.swift`**

```swift
// Sources/UsageTracker/Views/Settings/Tabs/AboutTab.swift
import SwiftUI
import AppKit

struct AboutTab: View {
    @ObservedObject var appState: AppState

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?): return "v\(version) (\(build))"
        case let (version?, nil): return "v\(version)"
        case let (nil, build?): return "v\(build)"
        default: return "v1.0"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    Text("UsageTracker")
                        .font(.system(size: 16, weight: .semibold))
                    Text(versionLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                if appState.updateChecker.updateAvailable,
                   let version = appState.updateChecker.latestVersion,
                   let url = appState.updateChecker.downloadURL {
                    SettingsCard {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Update available")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Version \(version)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Link("Download", destination: url)
                                .controlSize(.small)
                        }
                        .settingsRowPadding()
                    }
                }

                SettingsCard {
                    aboutLink(label: "GitHub repository",
                              icon: "chevron.left.forwardslash.chevron.right",
                              urlString: "https://github.com/yourrepo/usagetracker")
                    SettingsCardDivider()
                    aboutLink(label: "Report an issue",
                              icon: "exclamationmark.bubble",
                              urlString: "https://github.com/yourrepo/usagetracker/issues")
                    SettingsCardDivider()
                    aboutLink(label: "License",
                              icon: "doc.text",
                              urlString: "https://github.com/yourrepo/usagetracker/blob/main/LICENSE")
                }

                Button("Quit UsageTracker") {
                    NSApp.terminate(nil)
                }
                .controlSize(.regular)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
    }

    private func aboutLink(label: String, icon: String, urlString: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12))
            Spacer()
            if let url = URL(string: urlString) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .settingsRowPadding()
    }
}
```

Note: the GitHub URLs are placeholders for the actual repo. Verify the real URL in `README.md` or git remote and substitute before commit.

- [ ] **Step 2: Replace placeholder repo URLs with the real ones**

Run: `git remote -v` and check `README.md` to find the correct repo URL. Substitute it in the three `urlString:` arguments above.

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/UsageTracker/Views/Settings/Tabs/AboutTab.swift
git commit -m "feat(settings): add AboutTab with version, update banner, links, quit"
```

---

## Task 10: `ProvidersTab`

**Files:**
- Create: `Sources/UsageTracker/Views/Settings/Tabs/ProvidersTab.swift`

This tab owns the API-key state (one `@State` per provider) that previously lived in `SettingsView`. The `ProviderSettingsItem` array construction is identical to today's `SettingsView.allProviders`.

- [ ] **Step 1: Implement `ProvidersTab.swift`**

```swift
// Sources/UsageTracker/Views/Settings/Tabs/ProvidersTab.swift
import SwiftUI

struct ProvidersTab: View {
    @ObservedObject var appState: AppState

    @State private var elevenLabsKey: String = ""
    @State private var elevenLabsSaved: Bool = false
    @State private var stabilityKey: String = ""
    @State private var stabilitySaved: Bool = false
    @State private var runwayKey: String = ""
    @State private var runwaySaved: Bool = false
    @State private var openAIKey: String = ""
    @State private var openAISaved: Bool = false
    @State private var openRouterKey: String = ""
    @State private var openRouterSaved: Bool = false

    private let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".usagetracker")

    private var allProviders: [String: ProviderSettingsItem] {
        [
            "claude": ProviderSettingsItem(
                id: "claude", icon: "brain", name: "Claude",
                hint: "via Claude Code", keyConfig: nil
            ),
            "cursor": ProviderSettingsItem(
                id: "cursor", icon: "cursorarrow.rays", name: "Cursor",
                hint: "via Cursor app", keyConfig: nil
            ),
            "codex": ProviderSettingsItem(
                id: "codex", icon: "terminal.fill", name: "Codex",
                hint: "via codex login", keyConfig: nil
            ),
            "elevenlabs": ProviderSettingsItem(
                id: "elevenlabs", icon: "waveform", name: "ElevenLabs",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "elevenlabs.io/app/settings/api-keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://elevenlabs.io/app/settings/api-keys"),
                    key: $elevenLabsKey, saved: $elevenLabsSaved,
                    onSave: { saveKey("elevenlabs", elevenLabsKey) },
                    validateKey: validateElevenLabsKey
                )
            ),
            "stability": ProviderSettingsItem(
                id: "stability", icon: "paintbrush", name: "Stability AI",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "platform.stability.ai/account/keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://platform.stability.ai/account/keys"),
                    key: $stabilityKey, saved: $stabilitySaved,
                    onSave: { saveKey("stability", stabilityKey) },
                    validateKey: validateStabilityKey
                )
            ),
            "runway": ProviderSettingsItem(
                id: "runway", icon: "film", name: "Runway",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "dev.runwayml.com",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://dev.runwayml.com"),
                    key: $runwayKey, saved: $runwaySaved,
                    onSave: { saveKey("runway", runwayKey) },
                    validateKey: validateRunwayKey
                )
            ),
            "openai": ProviderSettingsItem(
                id: "openai", icon: "sparkles", name: "OpenAI API",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "platform.openai.com/api-keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://platform.openai.com/api-keys"),
                    key: $openAIKey, saved: $openAISaved,
                    onSave: { saveKey("openai", openAIKey) },
                    validateKey: validateOpenAIKey
                )
            ),
            "openrouter": ProviderSettingsItem(
                id: "openrouter", icon: "arrow.trianglehead.branch", name: "OpenRouter",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "openrouter.ai/settings/keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://openrouter.ai/settings/keys"),
                    key: $openRouterKey, saved: $openRouterSaved,
                    onSave: { saveKey("openrouter", openRouterKey) },
                    validateKey: validateOpenRouterKey
                )
            )
        ]
    }

    private var providerSettings: [ProviderSettingsItem] {
        appState.config.providerOrder.compactMap { allProviders[$0] }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCard {
                    ForEach(Array(providerSettings.enumerated()), id: \.element.id) { index, provider in
                        ProviderDisclosureRow(provider: provider, appState: appState)
                            .onDrag {
                                NSItemProvider(object: provider.id as NSString)
                            }
                            .onDrop(of: [.text], delegate: ProviderDropDelegate(
                                item: provider.id,
                                appState: appState
                            ))
                        if index < providerSettings.count - 1 {
                            SettingsCardDivider()
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .onAppear {
            loadAllKeys()
        }
    }

    // MARK: - Key persistence

    private func loadAllKeys() {
        elevenLabsKey = loadKey("elevenlabs") ?? ""
        elevenLabsSaved = !elevenLabsKey.isEmpty

        stabilityKey = loadKey("stability") ?? ""
        stabilitySaved = !stabilityKey.isEmpty

        runwayKey = loadKey("runway") ?? ""
        runwaySaved = !runwayKey.isEmpty

        openAIKey = loadKey("openai") ?? ""
        openAISaved = !openAIKey.isEmpty

        openRouterKey = loadKey("openrouter") ?? ""
        openRouterSaved = !openRouterKey.isEmpty
    }

    private func loadKey(_ name: String) -> String? {
        let path = configDir.appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: path),
              let config = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return config["api_key"]
    }

    private func saveKey(_ name: String, _ key: String) {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let path = configDir.appendingPathComponent("\(name).json")
        let config = ["api_key": key]

        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: path)

            switch name {
            case "elevenlabs": elevenLabsSaved = true
            case "stability": stabilitySaved = true
            case "runway": runwaySaved = true
            case "openai": openAISaved = true
            case "openrouter": openRouterSaved = true
            default: break
            }

            Task { await appState.refresh() }
        }
    }

    // MARK: - Validators (copied verbatim from current SettingsView)

    private func validateElevenLabsKey(_ key: String) async -> (Bool, String?) {
        let url = URL(string: "https://api.elevenlabs.io/v1/user")!
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 { return (true, nil) }
                if httpResponse.statusCode == 401 { return (false, "Invalid API key") }
                return (false, "HTTP \(httpResponse.statusCode)")
            }
            return (false, "Invalid response")
        } catch {
            return (false, "Connection failed")
        }
    }

    private func validateStabilityKey(_ key: String) async -> (Bool, String?) {
        let url = URL(string: "https://api.stability.ai/v1/user/account")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 { return (true, nil) }
                if httpResponse.statusCode == 401 { return (false, "Invalid API key") }
                return (false, "HTTP \(httpResponse.statusCode)")
            }
            return (false, "Invalid response")
        } catch {
            return (false, "Connection failed")
        }
    }

    private func validateRunwayKey(_ key: String) async -> (Bool, String?) {
        if key.hasPrefix("key_") && key.count > 10 {
            return (true, nil)
        }
        return (false, "Key should start with 'key_'")
    }

    private func validateOpenRouterKey(_ key: String) async -> (Bool, String?) {
        let url = URL(string: "https://openrouter.ai/api/v1/key")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 { return (true, nil) }
                if httpResponse.statusCode == 401 { return (false, "Invalid API key") }
                return (false, "HTTP \(httpResponse.statusCode)")
            }
            return (false, "Invalid response")
        } catch {
            return (false, "Connection failed")
        }
    }

    private func validateOpenAIKey(_ key: String) async -> (Bool, String?) {
        let isAdminKey = key.hasPrefix("sk-admin-")
        let url: URL
        if isAdminKey {
            let now = Int(Date().timeIntervalSince1970)
            let start = now - 86400
            url = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(start)&end_time=\(now)&bucket_width=1d")!
        } else {
            url = URL(string: "https://api.openai.com/v1/models")!
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 { return (true, nil) }
                if httpResponse.statusCode == 401 { return (false, "Invalid API key") }
                if httpResponse.statusCode == 403 {
                    if isAdminKey { return (false, "Need usage scope") }
                    return (false, "Missing permissions")
                }
                return (false, "HTTP \(httpResponse.statusCode)")
            }
            return (false, "Invalid response")
        } catch {
            return (false, "Connection failed")
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageTracker/Views/Settings/Tabs/ProvidersTab.swift
git commit -m "feat(settings): add ProvidersTab with disclosure rows"
```

---

## Task 11: `SettingsContent` (root view)

**Files:**
- Create: `Sources/UsageTracker/Views/Settings/SettingsContent.swift`

This is the root view assigned to the NSWindow's hosting controller. It owns the selected-tab `@AppStorage` and routes to the right tab body. The window title is updated via a binding that the window controller observes.

- [ ] **Step 1: Implement `SettingsContent.swift`**

```swift
// Sources/UsageTracker/Views/Settings/SettingsContent.swift
import SwiftUI

struct SettingsContent: View {
    @ObservedObject var appState: AppState

    /// Selected tab persists across window close/reopen via UserDefaults.
    @AppStorage("settingsSelectedTab") private var selectedRaw: String = SettingsTabKind.general.rawValue

    /// Optional callback the window controller uses to update its title.
    var onTabChanged: ((SettingsTabKind) -> Void)?

    private var selected: Binding<SettingsTabKind> {
        Binding(
            get: { SettingsTabKind(rawValue: selectedRaw) ?? .general },
            set: { newValue in
                selectedRaw = newValue.rawValue
                onTabChanged?(newValue)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsToolbar(selected: selected)
            Group {
                switch selected.wrappedValue {
                case .general: GeneralTab(appState: appState)
                case .providers: ProvidersTab(appState: appState)
                case .display: DisplayTab(appState: appState)
                case .help: HelpTab()
                case .about: AboutTab(appState: appState)
                }
            }
            .id(selected.wrappedValue)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: selected.wrappedValue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(
            minWidth: SettingsDesign.windowMinWidth,
            minHeight: SettingsDesign.windowMinHeight
        )
        .onAppear {
            onTabChanged?(selected.wrappedValue)
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageTracker/Views/Settings/SettingsContent.swift
git commit -m "feat(settings): add SettingsContent root view"
```

---

## Task 12: Wire up `StatusBarController` to host the new view

**Files:**
- Modify: `Sources/UsageTracker/StatusBarController.swift`

Two changes:
1. `SettingsWindowController.showSettings()` now hosts `SettingsContent` instead of `SettingsView`, with a hidden title bar and full-size content view, and sets the window's content size to 560×600 (resizable to 480×540 minimum).
2. `StatusBarController.setup(...)` observes `.showOnboarding` notifications and forwards to `onboardingWindowController`.

- [ ] **Step 1: Update `SettingsWindowController.showSettings()`**

In `Sources/UsageTracker/StatusBarController.swift`, locate the `showSettings()` method (lines 18-39 in the current file). Replace with:

```swift
func showSettings() {
    if let existingWindow = window, existingWindow.isVisible {
        existingWindow.orderFrontRegardless()
        existingWindow.makeKey()
        return
    }

    let weakSelfRef = self
    let rootView = SettingsContent(appState: appState) { [weak weakSelfRef] tab in
        weakSelfRef?.window?.title = "UsageTracker · \(tab.label)"
    }
    let hostingController = NSHostingController(rootView: rootView)

    let newWindow = NSWindow(contentViewController: hostingController)
    newWindow.title = "UsageTracker"
    newWindow.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
    newWindow.titlebarAppearsTransparent = true
    newWindow.titleVisibility = .hidden
    newWindow.isMovableByWindowBackground = true
    newWindow.setContentSize(NSSize(
        width: SettingsDesign.windowDefaultWidth,
        height: SettingsDesign.windowDefaultHeight
    ))
    newWindow.minSize = NSSize(
        width: SettingsDesign.windowMinWidth,
        height: SettingsDesign.windowMinHeight
    )
    newWindow.center()
    newWindow.delegate = self
    newWindow.isReleasedWhenClosed = false

    self.window = newWindow

    newWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}
```

- [ ] **Step 2: Add `.showOnboarding` notification observer in `StatusBarController.setup`**

In `Sources/UsageTracker/StatusBarController.swift`, locate the existing `.openSettings` observer registration (around lines 145-151):

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(openSettings),
    name: .openSettings,
    object: nil
)
```

Add a second observer immediately after it:

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(showOnboardingFromNotification),
    name: .showOnboarding,
    object: nil
)
```

Then add the handler method to `StatusBarController` (place it near `@objc private func openSettings()`):

```swift
@objc private func showOnboardingFromNotification() {
    onboardingWindowController?.showOnboarding()
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds. Old `SettingsView` references inside `showSettings` are gone; old file still exists but is unreachable.

- [ ] **Step 4: Commit**

```bash
git add Sources/UsageTracker/StatusBarController.swift
git commit -m "feat(settings): wire StatusBarController to new settings window"
```

---

## Task 13: Remove the duplicate `Settings { ... }` Scene from `App.swift`

**Files:**
- Modify: `Sources/UsageTracker/App.swift`

The standalone `Settings { SettingsView(...) }` scene in `App.swift` creates a parallel macOS-managed Settings window via Cmd+, that competes with the right-click → Settings… path. Remove it so `SettingsWindowController.showSettings()` is the single entry point.

- [ ] **Step 1: Remove the Settings scene**

In `Sources/UsageTracker/App.swift`, locate the App body (lines 8-13):

```swift
var body: some Scene {
    Settings {
        SettingsView(appState: appDelegate.appState)
    }
}
```

Replace the entire `body` with:

```swift
var body: some Scene {
    Settings {
        EmptyView()
    }
}
```

(SwiftUI `App` requires at least one Scene. `Settings { EmptyView() }` keeps the standard Cmd+, → menu integration but renders nothing — the right-click → Settings... flow remains the only way to open the real window. The empty Cmd+, scene is invisible to users.)

- [ ] **Step 2: Build and run**

Run: `swift build && .build/debug/UsageTracker &`

Expected: App launches, menu bar icon appears. Right-click → Settings... opens the new tabbed window. Cmd+, opens an invisible/empty SwiftUI window (acceptable side-effect; can be addressed later by making the gear-button shortcut explicit).

Stop the app: find its PID with `pgrep -f UsageTracker | head -1` and `kill <pid>`.

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageTracker/App.swift
git commit -m "refactor: collapse Settings scene to single entry point"
```

---

## Task 14: Delete `SettingsView.swift`, `HelpView.swift`, and unused row components

**Files:**
- Delete: `Sources/UsageTracker/Views/SettingsView.swift`
- Delete: `Sources/UsageTracker/Views/HelpView.swift`
- Modify: `Sources/UsageTracker/Views/ProviderSettingsComponents.swift` (remove `ProviderToggle` and `ProviderSettingsRow`)

- [ ] **Step 1: Delete the old view files**

```bash
rm Sources/UsageTracker/Views/SettingsView.swift
rm Sources/UsageTracker/Views/HelpView.swift
```

- [ ] **Step 2: Remove `ProviderToggle` and `ProviderSettingsRow` from `ProviderSettingsComponents.swift`**

Open `Sources/UsageTracker/Views/ProviderSettingsComponents.swift`. Delete the entire `ProviderToggle` struct (currently lines 134-171) and the entire `ProviderSettingsRow` struct (currently lines 173-204). Keep:
- `KeyValidationState` enum
- `APIKeyInput` struct
- `ProviderSettingsItem` struct
- `ProviderKeyConfig` struct
- `ProviderDropDelegate` struct

After the edit, the file should contain only those five types.

- [ ] **Step 3: Build to verify nothing references the removed types**

Run: `swift build`
Expected: Build succeeds. If any file fails to compile, search for references to `ProviderToggle` or `ProviderSettingsRow` and confirm they're no longer needed.

- [ ] **Step 4: Run all tests to confirm nothing broke**

Run: `swift test`
Expected: All tests pass (existing + the new `ConnectionStatusTests` + `PinnedSelectionTests`).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove old SettingsView, HelpView, and unused row components"
```

---

## Task 15: Add tab persistence test

**Files:**
- Modify: `Tests/UsageTrackerTests/SettingsViewModelTests.swift`

Verify `SettingsTabKind.rawValue` round-trip and that the `@AppStorage` key resolves correctly (we test the enum-from-string fallback behavior here, not SwiftUI's storage layer).

- [ ] **Step 1: Add tests**

Append to `Tests/UsageTrackerTests/SettingsViewModelTests.swift`:

```swift
@Suite("SettingsTabKind persistence")
struct SettingsTabKindTests {

    @Test("All cases have unique raw values")
    func uniqueRawValues() {
        let raws = SettingsTabKind.allCases.map(\.rawValue)
        let unique = Set(raws)
        #expect(raws.count == unique.count)
    }

    @Test("Raw value round-trip")
    func rawRoundTrip() {
        for tab in SettingsTabKind.allCases {
            let restored = SettingsTabKind(rawValue: tab.rawValue)
            #expect(restored == tab)
        }
    }

    @Test("Unknown raw value is nil (caller falls back to .general)")
    func unknownRaw() {
        #expect(SettingsTabKind(rawValue: "bogus") == nil)
    }

    @Test("Each tab has a distinct keyboard shortcut")
    func uniqueShortcuts() {
        let shortcuts = SettingsTabKind.allCases.map(\.shortcut)
        let unique = Set(shortcuts)
        #expect(shortcuts.count == unique.count)
    }
}

@Suite("AppState refresh interval")
struct AppStateRefreshIntervalTests {

    @MainActor
    @Test("updateRefreshInterval writes to config")
    func writesToConfig() {
        let appState = AppState()
        appState.updateRefreshInterval(15)
        #expect(appState.config.refreshIntervalMinutes == 15)
    }
}
```

- [ ] **Step 2: Run tests**

Run: `swift test`
Expected: All tests pass — the four new `SettingsTabKindTests` and one new `AppStateRefreshIntervalTests`, plus everything from prior tasks.

- [ ] **Step 3: Commit**

```bash
git add Tests/UsageTrackerTests/SettingsViewModelTests.swift
git commit -m "test(settings): add tab persistence and refresh interval tests"
```

---

## Task 16: Manual QA + final build

**Files:** None (verification only)

- [ ] **Step 1: Clean build**

```bash
swift build
```

Expected: builds with no errors or warnings introduced by this work.

- [ ] **Step 2: Run all tests**

```bash
swift test
```

Expected: every suite passes. Note the count of new tests (5 ConnectionStatus + 2 PinnedSelection + 4 SettingsTabKind + 1 AppStateRefreshInterval = 12 new tests minimum).

- [ ] **Step 3: Launch the app and walk the manual QA checklist**

```bash
.build/debug/UsageTracker &
```

Run through the checklist below, ticking each item. If any fails, debug, fix, and re-test.

- [ ] Right-click menu bar icon → Settings… opens a 560×600 borderless window with five tabs across the top.
- [ ] ⌘1 through ⌘5 select General / Providers / Display / Help / About respectively.
- [ ] Window title in Mission Control reads "UsageTracker · <selected tab>".
- [ ] **General:** Toggle Launch at login persists across app restart. Refresh-interval picker shows 1/2/5/10/15/30 minute options; selection writes to `~/.usagetracker/config.json`. "Show Onboarding Again" opens the onboarding window.
- [ ] **Providers:** All 8 providers appear in saved order. Drag a provider — order persists across window reopen and writes to config. Each row's status dot reflects connection state (green/gray/red, hidden when toggled off). Auto-detected providers (Claude, Cursor, Codex) show no chevron. Click chevron on OpenAI/ElevenLabs/etc. → `APIKeyInput` expands with 0.18s ease-in-out animation. Saving a key debounces validation, shows red border on invalid, green ✓ on valid. Runway and Stability show an "Untested" pill when expanded.
- [ ] **Display:** "Hide not connected" toggle hides offline providers from the popover. "Show API cost estimate" toggles the cost line in the popover. "Menu bar shows…" picker offers "Auto (highest %)" plus one entry per visible provider/item; selection updates the menu bar icon's percentage source.
- [ ] **Help:** All 12 entries from the original `HelpView` appear under three sections with monochrome `.secondary` icons.
- [ ] **About:** App icon, name, version+build display. If an update is available, the Download banner appears. GitHub / Issues / License links open in the default browser. Quit button terminates the app.
- [ ] Switch to Dark Mode (System Settings → Appearance → Dark) — re-open Settings; all five tabs render correctly with no hard-coded light backgrounds.
- [ ] Resize the window to its minimum (480×540) and back — content reflows without clipping.
- [ ] Close and re-open the Settings window — last-selected tab is remembered.

- [ ] **Step 4: If any QA item failed, fix it inline (no separate task) and re-run `swift test` + the QA item before continuing.**

- [ ] **Step 5: Final commit (if any QA fixes were made)**

```bash
git add -A
git commit -m "fix(settings): address QA findings"
```

(Skip this step if no fixes were needed.)

---

## Done

The Settings window now uses a tabbed top toolbar with monochrome SF Symbols, disclosure rows for providers, a status dot for connection state, and a refreshed visual system shared across all tabs. All `AppConfig` behavior is preserved; no schema migration is needed.

Stop the running app:

```bash
pgrep -f UsageTracker | head -1 | xargs -r kill
```
