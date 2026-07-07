import Testing
import Foundation
@testable import UsageTracker

@Suite("ClaudeInsightsAnalyzer parsing")
struct ClaudeInsightsParsingTests {

    @Test("Parses assistant line with attribution and sidechain fields")
    func parsesUsageEvent() {
        let line = """
        {"type":"assistant","timestamp":"2026-07-07T10:00:00.000Z","sessionId":"sess-1","isSidechain":true,"attributionSkill":"superpowers:brainstorming","attributionAgent":"code-reviewer","message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":200,"cache_read_input_tokens":300}}}
        """
        guard case .usage(let event)? = ClaudeInsightsAnalyzer.parseEvent(line) else {
            Issue.record("expected usage event"); return
        }
        #expect(event.model == "claude-opus-4-6")
        #expect(event.input == 100)
        #expect(event.output == 50)
        #expect(event.cacheWrite == 200)
        #expect(event.cacheRead == 300)
        #expect(event.isSidechain == true)
        #expect(event.sessionId == "sess-1")
        #expect(event.skill == "superpowers:brainstorming")
        #expect(event.agent == "code-reviewer")
        #expect(event.totalTokens == 650)
        #expect(event.contextTokens == 600)
    }

    @Test("Missing optional fields default sensibly")
    func defaultsForMissingFields() {
        let line = """
        {"type":"assistant","timestamp":"2026-07-07T10:00:00Z","message":{"model":"claude-sonnet-4-6","role":"assistant","usage":{"input_tokens":10,"output_tokens":5}}}
        """
        guard case .usage(let event)? = ClaudeInsightsAnalyzer.parseEvent(line) else {
            Issue.record("expected usage event"); return
        }
        #expect(event.isSidechain == false)
        #expect(event.sessionId == nil)
        #expect(event.skill == nil)
        #expect(event.agent == nil)
        #expect(event.cacheWrite == 0)
        #expect(event.cacheRead == 0)
    }

    @Test("Parses structuredPatch tool result into patch event")
    func parsesPatchEvent() {
        let line = """
        {"type":"user","timestamp":"2026-07-07T10:00:00.000Z","toolUseResult":{"filePath":"/a.swift","structuredPatch":[{"lines":["+new line","+another"," context","-old line"]},{"lines":["+third"]}]}}
        """
        guard case .patch(let event)? = ClaudeInsightsAnalyzer.parseEvent(line) else {
            Issue.record("expected patch event"); return
        }
        #expect(event.linesAdded == 3)
        #expect(event.linesRemoved == 1)
    }

    @Test("Returns nil for human lines, empty patches, malformed JSON, missing timestamp")
    func returnsNilForIrrelevantLines() {
        #expect(ClaudeInsightsAnalyzer.parseEvent("{invalid json") == nil)
        #expect(ClaudeInsightsAnalyzer.parseEvent(#"{"type":"human","timestamp":"2026-07-07T10:00:00Z","message":{"role":"user"}}"#) == nil)
        #expect(ClaudeInsightsAnalyzer.parseEvent(#"{"type":"user","timestamp":"2026-07-07T10:00:00Z","toolUseResult":{"structuredPatch":[]}}"#) == nil)
        #expect(ClaudeInsightsAnalyzer.parseEvent(#"{"type":"assistant","message":{"model":"m","usage":{"input_tokens":1}}}"#) == nil)
    }
}

@Suite("ClaudeInsightsAnalyzer aggregation")
struct ClaudeInsightsAggregationTests {
    // Fixed reference time: 2026-07-07 12:00:00 UTC
    let now = Date(timeIntervalSince1970: 1783425600)
    var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func usage(hoursAgo: Double, tokens: Int, contextTokens: Int? = nil,
               sidechain: Bool = false, session: String? = "s1",
               skill: String? = nil, agent: String? = nil,
               model: String = "claude-opus-4-6") -> TranscriptEvent {
        // Encode all tokens as output except the requested context portion,
        // so totalTokens == tokens and contextTokens is controllable.
        let ctx = contextTokens ?? 0
        return .usage(UsageEvent(
            timestamp: now.addingTimeInterval(-hoursAgo * 3600),
            model: model,
            input: ctx, output: tokens - ctx, cacheWrite: 0, cacheRead: 0,
            isSidechain: sidechain, sessionId: session, skill: skill, agent: agent
        ))
    }

    @Test("Context share counts tokens of requests above 150k context")
    func contextShare() {
        let events = [
            usage(hoursAgo: 1, tokens: 200_000, contextTokens: 160_000),  // over 150k
            usage(hoursAgo: 2, tokens: 100_000, contextTokens: 100_000),  // under
            usage(hoursAgo: 30, tokens: 500_000, contextTokens: 400_000), // outside 24h window
        ]
        let insights = ClaudeInsightsAnalyzer.aggregate(recentEvents: events, monthlyCost: 0, now: now, calendar: utcCalendar)
        // 200k of 300k tokens in-window came from >150k-context requests
        #expect(abs((insights.contextShareOver150k ?? 0) - 66.67) < 0.1)
    }

