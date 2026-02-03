# UsageTracker Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native SwiftUI menu bar app that displays AI coding tool usage via JavaScript plugins.

**Architecture:** Menu bar app with popover UI showing provider usage. JavaScriptCore runs JS plugins that fetch usage data. Timer handles periodic refresh.

**Tech Stack:** Swift 5.9+, SwiftUI, JavaScriptCore, macOS 14+

---

## Task 1: Create Xcode Project

**Files:**
- Create: Xcode project via command line

**Step 1: Create the Xcode project**

```bash
cd /Users/nk/Documents/Projects/UsageTracker
xcodegen generate --spec project.yml
```

First create `project.yml`:

```yaml
name: UsageTracker
options:
  bundleIdPrefix: com.usagetracker
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.0"
  generateEmptyDirectories: true
settings:
  SWIFT_VERSION: "5.9"
  MACOSX_DEPLOYMENT_TARGET: "14.0"
targets:
  UsageTracker:
    type: application
    platform: macOS
    sources:
      - UsageTracker
    settings:
      INFOPLIST_FILE: UsageTracker/Info.plist
      PRODUCT_BUNDLE_IDENTIFIER: com.usagetracker.app
      PRODUCT_NAME: UsageTracker
      CODE_SIGN_STYLE: Automatic
      ENABLE_HARDENED_RUNTIME: YES
      LD_RUNPATH_SEARCH_PATHS: "@executable_path/../Frameworks"
    info:
      path: UsageTracker/Info.plist
      properties:
        CFBundleName: UsageTracker
        CFBundleDisplayName: UsageTracker
        CFBundleIdentifier: com.usagetracker.app
        CFBundleVersion: "1"
        CFBundleShortVersionString: "1.0"
        LSUIElement: true
        NSAppTransportSecurity:
          NSAllowsArbitraryLoads: true
  UsageTrackerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - UsageTrackerTests
    dependencies:
      - target: UsageTracker
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.usagetracker.tests
```

**Step 2: Create directory structure**

```bash
mkdir -p UsageTracker/Views
mkdir -p UsageTracker/Resources/DefaultPlugins
mkdir -p UsageTrackerTests
```

**Step 3: Create Info.plist**

Create `UsageTracker/Info.plist`:

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
    <string>com.usagetracker.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>UsageTracker</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
```

**Step 4: Install xcodegen if needed and generate project**

```bash
brew install xcodegen || true
xcodegen generate
```

**Step 5: Commit**

```bash
git add .
git commit -m "feat: initialize Xcode project structure"
```

---

## Task 2: Create Data Models

**Files:**
- Create: `UsageTracker/Models.swift`
- Create: `UsageTrackerTests/ModelsTests.swift`

**Step 1: Write the test file**

Create `UsageTrackerTests/ModelsTests.swift`:

```swift
import XCTest
@testable import UsageTracker

final class ModelsTests: XCTestCase {

    func testUsageItemPercentage() {
        let item = UsageItem(label: "Test", current: 25, limit: 100, resetLabel: nil)
        XCTAssertEqual(item.percentage, 25.0)
    }

    func testUsageItemPercentageZeroLimit() {
        let item = UsageItem(label: "Test", current: 10, limit: 0, resetLabel: nil)
        XCTAssertEqual(item.percentage, 0.0)
    }

    func testUsageItemColor() {
        let low = UsageItem(label: "Low", current: 30, limit: 100, resetLabel: nil)
        let mid = UsageItem(label: "Mid", current: 65, limit: 100, resetLabel: nil)
        let high = UsageItem(label: "High", current: 85, limit: 100, resetLabel: nil)

        XCTAssertEqual(low.color, .green)
        XCTAssertEqual(mid.color, .yellow)
        XCTAssertEqual(high.color, .red)
    }

