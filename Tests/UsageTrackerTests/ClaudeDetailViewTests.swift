import Testing
import Foundation
@testable import UsageTracker

@Suite("Claude detail formatters")
struct ClaudeDetailFormatTests {
    var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test("Same-day reset shows time only")
    func sameDayReset() {
        // 2026-07-07 12:00 UTC → reset 16:40 same day
        let now = Date(timeIntervalSince1970: 1783425600)
        let reset = now.addingTimeInterval(4 * 3600 + 40 * 60)
        let label = ClaudeDetailFormat.absoluteResetLabel(for: reset, now: now, calendar: utcCalendar)
        #expect(label == "resets 4:40 PM")
    }

    @Test("Different-day reset shows weekday and hour")
    func weekdayReset() {
        // 2026-07-07 12:00 UTC is a Tuesday; +4 days = Saturday 2026-07-11, force 23:00
        let now = Date(timeIntervalSince1970: 1783425600)
        let reset = now.addingTimeInterval(4 * 24 * 3600 + 11 * 3600)  // Sat 23:00 UTC
        let label = ClaudeDetailFormat.absoluteResetLabel(for: reset, now: now, calendar: utcCalendar)
        #expect(label == "resets Sat 11 PM")
    }

    @Test("Token counts abbreviate")
    func tokenCounts() {
        #expect(ClaudeDetailFormat.tokenCount(123) == "123")
        #expect(ClaudeDetailFormat.tokenCount(45_600) == "46k")
        #expect(ClaudeDetailFormat.tokenCount(999_499) == "999k")
        #expect(ClaudeDetailFormat.tokenCount(1_200_000) == "1.2M")
        #expect(ClaudeDetailFormat.tokenCount(12_000_000) == "12M")
    }
}

@Suite("Claude detail reset text")
struct ClaudeDetailResetTextTests {
    var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    let now = Date(timeIntervalSince1970: 1783425600)  // 2026-07-07 12:00 UTC

    @Test("A window still running shows when it resets")
    func resetTextFuture() {
        let resetsAt = now.addingTimeInterval(2 * 3600)
        let item = UsageItem(label: "Session", current: 40, limit: 100, resetLabel: "2h 0m", resetsAt: resetsAt)
        #expect(ClaudeDetailFormat.resetText(for: item, now: now, calendar: utcCalendar)
                == ClaudeDetailFormat.absoluteResetLabel(for: resetsAt, now: now, calendar: utcCalendar))
    }

    @Test("A window that reset since the reading says so, not a time in the past")
    func resetTextElapsed() {
        let item = UsageItem(label: "Session", current: 40, limit: 100, resetLabel: "1h",
                             resetsAt: now.addingTimeInterval(-3600)).markedReset()
        #expect(ClaudeDetailFormat.resetText(for: item, now: now, calendar: utcCalendar) == "reset")
    }

    @Test("A row with no reset time shows its own detail")
    func resetTextNoDate() {
        let item = UsageItem(label: "Extra credits", current: 12.4, limit: 50, resetLabel: "$12.40/$50")
        #expect(ClaudeDetailFormat.resetText(for: item, now: now, calendar: utcCalendar) == "$12.40/$50")
    }
}