    @Test("Boundary: exactly 150k context does not count as over")
    func contextBoundary() {
        let events = [usage(hoursAgo: 1, tokens: 150_000, contextTokens: 150_000)]
        let insights = ClaudeInsightsAnalyzer.aggregate(recentEvents: events, monthlyCost: 0, now: now, calendar: utcCalendar)
        #expect(insights.contextShareOver150k == 0)
    }

    @Test("Subagent-heavy sessions: >25% sidechain tokens marks the whole session")
    func subagentShare() {
        let events = [
            // session A: 400 tokens, 200 sidechain (50% → heavy)
            usage(hoursAgo: 1, tokens: 200, session: "A"),
            usage(hoursAgo: 1, tokens: 200, sidechain: true, session: "A"),
            // session B: 600 tokens, 0 sidechain (not heavy)
            usage(hoursAgo: 2, tokens: 600, session: "B"),
        ]
        let insights = ClaudeInsightsAnalyzer.aggregate(recentEvents: events, monthlyCost: 0, now: now, calendar: utcCalendar)
        // heavy session A holds 400 of 1000 tokens
        #expect(abs((insights.subagentShare ?? 0) - 40.0) < 0.01)
    }

    @Test("Skills and subagents share, sorted, top 5, sidechain agents grouped")
    func skillsAndAgents() {
        let events = [
            usage(hoursAgo: 1, tokens: 300, skill: "brainstorming"),
            usage(hoursAgo: 1, tokens: 100, skill: "tdd"),
            usage(hoursAgo: 1, tokens: 400, sidechain: true, agent: "code-reviewer"),
            usage(hoursAgo: 1, tokens: 100, sidechain: true, agent: nil),  // → "other"
            usage(hoursAgo: 1, tokens: 100),
        ]
        let insights = ClaudeInsightsAnalyzer.aggregate(recentEvents: events, monthlyCost: 0, now: now, calendar: utcCalendar)
        #expect(insights.skills.map(\.name) == ["brainstorming", "tdd"])
        #expect(abs(insights.skills[0].share - 30.0) < 0.01)
        #expect(insights.subagents.map(\.name) == ["code-reviewer", "other"])
        #expect(abs(insights.subagents[0].share - 40.0) < 0.01)
    }

    @Test("No 24h data leaves insight fields nil and lists empty")
    func emptyWindow() {
        let events = [usage(hoursAgo: 30, tokens: 1000, skill: "x")]
        let insights = ClaudeInsightsAnalyzer.aggregate(recentEvents: events, monthlyCost: 5, now: now, calendar: utcCalendar)
        #expect(insights.contextShareOver150k == nil)
        #expect(insights.subagentShare == nil)
        #expect(insights.skills.isEmpty)
        #expect(insights.subagents.isEmpty)
        #expect(insights.monthlyCost == 5)
        #expect(insights.hasWarnings == false)
    }

    @Test("Today stats: cost, tokens, distinct main sessions, patch lines; midnight boundary")
    func todayStats() {
        // now is 12:00 UTC → today started 12h ago
        let events = [
            usage(hoursAgo: 1, tokens: 1_000_000, session: "A", model: "claude-opus-4-6"),  // $75 output
            usage(hoursAgo: 2, tokens: 500, sidechain: true, session: "A"),                 // sidechain: not counted as session
            usage(hoursAgo: 3, tokens: 500, session: "B"),
            usage(hoursAgo: 13, tokens: 999, session: "C"),  // yesterday (13h > 12h) — excluded from today
            .patch(PatchEvent(timestamp: now.addingTimeInterval(-3600), linesAdded: 296, linesRemoved: 6)),
            .patch(PatchEvent(timestamp: now.addingTimeInterval(-13 * 3600), linesAdded: 50, linesRemoved: 50)),  // yesterday
        ]
        let insights = ClaudeInsightsAnalyzer.aggregate(recentEvents: events, monthlyCost: 0, now: now, calendar: utcCalendar)
        let today = insights.today
        #expect(today != nil)
        #expect(today?.sessionCount == 2)                      // A and B; sidechain line doesn't add
        #expect(today?.totalTokens == 1_001_000)
        #expect(abs((today?.cost ?? 0) - 75.0) < 0.1)          // 1M opus output tokens
        #expect(today?.linesAdded == 296)
        #expect(today?.linesRemoved == 6)
    }

    @Test("Nothing today leaves today nil")
    func noToday() {
        let events = [usage(hoursAgo: 13, tokens: 100)]  // yesterday relative to 12:00 UTC
        let insights = ClaudeInsightsAnalyzer.aggregate(recentEvents: events, monthlyCost: 0, now: now, calendar: utcCalendar)
        #expect(insights.today == nil)
    }

    @Test("hasWarnings reflects thresholds")
    func warningThresholds() {
        var i = ClaudeInsights()
        #expect(i.hasWarnings == false)
        i.contextShareOver150k = 39.9
        #expect(i.hasWarnings == false)
        i.contextShareOver150k = 40
        #expect(i.hasWarnings == true)
        i = ClaudeInsights()
        i.subagentShare = 30
        #expect(i.hasWarnings == true)
    }
}
