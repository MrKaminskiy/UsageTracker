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

    @Test("Usage level thresholds: normal below 60, warning 60..<85, critical 85+")
    func usageLevelThresholds() {
        #expect(UsageLevel(percentage: 0) == .normal)
        #expect(UsageLevel(percentage: 59.999) == .normal)
        #expect(UsageLevel(percentage: 60) == .warning)
        #expect(UsageLevel(percentage: 84.999) == .warning)
        #expect(UsageLevel(percentage: 85) == .critical)
        #expect(UsageLevel(percentage: 130) == .critical)

        let item = UsageItem(label: "W", current: 34, limit: 40, resetLabel: nil)  // 85%
        #expect(UsageLevel(percentage: item.percentage) == .critical)
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

    @Test("Extra usage is shown by default")
    func extraUsageDefault() {
        #expect(AppConfig().shouldShowExtraUsageInPopover)
    }

    @Test("Config without extra-usage preference decodes with default")
    func missingExtraUsagePreference() throws {
        let data = try JSONEncoder().encode(AppConfig())
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.shouldShowExtraUsageInPopover)
    }
}

@Suite("Claude provider IDs")
struct ClaudeProviderIDTests {

    @Test("Claude IDs are the default and claude-<hash>, nothing else")
    func claudeIDs() {
        #expect(isClaudeProviderID("claude"))
        #expect(isClaudeProviderID("claude-2601a85c"))
        #expect(!isClaudeProviderID("codex"))
        #expect(!isClaudeProviderID("claudette"))
    }

    @Test("A config.json written by 1.5.1 decodes with no account names")
    func decodes151Config() throws {
        let json = #"{"refreshIntervalMinutes":5,"launchAtLogin":false,"hideNotConnected":true,"hasCompletedOnboarding":true,"showCostEstimate":false,"pinnedItem":{"providerId":"claude","itemLabel":"Weekly"},"enabledProviders":{"claude":true,"codex":true},"providerOrder":["claude","cursor","codex"]}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.claudeAccountNames == nil)
        #expect(config.pinnedItem == PinnedItem(providerId: "claude", itemLabel: "Weekly"))
    }
}