    func testProviderMaxPercentage() {
        let provider = Provider(
            id: "test",
            name: "Test",
            icon: "star",
            items: [
                UsageItem(label: "A", current: 30, limit: 100, resetLabel: nil),
                UsageItem(label: "B", current: 80, limit: 100, resetLabel: nil)
            ],
            status: .loaded
        )
        XCTAssertEqual(provider.maxPercentage, 80.0)
    }

    func testProviderEmptyItems() {
        let provider = Provider(id: "test", name: "Test", icon: "star", items: [], status: .loaded)
        XCTAssertEqual(provider.maxPercentage, 0.0)
    }
}
```

**Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
```

Expected: Build fails (Models.swift doesn't exist)

**Step 3: Write the Models implementation**

Create `UsageTracker/Models.swift`:

```swift
import SwiftUI

struct UsageItem: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let current: Double
    let limit: Double
    let resetLabel: String?

    var percentage: Double {
        guard limit > 0 else { return 0 }
        return (current / limit) * 100
    }

    var color: Color {
        switch percentage {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }
}

enum ProviderStatus: Equatable {
    case loading
    case loaded
    case error(String)
}

struct Provider: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    var items: [UsageItem]
    var status: ProviderStatus
    var isExpanded: Bool = true

    var maxPercentage: Double {
        items.map(\.percentage).max() ?? 0
    }

    var displayColor: Color {
        switch maxPercentage {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }
}

struct AppConfig: Codable {
    var refreshIntervalMinutes: Int = 15
    var launchAtLogin: Bool = false
}
```

**Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add UsageTracker/Models.swift UsageTrackerTests/ModelsTests.swift
git commit -m "feat: add data models for Provider and UsageItem"
```

---

## Task 3: Create Basic App Shell

**Files:**
- Create: `UsageTracker/App.swift`

**Step 1: Create the app entry point**

Create `UsageTracker/App.swift`:

```swift
import SwiftUI

@main
struct UsageTrackerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            MenuBarIcon(percentage: appState.maxPercentage, isLoading: appState.isLoading)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var providers: [Provider] = []
    @Published var isLoading: Bool = false
    @Published var config: AppConfig = AppConfig()
    @Published var lastUpdated: Date?

    var maxPercentage: Double {
        providers.map(\.maxPercentage).max() ?? 0
    }

    private var refreshTimer: Timer?

    init() {
        loadConfig()
        setupRefreshTimer()
    }

    func refresh() async {
        isLoading = true
        // Plugin loading will be added in Task 4
        isLoading = false
        lastUpdated = Date()
    }

    func loadConfig() {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker/config.json")

        if let data = try? Data(contentsOf: configURL),
           let loaded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = loaded
        }
    }

    func saveConfig() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker")

        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let configURL = configDir.appendingPathComponent("config.json")
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL)
        }
    }

    private func setupRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(config.refreshIntervalMinutes * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func updateRefreshInterval(_ minutes: Int) {
        config.refreshIntervalMinutes = minutes
        saveConfig()
        setupRefreshTimer()
    }
}
```

**Step 2: Build to verify no compile errors**

```bash
xcodebuild build -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
```

Expected: Build fails (MenuBarView, MenuBarIcon, SettingsView don't exist yet)

**Step 3: Commit partial progress**

```bash
git add UsageTracker/App.swift
git commit -m "feat: add app entry point and AppState"
```

---

## Task 4: Create Menu Bar Icon

**Files:**
- Create: `UsageTracker/Views/MenuBarIcon.swift`

**Step 1: Create the menu bar icon view**

Create `UsageTracker/Views/MenuBarIcon.swift`:

```swift
import SwiftUI

struct MenuBarIcon: View {
    let percentage: Double
    let isLoading: Bool

