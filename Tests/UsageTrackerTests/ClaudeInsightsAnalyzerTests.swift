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
        #expect(abs((today?.cost ?? 0) - 75.075) < 0.0001)     // 1M opus output ($75) + two 500-output events (~$0.0375 each)
        #expect(today?.linesAdded == 296)
        #expect(today?.linesRemoved == 6)
    }

    @Test("Today stats split cache reads from new tokens")
    func todayCacheSplit() {
        // 1 event today: 5M cache read + 100k output → totalTokens 5.1M, new 100k
        let events: [TranscriptEvent] = [
            .usage(UsageEvent(
                timestamp: now.addingTimeInterval(-3600),
                model: "claude-opus-4-6",
                input: 0, output: 100_000, cacheWrite: 0, cacheRead: 5_000_000,
                isSidechain: false, sessionId: "A", skill: nil, agent: nil
            ))
        ]
        let today = ClaudeInsightsAnalyzer.aggregate(recentEvents: events, monthlyCost: 0, now: now, calendar: utcCalendar).today
        #expect(today?.totalTokens == 5_100_000)
        #expect(today?.cacheReadTokens == 5_000_000)
        #expect(today?.newTokens == 100_000)
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

@Suite("ClaudeInsightsAnalyzer file analysis")
struct ClaudeInsightsAnalyzeTests {

    func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Formats `date` as a fractional-second ISO8601 string. Callers should pass a date
    /// safely in the past (relative to the `now` they'll hand to `analyze`) so that
    /// ISO8601DateFormatter's ~50%-of-the-time rounding-up of fractional seconds can never
    /// push the fixture timestamp past `now` and get it dropped by `timestamp <= now` filters.
    func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    @Test("Returns nil for missing directory")
    func missingDir() async {
        let now = Date()
        let analyzer = ClaudeInsightsAnalyzer()
        let result = await analyzer.analyze(projectsDir: URL(fileURLWithPath: "/tmp/nope-\(UUID().uuidString)"), now: now)
        #expect(result == nil)
    }

    @Test("Empty directory yields zero-cost insights with no data")
    func emptyDir() async throws {
        let now = Date()
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let analyzer = ClaudeInsightsAnalyzer()
        let result = await analyzer.analyze(projectsDir: dir, now: now)
        #expect(result != nil)
        #expect(result?.monthlyCost == 0)
        #expect(result?.contextShareOver150k == nil)
        #expect(result?.today == nil)
    }

    @Test("Aggregates cost and insights across files, including subagents subdirectory")
    func aggregatesFiles() async throws {
        let now = Date()
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Main session file: 1M opus input = $15
        let mainLine = """
        {"type":"assistant","timestamp":"\(iso(now.addingTimeInterval(-60)))","sessionId":"s1","isSidechain":false,"message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try mainLine.write(to: dir.appendingPathComponent("main.jsonl"), atomically: true, encoding: .utf8)

        // Subagent file nested like real transcripts: <session>/subagents/agent-x.jsonl
        let subDir = dir.appendingPathComponent("s1/subagents")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let sideLine = """
        {"type":"assistant","timestamp":"\(iso(now.addingTimeInterval(-60)))","sessionId":"s1","isSidechain":true,"attributionAgent":"code-reviewer","message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try sideLine.write(to: subDir.appendingPathComponent("agent-x.jsonl"), atomically: true, encoding: .utf8)

        let analyzer = ClaudeInsightsAnalyzer()
        let result = await analyzer.analyze(projectsDir: dir, now: now)
        #expect(abs((result?.monthlyCost ?? 0) - 30.0) < 0.01)
        // session s1: 50% sidechain tokens → subagent-heavy → 100% share
        #expect(abs((result?.subagentShare ?? 0) - 100.0) < 0.01)
        #expect(result?.subagents.first?.name == "code-reviewer")
    }

    @Test("Cache: unchanged file is not re-parsed; changed file is")
    func cacheInvalidation() async throws {
        let now = Date()
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("a.jsonl")

        let line = """
        {"type":"assistant","timestamp":"\(iso(now.addingTimeInterval(-60)))","sessionId":"s1","message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try line.write(to: fileURL, atomically: true, encoding: .utf8)

        let analyzer = ClaudeInsightsAnalyzer()
        let first = await analyzer.analyze(projectsDir: dir, now: now)
        #expect(abs((first?.monthlyCost ?? 0) - 15.0) < 0.01)

        // Second run without changes: same result (cache path exercised)
        let second = await analyzer.analyze(projectsDir: dir, now: now)
        #expect(abs((second?.monthlyCost ?? 0) - 15.0) < 0.01)

        // Append another 1M-input line and bump mtime → re-parse picks it up
        let appended = line + "\n" + line
        try appended.write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: fileURL.path)

        let third = await analyzer.analyze(projectsDir: dir, now: now)
        #expect(abs((third?.monthlyCost ?? 0) - 30.0) < 0.01)
    }

    @Test("Cache: same mtime but different size (content) is re-parsed")
    func cacheInvalidatesOnSizeChange() async throws {
        let now = Date()
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("a.jsonl")

        let line = """
        {"type":"assistant","timestamp":"\(iso(now.addingTimeInterval(-60)))","sessionId":"s1","message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try line.write(to: fileURL, atomically: true, encoding: .utf8)
        let fixedModDate = Date().addingTimeInterval(-30)
        try FileManager.default.setAttributes([.modificationDate: fixedModDate], ofItemAtPath: fileURL.path)

        let analyzer = ClaudeInsightsAnalyzer()
        let first = await analyzer.analyze(projectsDir: dir, now: now)
        #expect(abs((first?.monthlyCost ?? 0) - 15.0) < 0.01)

        // Rewrite with different content length (two lines instead of one) but force the
        // SAME modification date — only file size differs, so a modDate-only cache key
        // would wrongly serve the stale cached summary.
        let appended = line + "\n" + line
        try appended.write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: fixedModDate], ofItemAtPath: fileURL.path)

        let second = await analyzer.analyze(projectsDir: dir, now: now)
        #expect(abs((second?.monthlyCost ?? 0) - 30.0) < 0.01)
    }

    @Test("Malformed file mixed with valid file doesn't poison results")
    func malformedFileSkipped() async throws {
        let now = Date()
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0xFF, 0xFE, 0x00]).write(to: dir.appendingPathComponent("garbage.jsonl"))
        let line = """
        {"type":"assistant","timestamp":"\(iso(now.addingTimeInterval(-60)))","sessionId":"s1","message":{"model":"claude-sonnet-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try line.write(to: dir.appendingPathComponent("good.jsonl"), atomically: true, encoding: .utf8)

        let analyzer = ClaudeInsightsAnalyzer()
        let result = await analyzer.analyze(projectsDir: dir, now: now)
        #expect(abs((result?.monthlyCost ?? 0) - 3.0) < 0.01)
    }
}
