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
        let shortcuts = SettingsTabKind.allCases.map { String($0.shortcut.character) }
        let unique = Set(shortcuts)
        #expect(shortcuts.count == unique.count)
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