    private var color: Color {
        switch percentage {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                .frame(width: 16, height: 16)

            Circle()
                .trim(from: 0, to: percentage / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(-90))

            if isLoading {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            } else {
                Text("\(Int(percentage))")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        MenuBarIcon(percentage: 25, isLoading: false)
        MenuBarIcon(percentage: 65, isLoading: false)
        MenuBarIcon(percentage: 90, isLoading: false)
        MenuBarIcon(percentage: 50, isLoading: true)
    }
    .padding()
}
```

**Step 2: Build to verify**

```bash
xcodebuild build -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
```

Expected: Still fails (MenuBarView, SettingsView missing)

**Step 3: Commit**

```bash
git add UsageTracker/Views/MenuBarIcon.swift
git commit -m "feat: add radial progress menu bar icon"
```

---

## Task 5: Create Provider Row View

**Files:**
- Create: `UsageTracker/Views/ProviderRow.swift`

**Step 1: Create the provider row component**

Create `UsageTracker/Views/ProviderRow.swift`:

```swift
import SwiftUI

struct ProviderRow: View {
    @Binding var provider: Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            providerHeader

            if provider.isExpanded {
                ForEach(provider.items) { item in
                    UsageItemRow(item: item)
                }
            }
        }
    }

    private var providerHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                provider.isExpanded.toggle()
            }
        } label: {
            HStack {
                Image(systemName: provider.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 12)

                Image(systemName: provider.icon)
                    .font(.system(size: 12))
                    .foregroundColor(provider.displayColor)

                Text(provider.name)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                switch provider.status {
                case .loading:
                    ProgressView()
                        .scaleEffect(0.6)
                case .error(let message):
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .help(message)
                case .loaded:
                    Text("\(Int(provider.maxPercentage))%")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct UsageItemRow: View {
    let item: UsageItem

    var body: some View {
        HStack(spacing: 8) {
            Text(item.label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.color)
                        .frame(width: geometry.size.width * min(item.percentage / 100, 1))
                }
            }
            .frame(height: 6)

            Text("\(Int(item.percentage))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .trailing)

            if let resetLabel = item.resetLabel {
                Text(resetLabel)
                    .font(.system(size: 9))
                    .foregroundColor(.tertiary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.leading, 24)
    }
}

#Preview {
    VStack {
        ProviderRow(provider: .constant(Provider(
            id: "claude",
            name: "Claude",
            icon: "brain",
            items: [
                UsageItem(label: "Session", current: 2, limit: 100, resetLabel: "4h 37m"),
                UsageItem(label: "All models", current: 27, limit: 100, resetLabel: "19h 37m"),
                UsageItem(label: "Weekly", current: 8, limit: 100, resetLabel: "Wed 2PM")
            ],
            status: .loaded
        )))
    }
    .frame(width: 320)
    .padding()
}
```

**Step 2: Build to verify**

```bash
xcodebuild build -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
```

Expected: Still fails (MenuBarView, SettingsView missing)

**Step 3: Commit**

```bash
git add UsageTracker/Views/ProviderRow.swift
git commit -m "feat: add provider row with collapsible usage items"
```

---

## Task 6: Create Menu Bar View

**Files:**
- Create: `UsageTracker/Views/MenuBarView.swift`

**Step 1: Create the main popover view**

Create `UsageTracker/Views/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Provider list
            if appState.providers.isEmpty && !appState.isLoading {
                emptyState
            } else {
                providerList
            }

            Divider()
                .padding(.vertical, 8)

            // Footer
            footer
        }
        .padding(12)
        .frame(width: 340)
        .task {
            await appState.refresh()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 24))
                .foregroundColor(.secondary)

            Text("No plugins found")
                .font(.system(size: 13, weight: .medium))

            Text("Add plugins to ~/.usagetracker/plugins/")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button("Open Plugins Folder") {
                openPluginsFolder()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($appState.providers) { $provider in
                ProviderRow(provider: $provider)

                if provider.id != appState.providers.last?.id {
                    Divider()
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task {
                    await appState.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(appState.isLoading)

            Spacer()

            if let lastUpdated = appState.lastUpdated {
                Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 10))
                    .foregroundColor(.tertiary)
            }

            Spacer()

            SettingsLink {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "xmark")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11))
    }

    private func openPluginsFolder() {
        let pluginsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker/plugins")

        try? FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(pluginsDir)
    }
}

