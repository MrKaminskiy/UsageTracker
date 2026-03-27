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

    @Test("Color thresholds based on percentage")
    func usageItemColor() {
        let low = UsageItem(label: "Low", current: 30, limit: 100, resetLabel: nil)
        let mid = UsageItem(label: "Mid", current: 65, limit: 100, resetLabel: nil)
        let high = UsageItem(label: "High", current: 85, limit: 100, resetLabel: nil)

        // Colors are custom gradients, not system colors — verify they differ by threshold
        #expect(low.color != mid.color)
        #expect(mid.color != high.color)
        #expect(low.color != high.color)
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
}

@Suite("AppConfig Tests")
struct AppConfigTests {

    /// Ensures default refresh interval is 10 minutes.
    @Test("Default refresh interval is 10 minutes")
    func defaultRefreshInterval() {
        let config = AppConfig()
        #expect(config.refreshIntervalMinutes == 10)
    }
}
