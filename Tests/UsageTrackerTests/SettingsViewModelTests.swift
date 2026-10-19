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

@Suite("SettingsPage persistence")
struct SettingsPageTests {
    private var allPages: [SettingsPage] {
        SettingsPage.appPages + ProviderCatalog.all.keys.sorted().map { SettingsPage.provider($0) }
    }

    @Test("All pages have unique raw values")
    func uniqueRawValues() {
        let raws = allPages.map(\.rawValue)
        #expect(raws.count == Set(raws).count)
    }

    @Test("Raw value round-trip, including provider pages")
    func rawRoundTrip() {
        for page in allPages {
            #expect(SettingsPage(rawValue: page.rawValue) == page)
        }
    }

    @Test("Unknown raw values are nil, so the caller falls back to General")
    func unknownRawValues() {
        #expect(SettingsPage(rawValue: "general") == .general)
        #expect(SettingsPage(rawValue: "help") == .howItWorks)
        #expect(SettingsPage(rawValue: "providers") == nil)   // caller falls back to .general
        #expect(SettingsPage(rawValue: "bogus") == nil)
    }

    @Test("Search matches titles and keywords, case-insensitively")
    func searchMatching() {
        #expect(SettingsPage.general.matches("REFRESH"))
        #expect(SettingsPage.provider("openrouter").matches("router"))
        #expect(SettingsPage.provider("claude").matches("cookie"))
        #expect(!SettingsPage.provider("codex").matches("cookie"))
        #expect(SettingsPage.provider("openai").matches("api key"))
        #expect(!SettingsPage.provider("cursor").matches("api key"))
        #expect(!SettingsPage.about.matches("refresh"))
        #expect(SettingsPage.display.matches("  "))
    }
}

@Suite("AppState refresh interval")
struct AppStateRefreshIntervalTests {

    @MainActor
    @Test("updateRefreshInterval writes to config")
    func writesToConfig() {
        // AppState persists to the real ~/.usagetracker/config.json; snapshot and restore
        // it so running the test suite doesn't mutate the developer's actual settings.
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker/config.json")
        let backup = try? Data(contentsOf: url)
        defer { if let backup { try? backup.write(to: url) } }

        let appState = AppState()
        appState.updateRefreshInterval(15)
        #expect(appState.config.refreshIntervalMinutes == 15)
    }
}

@Suite("Popover item visibility")
@MainActor
struct PopoverItemVisibilityTests {

    @Test("Hidden extra usage is excluded from rows, pinning, and menu bar percentage")
    func hidesExtraUsageEverywhereInPopover() {
        let appState = AppState()
        appState.config.hideNotConnected = false
        appState.config.enabledProviders = ["claude": true]
        appState.config.providerOrder = ["claude"]
        appState.providers = [Provider(
            id: "claude",
            name: "Claude",
            icon: "brain",
            items: [
                UsageItem(label: "Session", current: 40, limit: 100, resetLabel: nil),
                UsageItem(label: "Extra credits", current: 90, limit: 100,
                          resetLabel: nil, kind: .extraUsage)
            ],
            status: .loaded
        )]
        appState.config.pinnedItem = PinnedItem(providerId: "claude", itemLabel: "Extra credits")
        appState.config.showExtraUsageInPopover = false

        #expect(appState.popoverProviders.first?.items.map(\.label) == ["Session"])
        #expect(appState.pinnedItem == nil)
        #expect(appState.maxPercentage == 40)

        appState.config.showExtraUsageInPopover = true
        #expect(appState.popoverProviders.first?.items.count == 2)
        #expect(appState.pinnedItem != nil)
        #expect(appState.maxPercentage == 90)
    }
}

@Suite("AppState transient-failure detection")
@MainActor
struct AppStateTransientFailureTests {

    private func withData(_ id: String) -> Provider {
        Provider(id: id, name: id, icon: "x",
                 items: [UsageItem(label: "Session", current: 40, limit: 100, resetLabel: nil)],
                 status: .loaded)
    }
    private func notConnected(_ id: String) -> Provider {
        Provider(id: id, name: id, icon: "x", items: [],
                 status: .notConnected(url: URL(string: "https://example.com")!))
    }

    @Test("Enabled provider that threw with no cached data counts as transient")
    func threwNoData() {
        let n = AppState.transientFailures(
            results: [("claude", nil)], finalProviders: [], enabled: ["claude": true])
        #expect(n == 1)
    }

    @Test("notConnected (non-throwing) is signed-out, not transient")
    func notConnectedIsNotTransient() {
        let p = notConnected("claude")
        let n = AppState.transientFailures(
            results: [("claude", p)], finalProviders: [p], enabled: ["claude": true])
        #expect(n == 0)
    }

    @Test("Disabled provider that threw is not counted")
    func disabledNotCounted() {
        let n = AppState.transientFailures(
            results: [("claude", nil)], finalProviders: [], enabled: ["claude": false])
        #expect(n == 0)
    }

    @Test("Threw but has preserved cached data is not counted")
    func cachedDataNotCounted() {
        let n = AppState.transientFailures(
            results: [("claude", nil)], finalProviders: [withData("claude")], enabled: ["claude": true])
        #expect(n == 0)
    }
}

@Suite("ProviderCatalog info")
struct ProviderCatalogInfoTests {

    @Test("A second Claude account gets its own page: its ID and name, no cookie field")
    func extraClaudeInfo() throws {
        let info = try #require(ProviderCatalog.info(for: "claude-2601a85c", liveName: "Claude · b@x"))
        #expect(info.id == "claude-2601a85c")
        #expect(info.name == "Claude · b@x")
        #expect(info.key == nil)
        #expect(info.icon == "brain")
    }

    @Test("The default Claude page keeps the browser cookie field")
    func defaultClaudeKeepsCookie() {
        #expect(ProviderCatalog.info(for: "claude")?.key?.fileName == "claude-web")
        #expect(ProviderCatalog.info(for: "claude", liveName: "Claude · a@x")?.name == "Claude · a@x")
    }

    @Test("Other providers come from the static catalog; unknown IDs have no page")
    func unknownIDIsNil() {
        #expect(ProviderCatalog.info(for: "nope") == nil)
        #expect(ProviderCatalog.info(for: "codex")?.name == "Codex")
    }
}

@Suite("Settings sidebar provider list")
struct SettingsSidebarListTests {

    @Test("A signed-in Claude account is listed even before its first reading arrives")
    func listsDiscoveredAccounts() {
        let order = ["claude", "claude-2601a85c", "cursor", "nope"]
        #expect(SettingsContent.listedProviderIDs(order: order, discoveredClaudeIDs: ["claude", "claude-2601a85c"])
                == ["claude", "claude-2601a85c", "cursor"])
        #expect(SettingsContent.listedProviderIDs(order: order, discoveredClaudeIDs: ["claude"])
                == ["claude", "cursor"])
        #expect(SettingsContent.listedProviderIDs(order: order, discoveredClaudeIDs: [])
                == ["claude", "cursor"])
    }
}