#Preview {
    let state = AppState()
    state.providers = [
        Provider(
            id: "claude",
            name: "Claude",
            icon: "brain",
            items: [
                UsageItem(label: "Session", current: 2, limit: 100, resetLabel: "4h 37m"),
                UsageItem(label: "All models", current: 27, limit: 100, resetLabel: "19h 37m")
            ],
            status: .loaded
        ),
        Provider(
            id: "cursor",
            name: "Cursor",
            icon: "cursorarrow.rays",
            items: [
                UsageItem(label: "Usage", current: 40, limit: 100, resetLabel: nil)
            ],
            status: .loaded
        )
    ]
    state.lastUpdated = Date()

    return MenuBarView(appState: state)
}
```

**Step 2: Build to verify**

```bash
xcodebuild build -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
```

Expected: Still fails (SettingsView missing)

**Step 3: Commit**

```bash
git add UsageTracker/Views/MenuBarView.swift
git commit -m "feat: add main menu bar popover view"
```

---

## Task 7: Create Settings View

**Files:**
- Create: `UsageTracker/Views/SettingsView.swift`

**Step 1: Create the settings window view**

Create `UsageTracker/Views/SettingsView.swift`:

```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLogin: Bool = false

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Interval", selection: Binding(
                    get: { appState.config.refreshIntervalMinutes },
                    set: { appState.updateRefreshInterval($0) }
                )) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("60 minutes").tag(60)
                }
                .pickerStyle(.segmented)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("Plugins") {
                HStack {
                    Text("~/.usagetracker/plugins/")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Open") {
                        openPluginsFolder()
                    }
                }
            }

            Section("About") {
                HStack {
                    Text("UsageTracker")
                    Spacer()
                    Text("v1.0")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 250)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func openPluginsFolder() {
        let pluginsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker/plugins")

        try? FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(pluginsDir)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }
}

#Preview {
    SettingsView(appState: AppState())
}
```

**Step 2: Build to verify app compiles**

```bash
xcodebuild build -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
```

Expected: Build succeeds

**Step 3: Run tests**

```bash
xcodebuild test -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
```

Expected: All tests pass

**Step 4: Commit**

```bash
git add UsageTracker/Views/SettingsView.swift
git commit -m "feat: add settings view with refresh interval and launch at login"
```

---

## Task 8: Create Plugin Engine

**Files:**
- Create: `UsageTracker/PluginEngine.swift`
- Create: `UsageTrackerTests/PluginEngineTests.swift`

**Step 1: Write the tests**

Create `UsageTrackerTests/PluginEngineTests.swift`:

```swift
import XCTest
@testable import UsageTracker

final class PluginEngineTests: XCTestCase {

    func testParsePluginMetadata() throws {
        let js = """
        module.exports = {
            name: "TestPlugin",
            icon: "star",
            probe: async function() {
                return { label: "Test", current: 50, limit: 100 };
            }
        }
        """

        let engine = PluginEngine()
        let metadata = try engine.parseMetadata(from: js, id: "test")

        XCTAssertEqual(metadata.name, "TestPlugin")
        XCTAssertEqual(metadata.icon, "star")
    }

    func testParsePluginReturnsArray() throws {
        let js = """
        module.exports = {
            name: "MultiBar",
            icon: "chart.bar",
            probe: async function() {
                return [
                    { label: "A", current: 10, limit: 100 },
                    { label: "B", current: 20, limit: 100 }
                ];
            }
        }
        """

        let engine = PluginEngine()
        let metadata = try engine.parseMetadata(from: js, id: "multi")

        XCTAssertEqual(metadata.name, "MultiBar")
    }

