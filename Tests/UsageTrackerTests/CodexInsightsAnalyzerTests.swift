import Foundation
import Testing
@testable import UsageTracker

@Suite("Codex local activity insights")
struct CodexInsightsAnalyzerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_783_425_600) // 2026-07-14 12:00 UTC

    private func thread(_ id: String, hoursAgo: Double, createdHoursAgo: Double? = nil,
                        tokens: Int = 0, model: String? = "gpt-5", cwd: String = "/work/app") -> CodexInsightsAnalyzer.ThreadRecord {
        .init(
            id: id,
            title: "Chat \(id)",
            cwd: cwd,
            model: model,
            tokensUsed: tokens,
            createdAt: now.addingTimeInterval(-3600 * (createdHoursAgo ?? hoursAgo)),
            updatedAt: now.addingTimeInterval(-3600 * hoursAgo)
        )
    }

    @Test("Today stats include only chats updated today")
    func todayStats() {
        let insights = CodexInsightsAnalyzer.aggregate(records: [
            thread("a", hoursAgo: 1, tokens: 120_000, model: "gpt-5"),
            thread("b", hoursAgo: 3, createdHoursAgo: 28, tokens: 80_000, model: "gpt-5-mini"),
            thread("old", hoursAgo: 25, tokens: 999_999)
        ], now: now, calendar: calendar)

        #expect(insights.today?.updatedThreadCount == 2)
        #expect(insights.today?.createdThreadCount == 1)
        #expect(insights.today?.activeThreadTokens == 200_000)
        #expect(insights.models.map(\.model) == ["gpt-5", "gpt-5-mini"])
        #expect(insights.recentThreads.map(\.id) == ["a", "b", "old"])
    }

    @Test("No activity today leaves today stats empty but preserves recent chats")
    func noTodayActivity() {
        let insights = CodexInsightsAnalyzer.aggregate(records: [thread("old", hoursAgo: 25)], now: now, calendar: calendar)
        #expect(insights.today == nil)
        #expect(insights.models.isEmpty)
        #expect(insights.recentThreads.first?.project == "app")
    }
}
