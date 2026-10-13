import Foundation
import Testing
@testable import UsageTracker

@Suite("Settings limit row detail")
struct SettingsLimitRowTests {
    let now = Date(timeIntervalSince1970: 1_783_425_600)

    func item(resetLabel: String?, resetsAt: Date? = nil) -> UsageItem {
        UsageItem(label: "Session", current: 20, limit: 100, resetLabel: resetLabel, resetsAt: resetsAt)
    }

    @Test("A reset date reads as a live countdown")
    func countdownFromDate() {
        let detail = SettingsLimitRow.detail(for: item(resetLabel: "5d", resetsAt: now.addingTimeInterval(9000)), now: now)
        #expect(detail == "Resets in 2h 30m")
    }

    @Test("A reset date that has passed shows nothing, not a stale label")
    func passedDate() {
        let detail = SettingsLimitRow.detail(for: item(resetLabel: "5d", resetsAt: now.addingTimeInterval(-60)), now: now)
        #expect(detail == nil)
    }

    @Test("Duration labels without a date still read as resets", arguments: ["6d", "4h 19m", "45m"])
    func durationLabel(label: String) {
        #expect(SettingsLimitRow.detail(for: item(resetLabel: label), now: now) == "Resets in \(label)")
    }

    @Test("Spend and balance labels pass through", arguments: ["$12.40 / $50.00", "1234 today", "42 left", "No usage"])
    func amountLabel(label: String) {
        #expect(SettingsLimitRow.detail(for: item(resetLabel: label), now: now) == label)
    }

    @Test("No label, no detail")
    func noLabel() {
        #expect(SettingsLimitRow.detail(for: item(resetLabel: nil), now: now) == nil)
        #expect(SettingsLimitRow.detail(for: item(resetLabel: ""), now: now) == nil)
    }
}