    func testRunProbe() async throws {
        let js = """
        module.exports = {
            name: "Test",
            icon: "star",
            probe: async function() {
                return { label: "Usage", current: 75, limit: 100, resetLabel: "2h" };
            }
        }
        """

        let engine = PluginEngine()
        let items = try await engine.runProbe(js: js)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].label, "Usage")
        XCTAssertEqual(items[0].current, 75)
        XCTAssertEqual(items[0].limit, 100)
        XCTAssertEqual(items[0].resetLabel, "2h")
    }

    func testRunProbeArray() async throws {
        let js = """
        module.exports = {
            name: "Test",
            icon: "star",
            probe: async function() {
                return [
                    { label: "A", current: 10, limit: 100 },
                    { label: "B", current: 20, limit: 50 }
                ];
            }
        }
        """

        let engine = PluginEngine()
        let items = try await engine.runProbe(js: js)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].label, "A")
        XCTAssertEqual(items[1].label, "B")
        XCTAssertEqual(items[1].limit, 50)
    }
}
```

**Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
```

Expected: Build fails (PluginEngine doesn't exist)

**Step 3: Implement PluginEngine**

Create `UsageTracker/PluginEngine.swift`:

```swift
import Foundation
import JavaScriptCore

struct PluginMetadata {
    let id: String
    let name: String
    let icon: String
}

enum PluginError: Error, LocalizedError {
    case invalidPlugin(String)
    case probeTimeout
    case probeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlugin(let reason): return "Invalid plugin: \(reason)"
        case .probeTimeout: return "Plugin timed out"
        case .probeFailed(let reason): return "Probe failed: \(reason)"
        }
    }
}

class PluginEngine {
    private let timeout: TimeInterval = 10.0

    func parseMetadata(from js: String, id: String) throws -> PluginMetadata {
        let context = JSContext()!
        setupContext(context)

        // Wrap module.exports pattern
        let wrappedJS = """
        var module = { exports: {} };
        \(js)
        module.exports;
        """

        guard let result = context.evaluateScript(wrappedJS),
              !result.isUndefined else {
            throw PluginError.invalidPlugin("Could not evaluate plugin")
        }

        guard let name = result.objectForKeyedSubscript("name")?.toString(),
              !name.isEmpty && name != "undefined" else {
            throw PluginError.invalidPlugin("Missing 'name' property")
        }

        let icon = result.objectForKeyedSubscript("icon")?.toString() ?? "questionmark.circle"

        return PluginMetadata(id: id, name: name, icon: icon)
    }

    func runProbe(js: String) async throws -> [UsageItem] {
        return try await withCheckedThrowingContinuation { continuation in
            let context = JSContext()!
            setupContext(context)

            // Create promise resolver
            var hasCompleted = false

            let resolve: @convention(block) (JSValue) -> Void = { result in
                guard !hasCompleted else { return }
                hasCompleted = true

                let items = self.parseProbeResult(result)
                continuation.resume(returning: items)
            }

            let reject: @convention(block) (JSValue) -> Void = { error in
                guard !hasCompleted else { return }
                hasCompleted = true

                let message = error.toString() ?? "Unknown error"
                continuation.resume(throwing: PluginError.probeFailed(message))
            }

            context.setObject(resolve, forKeyedSubscript: "__resolve" as NSString)
            context.setObject(reject, forKeyedSubscript: "__reject" as NSString)

            // Run the plugin
            let wrappedJS = """
            var module = { exports: {} };
            \(js)

            (async function() {
                try {
                    const result = await module.exports.probe();
                    __resolve(result);
                } catch (e) {
                    __reject(e.toString());
                }
            })();
            """

            context.evaluateScript(wrappedJS)

            // Timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard !hasCompleted else { return }
                hasCompleted = true
                continuation.resume(throwing: PluginError.probeTimeout)
            }
        }
    }

    private func setupContext(_ context: JSContext) {
        // Add console.log
        let log: @convention(block) (String) -> Void = { message in
            print("[Plugin] \(message)")
        }
        context.setObject(log, forKeyedSubscript: "log" as NSString)

        // Add console object
        context.evaluateScript("""
            var console = {
                log: function(...args) { log(args.join(' ')); },
                error: function(...args) { log('ERROR: ' + args.join(' ')); },
                warn: function(...args) { log('WARN: ' + args.join(' ')); }
            };
        """)

        // Exception handler
        context.exceptionHandler = { _, exception in
            print("[Plugin Error] \(exception?.toString() ?? "Unknown")")
        }
    }

    private func parseProbeResult(_ result: JSValue) -> [UsageItem] {
        var items: [UsageItem] = []

        // Check if result is an array
        if result.isArray {
            let length = result.objectForKeyedSubscript("length")?.toInt32() ?? 0
            for i in 0..<length {
                if let item = result.objectAtIndexedSubscript(Int(i)),
                   let parsed = parseUsageItem(item) {
                    items.append(parsed)
                }
            }
        } else if let parsed = parseUsageItem(result) {
            items.append(parsed)
        }

        return items
    }

    private func parseUsageItem(_ value: JSValue) -> UsageItem? {
        guard let label = value.objectForKeyedSubscript("label")?.toString(),
              !label.isEmpty && label != "undefined" else {
            return nil
        }

        let current = value.objectForKeyedSubscript("current")?.toDouble() ?? 0
        let limit = value.objectForKeyedSubscript("limit")?.toDouble() ?? 100

        let resetLabelValue = value.objectForKeyedSubscript("resetLabel")
        let resetLabel: String? = (resetLabelValue?.isString == true) ? resetLabelValue?.toString() : nil

        return UsageItem(label: label, current: current, limit: limit, resetLabel: resetLabel)
    }
}
```

**Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
```

Expected: All tests pass

**Step 5: Commit**

```bash
git add UsageTracker/PluginEngine.swift UsageTrackerTests/PluginEngineTests.swift
git commit -m "feat: add JavaScriptCore-based plugin engine"
```

---

## Task 9: Integrate Plugin Loading into AppState

**Files:**
- Modify: `UsageTracker/App.swift`

**Step 1: Update AppState to load and run plugins**

Update `UsageTracker/App.swift` - add plugin loading to AppState:

```swift
import SwiftUI

@main
struct UsageTrackerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            MenuBarIcon(percentage: appState.maxPercentage, isLoading: appState.isLoading)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var providers: [Provider] = []
    @Published var isLoading: Bool = false
    @Published var config: AppConfig = AppConfig()
    @Published var lastUpdated: Date?

    private let pluginEngine = PluginEngine()
    private var refreshTimer: Timer?

    var maxPercentage: Double {
        providers.map(\.maxPercentage).max() ?? 0
    }

    init() {
        loadConfig()
        setupRefreshTimer()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let plugins = loadPlugins()

        // Run all probes concurrently
        await withTaskGroup(of: (String, Result<[UsageItem], Error>).self) { group in
            for (id, js, metadata) in plugins {
                group.addTask {
                    do {
                        let items = try await self.pluginEngine.runProbe(js: js)
                        return (id, .success(items))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }

            var results: [String: Result<[UsageItem], Error>] = [:]
            for await (id, result) in group {
                results[id] = result
            }

            // Update providers
            providers = plugins.map { id, _, metadata in
                switch results[id] {
                case .success(let items)?:
                    return Provider(
                        id: id,
                        name: metadata.name,
                        icon: metadata.icon,
                        items: items,
                        status: .loaded
                    )
                case .failure(let error)?:
                    return Provider(
                        id: id,
                        name: metadata.name,
                        icon: metadata.icon,
                        items: [],
                        status: .error(error.localizedDescription)
                    )
                case nil:
                    return Provider(
                        id: id,
                        name: metadata.name,
                        icon: metadata.icon,
                        items: [],
                        status: .error("Unknown error")
                    )
                }
            }
        }

        lastUpdated = Date()
    }

    private func loadPlugins() -> [(String, String, PluginMetadata)] {
        let pluginsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker/plugins")

        // Also check bundled plugins
        let bundledDir = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/DefaultPlugins")

        var plugins: [(String, String, PluginMetadata)] = []

        for dir in [pluginsDir, bundledDir] {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ) else { continue }

            for file in files where file.pathExtension == "js" {
                let id = file.deletingPathExtension().lastPathComponent

                // Skip if we already have this plugin (user plugins override bundled)
                if plugins.contains(where: { $0.0 == id }) { continue }

                guard let js = try? String(contentsOf: file, encoding: .utf8) else { continue }

                do {
                    let metadata = try pluginEngine.parseMetadata(from: js, id: id)
                    plugins.append((id, js, metadata))
                } catch {
                    print("Failed to parse plugin \(id): \(error)")
                }
            }
        }

        return plugins
    }

    func loadConfig() {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker/config.json")

        if let data = try? Data(contentsOf: configURL),
           let loaded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = loaded
        }
    }

    func saveConfig() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker")

        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let configURL = configDir.appendingPathComponent("config.json")
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL)
        }
    }

    private func setupRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(config.refreshIntervalMinutes * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func updateRefreshInterval(_ minutes: Int) {
        config.refreshIntervalMinutes = minutes
        saveConfig()
        setupRefreshTimer()
    }
}
```

**Step 2: Build and test**

```bash
xcodebuild build -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
xcodebuild test -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
```

Expected: Build succeeds, tests pass

**Step 3: Commit**

```bash
git add UsageTracker/App.swift
git commit -m "feat: integrate plugin loading and concurrent probe execution"
```

---

## Task 10: Create Example Claude Plugin

**Files:**
- Create: `UsageTracker/Resources/DefaultPlugins/claude.js`

**Step 1: Create a demo plugin**

Create `UsageTracker/Resources/DefaultPlugins/claude.js`:

```javascript
// Claude Pro usage tracker
// Note: This is a demo plugin showing the expected format.
// Real implementation would need to fetch from claude.ai with auth.

