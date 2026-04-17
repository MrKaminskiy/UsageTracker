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
