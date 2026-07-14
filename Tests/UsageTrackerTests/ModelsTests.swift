import Foundation
import Testing
@testable import UsageTracker

@Suite("UsageItem Tests")
struct UsageItemTests {

    @Test("Percentage calculation")
    func usageItemPercentage() {
        let item = UsageItem(label: "Test", current: 25, limit: 100, resetLabel: nil)
        #expect(item.percentage == 25.0)
    }

    @Test("Zero limit returns zero percentage")
    func usageItemPercentageZeroLimit() {
        let item = UsageItem(label: "Test", current: 10, limit: 0, resetLabel: nil)
        #expect(item.percentage == 0.0)
    }

    @Test("Color thresholds: green below 60, amber 60..<85, red 85+")
    func usageItemColor() {
        let green = UsageItem(label: "G", current: 59, limit: 100, resetLabel: nil)
        let amber = UsageItem(label: "A", current: 60, limit: 100, resetLabel: nil)
        let amberHigh = UsageItem(label: "AH", current: 84, limit: 100, resetLabel: nil)
        let red = UsageItem(label: "R", current: 85, limit: 100, resetLabel: nil)

        #expect(green.color != amber.color)
        #expect(amber.color == amberHigh.color)
        #expect(amberHigh.color != red.color)
        #expect(green.color != red.color)
    }

    @Test("UsageItem resetsAt defaults to nil and is settable")
    func usageItemNewFields() {
        let plain = UsageItem(label: "T", current: 1, limit: 100, resetLabel: nil)
        #expect(plain.resetsAt == nil)

        let date = Date()
        let rich = UsageItem(label: "T", current: 12, limit: 50, resetLabel: nil, resetsAt: date)
        #expect(rich.resetsAt == date)
        #expect(abs(rich.percentage - 24.0) < 0.01)
    }

    @Test("stablePinKey falls back to label when pinKey is unset, else uses pinKey")
    func usageItemStablePinKey() {
        let noKey = UsageItem(label: "5h", current: 1, limit: 100, resetLabel: nil)
        #expect(noKey.stablePinKey == "5h")

        let withKey = UsageItem(label: "5h", current: 1, limit: 100, resetLabel: nil, pinKey: "Session")
        #expect(withKey.stablePinKey == "Session")
    }
}

@Suite("Provider Tests")
struct ProviderTests {

    @Test("Max percentage from items")
    func providerMaxPercentage() {
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
        #expect(provider.maxPercentage == 80.0)
    }

    @Test("Empty items returns zero")
    func providerEmptyItems() {
        let provider = Provider(id: "test", name: "Test", icon: "star", items: [], status: .loaded)
        #expect(provider.maxPercentage == 0.0)
    }

    @Test("Provider planLabel and insights default to nil")
    func providerNewFields() {
        let provider = Provider(id: "t", name: "T", icon: "star", items: [], status: .loaded)
        #expect(provider.planLabel == nil)
        #expect(provider.insights == nil)
    }
}

@Suite("AppConfig Tests")
struct AppConfigTests {

    /// Ensures default refresh interval is 5 minutes.
    @Test("Default refresh interval is 5 minutes")
    func defaultRefreshInterval() {
        let config = AppConfig()
        #expect(config.refreshIntervalMinutes == 5)
    }
}
