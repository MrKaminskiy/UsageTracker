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