module.exports = {
    name: "Claude",
    icon: "brain",

    async probe() {
        // TODO: Implement actual fetching from claude.ai
        // This would require:
        // 1. Reading session cookie from browser
        // 2. Making authenticated request to usage API
        // 3. Parsing the response

        // For now, return demo data to show the UI works
        return [
            {
                label: "Session",
                current: 15,
                limit: 100,
                resetLabel: "4h 30m"
            },
            {
                label: "All models",
                current: 42,
                limit: 100,
                resetLabel: "18h 15m"
            },
            {
                label: "Weekly",
                current: 23,
                limit: 100,
                resetLabel: "Wed 2PM"
            }
        ];
    }
};
```

**Step 2: Build the app**

```bash
xcodebuild build -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
```

Expected: Build succeeds

**Step 3: Test run the app**

```bash
open src-tauri/target/release/bundle/macos/UsageTracker.app || \
  find . -name "UsageTracker.app" -type d 2>/dev/null | head -1 | xargs open
```

**Step 4: Commit**

```bash
git add UsageTracker/Resources/DefaultPlugins/claude.js
git commit -m "feat: add example Claude plugin with demo data"
```

---

## Task 11: Add Fetch Helper to Plugin Engine

**Files:**
- Modify: `UsageTracker/PluginEngine.swift`

**Step 1: Add fetch support**

Update `PluginEngine.swift` to add the `fetch` helper:

In `setupContext(_:)`, add after the console setup:

```swift
// Add fetch function
let fetchBlock: @convention(block) (String, JSValue?) -> JSValue = { [weak context] urlString, options in
    guard let context = context else {
        return JSValue(undefinedIn: nil)
    }

    // Create a promise
    let promiseJS = """
    new Promise(function(resolve, reject) {
        __pendingFetch = { resolve: resolve, reject: reject };
    })
    """
    let promise = context.evaluateScript(promiseJS)!

    // Perform fetch async
    DispatchQueue.global().async {
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                context.evaluateScript("__pendingFetch.reject(new Error('Invalid URL'))")
            }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        // Parse options
        if let opts = options, !opts.isUndefined {
            if let method = opts.objectForKeyedSubscript("method")?.toString() {
                request.httpMethod = method
            }
            if let headers = opts.objectForKeyedSubscript("headers"),
               headers.isObject {
                // Add headers
                let keys = context.evaluateScript("Object.keys")?.call(withArguments: [headers])
                let length = keys?.objectForKeyedSubscript("length")?.toInt32() ?? 0
                for i in 0..<length {
                    if let key = keys?.objectAtIndexedSubscript(Int(i))?.toString(),
                       let value = headers.objectForKeyedSubscript(key)?.toString() {
                        request.setValue(value, forHTTPHeaderField: key)
                    }
                }
            }
            if let body = opts.objectForKeyedSubscript("body")?.toString() {
                request.httpBody = body.data(using: .utf8)
            }
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    context.evaluateScript("__pendingFetch.reject(new Error('\(error.localizedDescription)'))")
                    return
                }

                guard let data = data,
                      let text = String(data: data, encoding: .utf8) else {
                    context.evaluateScript("__pendingFetch.reject(new Error('No data'))")
                    return
                }

                let httpResponse = response as? HTTPURLResponse
                let status = httpResponse?.statusCode ?? 200

                // Create response object
                let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "$", with: "\\$")

                context.evaluateScript("""
                    __pendingFetch.resolve({
                        ok: \(status >= 200 && status < 300),
                        status: \(status),
                        text: function() { return Promise.resolve(`\(escaped)`); },
                        json: function() { return Promise.resolve(JSON.parse(`\(escaped)`)); }
                    })
                """)
            }
        }.resume()
    }

    return promise
}
context.setObject(fetchBlock, forKeyedSubscript: "fetch" as NSString)
```

**Step 2: Add readFile helper**

Add after fetch:

```swift
// Add readFile function
let readFileBlock: @convention(block) (String) -> JSValue = { [weak context] path in
    guard let context = context else {
        return JSValue(undefinedIn: nil)
    }

    let promiseJS = """
    new Promise(function(resolve, reject) {
        __pendingRead = { resolve: resolve, reject: reject };
    })
    """
    let promise = context.evaluateScript(promiseJS)!

    DispatchQueue.global().async {
        let expandedPath = NSString(string: path).expandingTildeInPath

        do {
            let content = try String(contentsOfFile: expandedPath, encoding: .utf8)
            let escaped = content.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")

            DispatchQueue.main.async {
                context.evaluateScript("__pendingRead.resolve(`\(escaped)`)")
            }
        } catch {
            DispatchQueue.main.async {
                context.evaluateScript("__pendingRead.reject(new Error('\(error.localizedDescription)'))")
            }
        }
    }

    return promise
}
context.setObject(readFileBlock, forKeyedSubscript: "readFile" as NSString)

// Add env function
let envBlock: @convention(block) (String) -> String? = { name in
    ProcessInfo.processInfo.environment[name]
}
context.setObject(envBlock, forKeyedSubscript: "env" as NSString)
```

**Step 3: Build and test**

```bash
xcodebuild build -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
xcodebuild test -project UsageTracker.xcodeproj -scheme UsageTracker -destination 'platform=macOS'
```

Expected: Build succeeds, tests pass

**Step 4: Commit**

```bash
git add UsageTracker/PluginEngine.swift
git commit -m "feat: add fetch, readFile, and env helpers to plugin engine"
```

---

## Summary

After completing all tasks, you'll have:

1. A working SwiftUI menu bar app
2. JavaScriptCore-based plugin system with fetch/readFile/env helpers
3. Configurable refresh intervals (15/30/60 min)
4. Settings with launch at login
5. Example Claude plugin (demo data)

**Next steps after implementation:**
- Write real Claude plugin using authenticated requests
- Add Cursor plugin (reads local SQLite)
- Add Codex plugin
