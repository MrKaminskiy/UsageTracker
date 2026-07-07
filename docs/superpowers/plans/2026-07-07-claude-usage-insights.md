# Claude Usage Insights & Popover Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a slide-in Claude detail page (limit bars with absolute reset times, extra-usage credits, 24h insights, skills/subagents breakdown, today stats) plus small popover polish, per the approved spec `docs/superpowers/specs/2026-07-07-claude-usage-insights-design.md`.

**Architecture:** A new `ClaudeInsightsAnalyzer` actor absorbs `ClaudeCostEstimator` — one incrementally-cached pass over `~/.claude/projects/**/*.jsonl` produces the monthly cost and a `ClaudeInsights` struct at refresh time. `ClaudeProvider` attaches insights, a plan label, and an extra-credits item to the `Provider` it returns. `MenuBarView` gains a two-screen navigation (`.list` / `.claudeDetail`) rendering the new `ClaudeDetailView`.

**Tech Stack:** Swift 6, SwiftUI, swift-testing (`@Test`/`#expect`), Swift Package Manager, macOS 14+.

## Global Constraints

- Build: `swift build`; tests: `swift test` (swift-testing framework, NOT XCTest).
- All transcript-derived metrics are approximate; UI labels them "approximate · local sessions on this Mac".
- Insight warning thresholds: context share ≥ 40, subagent share ≥ 30 (constants on `ClaudeInsights`).
- Bar color thresholds change from 50/80 to: green `0..<60`, amber `60..<85`, red `85+`.
- A session is "subagent-heavy" when > 25% of its tokens are sidechain tokens.
- Per-request context size = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`; the context insight counts requests with context > 150_000.
- Missing data hides sections — never render zeros for absent transcripts.
- Commit after each task; commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

## Verified transcript facts (do not re-derive)

Real `~/.claude/projects` transcripts were inspected on 2026-07-07:

- Assistant lines: `{"type":"assistant","timestamp":"...","sessionId":"...","isSidechain":false,"attributionSkill":"superpowers:brainstorming","message":{"model":"claude-...","usage":{"input_tokens":N,"output_tokens":N,"cache_creation_input_tokens":N,"cache_read_input_tokens":N}}}`. `attributionSkill` is present only while a skill is active; `attributionAgent` (e.g. `"code-reviewer"`) is present on subagent lines.
- Subagent transcripts live in `<project>/<sessionId>/subagents/agent-*.jsonl` with `isSidechain: true` and `sessionId` set to the parent session. The existing recursive `FileManager.enumerator` walk already reaches them.
- Edit/Write tool results appear on `"type":"user"` lines as `"toolUseResult":{"structuredPatch":[{"lines":["+added line","-removed line"," context"]}, ...], ...}`.
- `extra_usage` in the OAuth usage response: `{"is_enabled":Bool,"used_credits":Double,"monthly_limit":Double}`. Dollar units are ASSUMED (unverifiable without an extra-usage-enabled account) — Task 5 logs raw values for manual verification.

## File Structure

- Create: `Sources/UsageTracker/Providers/ClaudeInsights.swift` — value types: `ClaudeInsights`, `UsageShare`, `TodayStats`, `TranscriptEvent`, `UsageEvent`, `PatchEvent`.
- Create: `Sources/UsageTracker/Providers/ClaudeInsightsAnalyzer.swift` — actor: pricing table, line parsing, aggregation, file walk + cache.
- Delete: `Sources/UsageTracker/Providers/ClaudeCostEstimator.swift` (absorbed).
- Create: `Sources/UsageTracker/Views/ClaudeDetailView.swift` — detail page + formatters.
- Modify: `Sources/UsageTracker/Models.swift`, `Providers/ClaudeProvider.swift`, `Views/MenuBarView.swift`, `Views/ProviderRow.swift`, `StatusBarController.swift`.
- Tests: Create `Tests/UsageTrackerTests/ClaudeInsightsAnalyzerTests.swift`, `Tests/UsageTrackerTests/ClaudeDetailViewTests.swift`; modify `ClaudeCostEstimatorTests.swift` (retarget to analyzer), `ModelsTests.swift`, `ClaudeProviderTests.swift`.

---

### Task 1: Transcript event models and line parsing

**Files:**
- Create: `Sources/UsageTracker/Providers/ClaudeInsights.swift`
- Create: `Sources/UsageTracker/Providers/ClaudeInsightsAnalyzer.swift`
- Test: `Tests/UsageTrackerTests/ClaudeInsightsAnalyzerTests.swift`

**Interfaces:**
- Consumes: nothing (foundation task).
- Produces: `ClaudeInsights`, `UsageShare`, `TodayStats`, `TranscriptEvent` (enum with `.usage(UsageEvent)` / `.patch(PatchEvent)`), and `ClaudeInsightsAnalyzer.parseEvent(_ line: String) -> TranscriptEvent?`, `ClaudeInsightsAnalyzer.costForTokens(model:input:output:cacheWrite:cacheRead:) -> Double`. Exact shapes below — later tasks depend on these names.

- [ ] **Step 1: Write the model types** (no test needed for plain data)

Create `Sources/UsageTracker/Providers/ClaudeInsights.swift`:

```swift
import Foundation

struct UsageShare: Equatable, Sendable {
    let name: String
    let share: Double   // 0–100, % of last-24h tokens
}

struct TodayStats: Equatable, Sendable {
    var cost: Double = 0
    var sessionCount: Int = 0
    var totalTokens: Int = 0
    var linesAdded: Int = 0
    var linesRemoved: Int = 0
}

struct ClaudeInsights: Equatable, Sendable {
    var monthlyCost: Double? = nil
    var contextShareOver150k: Double? = nil   // nil when no last-24h data
    var subagentShare: Double? = nil          // nil when no last-24h data
    var skills: [UsageShare] = []
    var subagents: [UsageShare] = []
    var today: TodayStats? = nil              // nil when nothing happened today

    static let contextWarningThreshold: Double = 40
    static let subagentWarningThreshold: Double = 30

    var hasWarnings: Bool {
        (contextShareOver150k ?? 0) >= Self.contextWarningThreshold
            || (subagentShare ?? 0) >= Self.subagentWarningThreshold
    }
}

struct UsageEvent: Equatable, Sendable {
    let timestamp: Date
    let model: String
    let input: Int
    let output: Int
    let cacheWrite: Int
    let cacheRead: Int
    let isSidechain: Bool
    let sessionId: String?
    let skill: String?
    let agent: String?

    var totalTokens: Int { input + output + cacheWrite + cacheRead }
    var contextTokens: Int { input + cacheWrite + cacheRead }
}

struct PatchEvent: Equatable, Sendable {
    let timestamp: Date
    let linesAdded: Int
    let linesRemoved: Int
}

enum TranscriptEvent: Equatable, Sendable {
    case usage(UsageEvent)
    case patch(PatchEvent)
}
```

- [ ] **Step 2: Write failing tests for parseEvent**

Create `Tests/UsageTrackerTests/ClaudeInsightsAnalyzerTests.swift`:

```swift
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter ClaudeInsightsParsingTests`
Expected: compile FAILURE — `ClaudeInsightsAnalyzer` not defined.

- [ ] **Step 4: Write the analyzer skeleton with parseEvent**

Create `Sources/UsageTracker/Providers/ClaudeInsightsAnalyzer.swift`:

```swift
import Foundation

struct ModelPricing: Sendable {
    let patterns: [String]           // case-insensitive substrings to match
    let inputPerMTok: Double         // $ per million input tokens
    let outputPerMTok: Double        // $ per million output tokens
    let cacheWritePerMTok: Double    // $ per million cache write tokens
    let cacheReadPerMTok: Double     // $ per million cache read tokens
}

actor ClaudeInsightsAnalyzer {
    private static let pricingTable: [ModelPricing] = [
        ModelPricing(patterns: ["opus-4-6", "opus-4-5"], inputPerMTok: 15, outputPerMTok: 75, cacheWritePerMTok: 18.75, cacheReadPerMTok: 1.50),
        ModelPricing(patterns: ["sonnet-4-6", "sonnet-4-5"], inputPerMTok: 3, outputPerMTok: 15, cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30),
        ModelPricing(patterns: ["haiku-4-5"], inputPerMTok: 0.80, outputPerMTok: 4, cacheWritePerMTok: 1.00, cacheReadPerMTok: 0.08),
    ]

    // Fallback = Sonnet pricing
    private static let fallbackPricing = ModelPricing(patterns: [], inputPerMTok: 3, outputPerMTok: 15, cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30)

    // MARK: - Static helpers (testable)

    static func costForTokens(model: String, input: Int, output: Int, cacheWrite: Int, cacheRead: Int) -> Double {
        let pricing = pricingForModel(model)
        let inputCost = Double(input) / 1_000_000 * pricing.inputPerMTok
        let outputCost = Double(output) / 1_000_000 * pricing.outputPerMTok
        let cacheWriteCost = Double(cacheWrite) / 1_000_000 * pricing.cacheWritePerMTok
        let cacheReadCost = Double(cacheRead) / 1_000_000 * pricing.cacheReadPerMTok
        return inputCost + outputCost + cacheWriteCost + cacheReadCost
    }

    static func parseEvent(_ line: String) -> TranscriptEvent? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestampStr = json["timestamp"] as? String,
              let timestamp = parseTimestamp(timestampStr) else {
            return nil
        }

        if json["type"] as? String == "assistant",
           let message = json["message"] as? [String: Any],
           let model = message["model"] as? String,
           let usage = message["usage"] as? [String: Any] {
            return .usage(UsageEvent(
                timestamp: timestamp,
                model: model,
                input: usage["input_tokens"] as? Int ?? 0,
                output: usage["output_tokens"] as? Int ?? 0,
                cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0,
                cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                isSidechain: json["isSidechain"] as? Bool ?? false,
                sessionId: json["sessionId"] as? String,
                skill: json["attributionSkill"] as? String,
                agent: json["attributionAgent"] as? String
            ))
        }

        if let result = json["toolUseResult"] as? [String: Any],
           let hunks = result["structuredPatch"] as? [[String: Any]] {
            var added = 0
            var removed = 0
            for hunk in hunks {
                for hunkLine in hunk["lines"] as? [String] ?? [] {
                    if hunkLine.hasPrefix("+") { added += 1 }
                    else if hunkLine.hasPrefix("-") { removed += 1 }
                }
            }
            if added > 0 || removed > 0 {
                return .patch(PatchEvent(timestamp: timestamp, linesAdded: added, linesRemoved: removed))
            }
        }

        return nil
    }

    // MARK: - Private

    private static func pricingForModel(_ model: String) -> ModelPricing {
        let lowered = model.lowercased()
        for pricing in pricingTable {
            for pattern in pricing.patterns where lowered.contains(pattern) {
                return pricing
            }
        }
        return fallbackPricing
    }

    nonisolated(unsafe) private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let isoFormatterBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseTimestamp(_ str: String) -> Date? {
        isoFormatterWithFractional.date(from: str) ?? isoFormatterBasic.date(from: str)
    }
}
```

Note: `ModelPricing` temporarily exists in both this file and `ClaudeCostEstimator.swift` — that would be a duplicate-symbol compile error. In this task, DELETE the `ModelPricing` struct from `ClaudeCostEstimator.swift` (lines 3–9) — the estimator keeps compiling because `ModelPricing` still exists at module scope in the new file. The estimator itself is deleted in Task 3.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ClaudeInsightsParsingTests`
Expected: PASS (4 tests). Also run `swift build` — whole target must still compile.

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageTracker/Providers/ClaudeInsights.swift Sources/UsageTracker/Providers/ClaudeInsightsAnalyzer.swift Sources/UsageTracker/Providers/ClaudeCostEstimator.swift Tests/UsageTrackerTests/ClaudeInsightsAnalyzerTests.swift
git commit -m "feat(claude): add transcript event models and line parsing for usage insights

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Pure aggregation into ClaudeInsights

**Files:**
- Modify: `Sources/UsageTracker/Providers/ClaudeInsightsAnalyzer.swift`
- Test: `Tests/UsageTrackerTests/ClaudeInsightsAnalyzerTests.swift`

**Interfaces:**
- Consumes: `TranscriptEvent`, `UsageEvent`, `PatchEvent`, `ClaudeInsights` from Task 1.
- Produces: `static func aggregate(recentEvents: [TranscriptEvent], monthlyCost: Double, now: Date, calendar: Calendar = .current) -> ClaudeInsights` on `ClaudeInsightsAnalyzer`.

- [ ] **Step 1: Write failing aggregation tests**

Append to `Tests/UsageTrackerTests/ClaudeInsightsAnalyzerTests.swift`. A shared helper makes events terse:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ClaudeInsightsAggregationTests`
Expected: compile FAILURE — `aggregate` not defined.

- [ ] **Step 3: Implement aggregate**

Add to `ClaudeInsightsAnalyzer` (below `parseEvent`):

```swift
    static func aggregate(recentEvents: [TranscriptEvent], monthlyCost: Double, now: Date, calendar: Calendar = .current) -> ClaudeInsights {
        var insights = ClaudeInsights(monthlyCost: monthlyCost)

        let windowStart = now.addingTimeInterval(-24 * 3600)
        var usage24: [UsageEvent] = []
        var patches: [PatchEvent] = []
        for event in recentEvents {
            switch event {
            case .usage(let u) where u.timestamp >= windowStart && u.timestamp <= now:
                usage24.append(u)
            case .patch(let p) where p.timestamp <= now:
                patches.append(p)
            default:
                break
            }
        }

        let totalTokens = usage24.reduce(0) { $0 + $1.totalTokens }
        if totalTokens > 0 {
            let total = Double(totalTokens)

            let overTokens = usage24.filter { $0.contextTokens > 150_000 }.reduce(0) { $0 + $1.totalTokens }
            insights.contextShareOver150k = Double(overTokens) / total * 100

            var sessionTokens: [String: Int] = [:]
            var sessionSidechainTokens: [String: Int] = [:]
            for u in usage24 {
                guard let sid = u.sessionId else { continue }
                sessionTokens[sid, default: 0] += u.totalTokens
                if u.isSidechain { sessionSidechainTokens[sid, default: 0] += u.totalTokens }
            }
            let heavyTokens = sessionTokens
                .filter { sid, tokens in Double(sessionSidechainTokens[sid] ?? 0) / Double(tokens) > 0.25 }
                .values.reduce(0, +)
            insights.subagentShare = Double(heavyTokens) / total * 100

            var skillTokens: [String: Int] = [:]
            var agentTokens: [String: Int] = [:]
            for u in usage24 {
                if let skill = u.skill { skillTokens[skill, default: 0] += u.totalTokens }
                if u.isSidechain { agentTokens[u.agent ?? "other", default: 0] += u.totalTokens }
            }
            insights.skills = topShares(skillTokens, total: total)
            insights.subagents = topShares(agentTokens, total: total)
        }

        let dayStart = calendar.startOfDay(for: now)
        let todayUsage = usage24.filter { $0.timestamp >= dayStart }
        let todayPatches = patches.filter { $0.timestamp >= dayStart }
        if !todayUsage.isEmpty || !todayPatches.isEmpty {
            var today = TodayStats()
            for u in todayUsage {
                today.cost += costForTokens(model: u.model, input: u.input, output: u.output, cacheWrite: u.cacheWrite, cacheRead: u.cacheRead)
                today.totalTokens += u.totalTokens
            }
            today.sessionCount = Set(todayUsage.compactMap { $0.isSidechain ? nil : $0.sessionId }).count
            today.linesAdded = todayPatches.reduce(0) { $0 + $1.linesAdded }
            today.linesRemoved = todayPatches.reduce(0) { $0 + $1.linesRemoved }
            insights.today = today
        }

        return insights
    }

    private static func topShares(_ tokensByName: [String: Int], total: Double) -> [UsageShare] {
        tokensByName
            .map { UsageShare(name: $0.key, share: Double($0.value) / total * 100) }
            .sorted { $0.share != $1.share ? $0.share > $1.share : $0.name < $1.name }
            .prefix(5)
            .map { $0 }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClaudeInsightsAggregationTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageTracker/Providers/ClaudeInsightsAnalyzer.swift Tests/UsageTrackerTests/ClaudeInsightsAnalyzerTests.swift
git commit -m "feat(claude): aggregate transcript events into usage insights

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: File walk, incremental cache, and cost-estimator absorption

**Files:**
- Modify: `Sources/UsageTracker/Providers/ClaudeInsightsAnalyzer.swift`
- Delete: `Sources/UsageTracker/Providers/ClaudeCostEstimator.swift`
- Modify: `Sources/UsageTracker/Providers/ClaudeProvider.swift` (minimal: swap estimator for analyzer so the target compiles)
- Modify: `Tests/UsageTrackerTests/ClaudeCostEstimatorTests.swift` (retarget to analyzer)
- Test: `Tests/UsageTrackerTests/ClaudeInsightsAnalyzerTests.swift`

**Interfaces:**
- Consumes: `parseEvent`, `aggregate`, `costForTokens` from Tasks 1–2.
- Produces: `func analyze(projectsDir: URL? = nil, now: Date = Date()) async -> ClaudeInsights?` on the actor — returns nil when the projects directory doesn't exist. `ClaudeProvider` now holds `private let insightsAnalyzer = ClaudeInsightsAnalyzer()` and its returned `Provider.costEstimate` comes from `insights?.monthlyCost` (full ClaudeProvider integration is Task 5).

- [ ] **Step 1: Write failing tests for analyze()**

Append to `ClaudeInsightsAnalyzerTests.swift`:

```swift
@Suite("ClaudeInsightsAnalyzer file analysis")
struct ClaudeInsightsAnalyzeTests {

    func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func isoNow(offsetHours: Double = 0) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date().addingTimeInterval(offsetHours * 3600))
    }

    @Test("Returns nil for missing directory")
    func missingDir() async {
        let analyzer = ClaudeInsightsAnalyzer()
        let result = await analyzer.analyze(projectsDir: URL(fileURLWithPath: "/tmp/nope-\(UUID().uuidString)"))
        #expect(result == nil)
    }

    @Test("Empty directory yields zero-cost insights with no data")
    func emptyDir() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let analyzer = ClaudeInsightsAnalyzer()
        let result = await analyzer.analyze(projectsDir: dir)
        #expect(result != nil)
        #expect(result?.monthlyCost == 0)
        #expect(result?.contextShareOver150k == nil)
        #expect(result?.today == nil)
    }

    @Test("Aggregates cost and insights across files, including subagents subdirectory")
    func aggregatesFiles() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Main session file: 1M opus input = $15
        let mainLine = """
        {"type":"assistant","timestamp":"\(isoNow())","sessionId":"s1","isSidechain":false,"message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try mainLine.write(to: dir.appendingPathComponent("main.jsonl"), atomically: true, encoding: .utf8)

        // Subagent file nested like real transcripts: <session>/subagents/agent-x.jsonl
        let subDir = dir.appendingPathComponent("s1/subagents")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let sideLine = """
        {"type":"assistant","timestamp":"\(isoNow())","sessionId":"s1","isSidechain":true,"attributionAgent":"code-reviewer","message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try sideLine.write(to: subDir.appendingPathComponent("agent-x.jsonl"), atomically: true, encoding: .utf8)

        let analyzer = ClaudeInsightsAnalyzer()
        let result = await analyzer.analyze(projectsDir: dir)
        #expect(abs((result?.monthlyCost ?? 0) - 30.0) < 0.01)
        // session s1: 50% sidechain tokens → subagent-heavy → 100% share
        #expect(abs((result?.subagentShare ?? 0) - 100.0) < 0.01)
        #expect(result?.subagents.first?.name == "code-reviewer")
    }

    @Test("Cache: unchanged file is not re-parsed; changed file is")
    func cacheInvalidation() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("a.jsonl")

        let line = """
        {"type":"assistant","timestamp":"\(isoNow())","sessionId":"s1","message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try line.write(to: fileURL, atomically: true, encoding: .utf8)

        let analyzer = ClaudeInsightsAnalyzer()
        let first = await analyzer.analyze(projectsDir: dir)
        #expect(abs((first?.monthlyCost ?? 0) - 15.0) < 0.01)

        // Second run without changes: same result (cache path exercised)
        let second = await analyzer.analyze(projectsDir: dir)
        #expect(abs((second?.monthlyCost ?? 0) - 15.0) < 0.01)

        // Append another 1M-input line and bump mtime → re-parse picks it up
        let appended = line + "\n" + line
        try appended.write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: fileURL.path)

        let third = await analyzer.analyze(projectsDir: dir)
        #expect(abs((third?.monthlyCost ?? 0) - 30.0) < 0.01)
    }

    @Test("Malformed file mixed with valid file doesn't poison results")
    func malformedFileSkipped() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0xFF, 0xFE, 0x00]).write(to: dir.appendingPathComponent("garbage.jsonl"))
        let line = """
        {"type":"assistant","timestamp":"\(isoNow())","sessionId":"s1","message":{"model":"claude-sonnet-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try line.write(to: dir.appendingPathComponent("good.jsonl"), atomically: true, encoding: .utf8)

        let analyzer = ClaudeInsightsAnalyzer()
        let result = await analyzer.analyze(projectsDir: dir)
        #expect(abs((result?.monthlyCost ?? 0) - 3.0) < 0.01)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ClaudeInsightsAnalyzeTests`
Expected: compile FAILURE — `analyze` not defined.

- [ ] **Step 3: Implement analyze() with per-file cache**

Add to `ClaudeInsightsAnalyzer` (actor state + methods):

```swift
    private struct FileSummary {
        let modDate: Date
        let monthKey: String            // "yyyy-MM" the summary was computed for
        let monthCost: Double           // cost of usage events within that month
        let recentEvents: [TranscriptEvent]  // events within 25h of parse time
    }

    private var fileCache: [String: FileSummary] = [:]

    func analyze(projectsDir: URL? = nil, now: Date = Date()) async -> ClaudeInsights? {
        let resolvedDir = projectsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard FileManager.default.fileExists(atPath: resolvedDir.path) else { return nil }

        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return nil
        }
        let monthKey = Self.monthKey(for: monthStart)
        // Keep a 25h buffer so the 24h window and "today" are always fully covered.
        let recentCutoff = now.addingTimeInterval(-25 * 3600)
        // A file not touched since before both cutoffs can contribute nothing.
        let walkCutoff = min(monthStart, recentCutoff)

        let jsonlFiles: [(url: URL, modDate: Date)] = {
            guard let enumerator = FileManager.default.enumerator(
                at: resolvedDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            var result: [(URL, Date)] = []
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl" else { continue }
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modDate = resourceValues.contentModificationDate,
                      modDate >= walkCutoff else { continue }
                result.append((fileURL, modDate))
            }
            return result
        }()

        var totalCost: Double = 0
        var recentEvents: [TranscriptEvent] = []

        for (fileURL, modDate) in jsonlFiles {
            let path = fileURL.path
            let summary: FileSummary
            if let cached = fileCache[path], cached.modDate == modDate, cached.monthKey == monthKey {
                summary = cached
            } else {
                summary = Self.parseFile(at: fileURL, modDate: modDate, monthKey: monthKey,
                                         monthStart: monthStart, now: now, recentCutoff: recentCutoff)
                fileCache[path] = summary
            }
            totalCost += summary.monthCost
            recentEvents.append(contentsOf: summary.recentEvents)
        }

        return Self.aggregate(recentEvents: recentEvents, monthlyCost: totalCost, now: now, calendar: calendar)
    }

    private static func parseFile(at url: URL, modDate: Date, monthKey: String,
                                  monthStart: Date, now: Date, recentCutoff: Date) -> FileSummary {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return FileSummary(modDate: modDate, monthKey: monthKey, monthCost: 0, recentEvents: [])
        }

        var monthCost: Double = 0
        var recentEvents: [TranscriptEvent] = []
        content.enumerateLines { line, _ in
            guard let event = parseEvent(line) else { return }
            switch event {
            case .usage(let u):
                if u.timestamp >= monthStart && u.timestamp <= now {
                    monthCost += costForTokens(model: u.model, input: u.input, output: u.output,
                                               cacheWrite: u.cacheWrite, cacheRead: u.cacheRead)
                }
                if u.timestamp >= recentCutoff { recentEvents.append(event) }
            case .patch(let p):
                if p.timestamp >= recentCutoff { recentEvents.append(event) }
            }
        }
        return FileSummary(modDate: modDate, monthKey: monthKey, monthCost: monthCost, recentEvents: recentEvents)
    }

    private static func monthKey(for monthStart: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.timeZone = .current
        return f.string(from: monthStart)
    }
```

- [ ] **Step 4: Delete ClaudeCostEstimator and swap it in ClaudeProvider**

Delete `Sources/UsageTracker/Providers/ClaudeCostEstimator.swift` (`git rm`). In `ClaudeProvider.swift`:

Replace (line 11):
```swift
    private let costEstimator = ClaudeCostEstimator()
```
with:
```swift
    private let insightsAnalyzer = ClaudeInsightsAnalyzer()
```

Replace (lines 177–178):
```swift
        // Cost estimation (caller controls visibility via showCostEstimate)
        let costEstimate = await costEstimator.estimateCurrentMonth()
```
with:
```swift
        // Cost estimation + local usage insights (caller controls cost visibility via showCostEstimate)
        let insights = await insightsAnalyzer.analyze()
```

Replace (line 187):
```swift
            costEstimate: costEstimate?.totalCost
```
with:
```swift
            costEstimate: insights?.monthlyCost
```

- [ ] **Step 5: Retarget the old estimator tests**

Rewrite `Tests/UsageTrackerTests/ClaudeCostEstimatorTests.swift` — same pricing coverage, pointed at the analyzer (the suite keeps its file but gets a new name). Replace the entire file content with:

```swift
import Testing
import Foundation
@testable import UsageTracker

@Suite("ClaudeInsightsAnalyzer pricing")
struct ClaudeInsightsPricingTests {

    @Test("Opus model pricing")
    func opusPricing() {
        let cost = ClaudeInsightsAnalyzer.costForTokens(
            model: "claude-opus-4-6", input: 1_000_000, output: 1_000_000,
            cacheWrite: 1_000_000, cacheRead: 1_000_000)
        // input: $15 + output: $75 + cacheWrite: $18.75 + cacheRead: $1.50 = $110.25
        #expect(abs(cost - 110.25) < 0.01)
    }

    @Test("Sonnet model pricing")
    func sonnetPricing() {
        let cost = ClaudeInsightsAnalyzer.costForTokens(
            model: "claude-sonnet-4-5-20250929", input: 1_000_000, output: 1_000_000,
            cacheWrite: 0, cacheRead: 0)
        #expect(abs(cost - 18.0) < 0.01)
    }

    @Test("Haiku model pricing")
    func haikuPricing() {
        let cost = ClaudeInsightsAnalyzer.costForTokens(
            model: "claude-haiku-4-5-20251001", input: 1_000_000, output: 1_000_000,
            cacheWrite: 0, cacheRead: 0)
        #expect(abs(cost - 4.80) < 0.01)
    }

    @Test("Unknown model falls back to Sonnet pricing")
    func unknownModelFallback() {
        let cost = ClaudeInsightsAnalyzer.costForTokens(
            model: "claude-unknown-99", input: 1_000_000, output: 1_000_000,
            cacheWrite: 0, cacheRead: 0)
        #expect(abs(cost - 18.0) < 0.01)
    }

    @Test("Case insensitive model matching")
    func caseInsensitive() {
        let cost = ClaudeInsightsAnalyzer.costForTokens(
            model: "Claude-OPUS-4-6", input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0)
        #expect(abs(cost - 15.0) < 0.01)
    }

    @Test("Zero tokens returns zero cost")
    func zeroTokens() {
        let cost = ClaudeInsightsAnalyzer.costForTokens(
            model: "claude-opus-4-6", input: 0, output: 0, cacheWrite: 0, cacheRead: 0)
        #expect(cost == 0.0)
    }

    @Test("Lines from previous months don't count toward monthly cost")
    func skipsOldLines() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let oldLine = """
        {"type":"assistant","timestamp":"2025-01-15T10:00:00.000Z","message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try oldLine.write(to: dir.appendingPathComponent("old.jsonl"), atomically: true, encoding: .utf8)

        let analyzer = ClaudeInsightsAnalyzer()
        let result = await analyzer.analyze(projectsDir: dir)
        #expect(result?.monthlyCost == 0.0)
    }
}
```

Optionally rename the file to `ClaudeInsightsPricingTests.swift` with `git mv` — do it, matching suite to filename.

- [ ] **Step 6: Run the full test suite**

Run: `swift test`
Expected: ALL PASS — new analyze tests, retargeted pricing tests, and every pre-existing suite (Claude2xDetector, ClaudeProvider, Models, SettingsViewModel).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(claude): incremental transcript analysis replaces cost estimator

One cached pass over ~/.claude/projects now produces monthly cost and
usage insights; unchanged files are never re-parsed.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Model extensions and bar threshold change

**Files:**
- Modify: `Sources/UsageTracker/Models.swift`
- Modify: `Sources/UsageTracker/Views/ProviderRow.swift` (valueText rendering only)
- Test: `Tests/UsageTrackerTests/ModelsTests.swift`

**Interfaces:**
- Consumes: `ClaudeInsights` from Task 1.
- Produces: `UsageItem` gains `var resetsAt: Date? = nil` and `var valueText: String? = nil`; `Provider` gains `var planLabel: String? = nil` and `var insights: ClaudeInsights? = nil`. Color thresholds become 60/85. Existing positional initializers keep working (new members have defaults and come after `resetLabel`).

- [ ] **Step 1: Update threshold tests and add new-field tests (failing first)**

In `Tests/UsageTrackerTests/ModelsTests.swift`, replace the `usageItemColor` test and add coverage:

```swift
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

    @Test("UsageItem valueText and resetsAt default to nil and are settable")
    func usageItemNewFields() {
        let plain = UsageItem(label: "T", current: 1, limit: 100, resetLabel: nil)
        #expect(plain.valueText == nil)
        #expect(plain.resetsAt == nil)

        let date = Date()
        let rich = UsageItem(label: "T", current: 12, limit: 50, resetLabel: nil, resetsAt: date, valueText: "$12 of $50")
        #expect(rich.valueText == "$12 of $50")
        #expect(rich.resetsAt == date)
        #expect(abs(rich.percentage - 24.0) < 0.01)
    }

    @Test("Provider planLabel and insights default to nil")
    func providerNewFields() {
        let provider = Provider(id: "t", name: "T", icon: "star", items: [], status: .loaded)
        #expect(provider.planLabel == nil)
        #expect(provider.insights == nil)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UsageItemTests`
Expected: compile FAILURE (`resetsAt`/`valueText` unknown), and after stubs, threshold assertion failures.

- [ ] **Step 3: Implement the model changes**

In `Models.swift`, `UsageItem` becomes:

```swift
struct UsageItem: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let current: Double
    let limit: Double
    let resetLabel: String?
    var resetsAt: Date? = nil
    var valueText: String? = nil     // overrides the "NN%" value display (e.g. "$12 of $50")

    var percentage: Double {
        guard limit > 0 else { return 0 }
        return (current / limit) * 100
    }

    var gradientColors: (start: Color, end: Color) {
        switch percentage {
        case 0..<60:
            return (Color(red: 0.204, green: 0.780, blue: 0.349),  // #34C759
                    Color(red: 0.188, green: 0.820, blue: 0.345))  // #30D158
        case 60..<85:
            return (Color(red: 1.0, green: 0.624, blue: 0.039),    // #FF9F0A
                    Color(red: 1.0, green: 0.702, blue: 0.251))    // #FFB340
        default:
            return (Color(red: 1.0, green: 0.231, blue: 0.188),    // #FF3B30
                    Color(red: 1.0, green: 0.412, blue: 0.380))    // #FF6961
        }
    }

    var color: Color {
        gradientColors.start
    }
}
```

In `Provider`, add after `costEstimate`:

```swift
    var planLabel: String? = nil             // e.g. "Max" from subscriptionType (Claude only)
    var insights: ClaudeInsights? = nil      // local transcript insights (Claude only)
```

And update `Provider.displayColor` thresholds to match:

```swift
    var displayColor: Color {
        switch maxPercentage {
        case 0..<60: return .green
        case 60..<85: return .yellow
        default: return .red
        }
    }
```

- [ ] **Step 4: Render valueText in UsageItemRow**

In `ProviderRow.swift`, `UsageItemRow`, replace the percentage text block:

```swift
            Text("\(Int(item.percentage))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .trailing)
```

with:

```swift
            Text(item.valueText ?? "\(Int(item.percentage))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(minWidth: 32, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
```

(`minWidth` + `fixedSize` lets "$12 of $50" take the room it needs; the bar flexes.)

- [ ] **Step 5: Run tests and build**

Run: `swift test && swift build`
Expected: ALL PASS, clean build.

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageTracker/Models.swift Sources/UsageTracker/Views/ProviderRow.swift Tests/UsageTrackerTests/ModelsTests.swift
git commit -m "feat(models): valueText/resetsAt on UsageItem, planLabel/insights on Provider, 60/85 color bands

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: ClaudeProvider integration — extra credits, plan label, reset dates, insights

**Files:**
- Modify: `Sources/UsageTracker/Providers/ClaudeProvider.swift`
- Test: `Tests/UsageTrackerTests/ClaudeProviderTests.swift`

**Interfaces:**
- Consumes: `UsageItem.valueText/resetsAt`, `Provider.planLabel/insights` (Task 4), `insightsAnalyzer.analyze()` (Task 3).
- Produces: `static func extraCreditsItem(from: UsageResponse.ExtraUsage?) -> UsageItem?` and `static func planLabel(from subscriptionType: String?) -> String?` on `ClaudeProvider`; the returned Provider carries `insights`, `planLabel`, an optional "Extra credits" item, and `resetsAt` dates on items.

- [ ] **Step 1: Write failing tests**

Append to `Tests/UsageTrackerTests/ClaudeProviderTests.swift` (inside the existing suite or a new one, matching the file's existing style):

```swift
@Suite("ClaudeProvider extra credits and plan label")
struct ClaudeProviderExtrasTests {

    @Test("Extra credits item maps used/limit and formats dollars")
    func extraCreditsMapping() {
        let extra = ClaudeProvider.UsageResponse.ExtraUsage(is_enabled: true, used_credits: 12, monthly_limit: 50)
        let item = ClaudeProvider.extraCreditsItem(from: extra)
        #expect(item != nil)
        #expect(item?.label == "Extra credits")
        #expect(item?.valueText == "$12 of $50")
        #expect(abs((item?.percentage ?? 0) - 24.0) < 0.01)
    }

    @Test("Extra credits hidden when disabled, missing, or zero limit")
    func extraCreditsHidden() {
        #expect(ClaudeProvider.extraCreditsItem(from: nil) == nil)
        #expect(ClaudeProvider.extraCreditsItem(from: .init(is_enabled: false, used_credits: 5, monthly_limit: 50)) == nil)
        #expect(ClaudeProvider.extraCreditsItem(from: .init(is_enabled: true, used_credits: 5, monthly_limit: 0)) == nil)
        #expect(ClaudeProvider.extraCreditsItem(from: .init(is_enabled: true, used_credits: 5, monthly_limit: nil)) == nil)
    }

    @Test("Fractional dollars keep two decimals")
    func extraCreditsFractional() {
        let extra = ClaudeProvider.UsageResponse.ExtraUsage(is_enabled: true, used_credits: 12.5, monthly_limit: 50)
        #expect(ClaudeProvider.extraCreditsItem(from: extra)?.valueText == "$12.50 of $50")
    }

    @Test("Plan label mapping")
    func planLabels() {
        #expect(ClaudeProvider.planLabel(from: "max") == "Max")
        #expect(ClaudeProvider.planLabel(from: "pro") == "Pro")
        #expect(ClaudeProvider.planLabel(from: "enterprise") == "Enterprise")
        #expect(ClaudeProvider.planLabel(from: "some_new_tier") == "Some_new_tier".capitalized)
        #expect(ClaudeProvider.planLabel(from: nil) == nil)
        #expect(ClaudeProvider.planLabel(from: "") == nil)
    }
}
```

Note: if `UsageResponse.ExtraUsage` lacks a memberwise initializer accessible from tests (it's inside an actor but types are internal — `@testable import` covers it), this compiles as-is.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ClaudeProviderExtrasTests`
Expected: compile FAILURE — `extraCreditsItem`/`planLabel` not defined.

- [ ] **Step 3: Implement in ClaudeProvider**

Add static helpers to `ClaudeProvider`:

```swift
    static func extraCreditsItem(from extra: UsageResponse.ExtraUsage?) -> UsageItem? {
        guard let extra, extra.is_enabled == true,
              let limit = extra.monthly_limit, limit > 0 else { return nil }
        let used = extra.used_credits ?? 0
        return UsageItem(
            label: "Extra credits",
            current: used,
            limit: limit,
            resetLabel: nil,
            valueText: "\(formatDollars(used)) of \(formatDollars(limit))"
        )
    }

    static func formatDollars(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "$%.0f", value)
            : String(format: "$%.2f", value)
    }

    static func planLabel(from subscriptionType: String?) -> String? {
        guard let type = subscriptionType, !type.isEmpty else { return nil }
        switch type.lowercased() {
        case "max": return "Max"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return type.capitalized
        }
    }
```

Split `formatResetTime` into a date parser plus the existing relative formatter, so items can carry both:

```swift
    private func parseResetDate(_ isoString: String?) -> Date? {
        guard let isoString = isoString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString)
    }

    private func relativeResetLabel(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return nil }
        let hours = Int(diff / 3600)
        let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 24 {
            return "\(hours / 24)d"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
```

Delete the old `formatResetTime`. Update the four item constructions in `fetchUsage()` to the pattern:

```swift
        if let fiveHour = usage.five_hour, let utilization = fiveHour.utilization {
            let resetDate = parseResetDate(fiveHour.resets_at)
            items.append(UsageItem(
                label: "Session",
                current: utilization,
                limit: 100,
                resetLabel: relativeResetLabel(resetDate),
                resetsAt: resetDate
            ))
        }
```

(Repeat identically for `seven_day` → "Weekly", `seven_day_sonnet` → "Sonnet", `seven_day_opus` → "Opus".)

After the Opus block, append the extra-credits item with a verification log (dollar units are an assumption — see "Verified transcript facts"):

```swift
        if let extraItem = Self.extraCreditsItem(from: usage.extra_usage) {
            Log.info("Claude extra usage raw values: used=\(usage.extra_usage?.used_credits ?? -1) limit=\(usage.extra_usage?.monthly_limit ?? -1)")
            items.append(extraItem)
        }
```

Finally, the loaded-Provider return gains the new fields:

```swift
        return Provider(
            id: "claude",
            name: "Claude",
            icon: "brain",
            items: items,
            status: items.isEmpty ? .error("No usage data") : .loaded,
            boostStatus: boostStatus,
            costEstimate: insights?.monthlyCost,
            planLabel: Self.planLabel(from: oauth.subscriptionType),
            insights: insights
        )
```

(Check `Provider`'s member order from Task 4 — `planLabel` and `insights` come after `costEstimate`; the memberwise init call above must list members in declaration order.)

- [ ] **Step 4: Run the full test suite**

Run: `swift test`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageTracker/Providers/ClaudeProvider.swift Tests/UsageTrackerTests/ClaudeProviderTests.swift
git commit -m "feat(claude): extra-credits item, plan label, reset dates, insights on Provider

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Detail-page formatters (TDD)

**Files:**
- Create: `Sources/UsageTracker/Views/ClaudeDetailView.swift` (formatters only in this task)
- Test: `Tests/UsageTrackerTests/ClaudeDetailViewTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `enum ClaudeDetailFormat` with `static func absoluteResetLabel(for date: Date, now: Date, calendar: Calendar) -> String` and `static func tokenCount(_ count: Int) -> String`. Task 7's view uses both.

- [ ] **Step 1: Write failing formatter tests**

Create `Tests/UsageTrackerTests/ClaudeDetailViewTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ClaudeDetailFormatTests`
Expected: compile FAILURE — `ClaudeDetailFormat` not defined.

- [ ] **Step 3: Implement the formatters**

Create `Sources/UsageTracker/Views/ClaudeDetailView.swift`:

```swift
import AppKit
import SwiftUI

enum ClaudeDetailFormat {
    /// "resets 4:40 PM" for today, "resets Sat 11 PM" otherwise.
    static func absoluteResetLabel(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "h:mm a"
        } else {
            let minute = calendar.component(.minute, from: date)
            formatter.dateFormat = minute == 0 ? "EEE h a" : "EEE h:mm a"
        }
        return "resets \(formatter.string(from: date))"
    }

    /// 123 → "123", 45600 → "46k", 1200000 → "1.2M"
    static func tokenCount(_ count: Int) -> String {
        switch count {
        case ..<1000:
            return "\(count)"
        case ..<999_500:
            return "\(Int((Double(count) / 1000).rounded()))k"
        default:
            let millions = Double(count) / 1_000_000
            let formatted = millions >= 10
                ? "\(Int(millions.rounded()))"
                : String(format: "%.1f", millions).replacingOccurrences(of: ".0", with: "")
            return "\(formatted)M"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClaudeDetailFormatTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageTracker/Views/ClaudeDetailView.swift Tests/UsageTrackerTests/ClaudeDetailViewTests.swift
git commit -m "feat(detail): absolute reset and token-count formatters

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: ClaudeDetailView UI, navigation, and popover sizing

**Files:**
- Modify: `Sources/UsageTracker/Views/ClaudeDetailView.swift` (add the view)
- Modify: `Sources/UsageTracker/Views/MenuBarView.swift` (navigation)
- Modify: `Sources/UsageTracker/Views/ProviderRow.swift` (drill-in chevron entry point)
- Modify: `Sources/UsageTracker/StatusBarController.swift` (self-sizing popover)

**Interfaces:**
- Consumes: `ClaudeDetailFormat` (Task 6), `Provider.insights/planLabel`, `UsageItem.resetsAt/valueText` (Tasks 4–5), `AppState` (existing).
- Produces: `ClaudeDetailView(appState:onBack:)`; `ProviderRow` gains `var onOpenDetail: (() -> Void)? = nil`.

- [ ] **Step 1: Build the detail view**

Append to `ClaudeDetailView.swift`:

```swift
struct ClaudeDetailView: View {
    @ObservedObject var appState: AppState
    var onBack: () -> Void

    private var provider: Provider? {
        appState.providers.first { $0.id == "claude" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 10)

            if let provider {
                barsSection(provider)

                if let insights = provider.insights {
                    sectionDivider
                    insightsSection(insights)

                    if !insights.skills.isEmpty || !insights.subagents.isEmpty {
                        sectionDivider
                        breakdownSection(insights)
                    }

                    if let today = insights.today {
                        sectionDivider
                        todaySection(today)
                    }
                }
            } else {
                Text("Claude is not connected")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }

            sectionDivider
            footerLink
        }
        .padding(12)
        .frame(width: 340)
        .onExitCommand { onBack() }
    }

    private var sectionDivider: some View {
        Divider().padding(.vertical, 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.icon)

            Image(systemName: "brain")
                .font(.system(size: 12))
                .foregroundColor(provider?.displayColor ?? .secondary)

            Text("Claude")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if let plan = provider?.planLabel {
                Text(plan)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            }
        }
    }

    private func barsSection(_ provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(provider.items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(item.label)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 88, alignment: .leading)

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.primary.opacity(0.06))
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(LinearGradient(
                                        colors: [item.gradientColors.start, item.gradientColors.end],
                                        startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geometry.size.width * min(item.percentage / 100, 1))
                            }
                        }
                        .frame(height: 10)

                        Text(item.valueText ?? "\(Int(item.percentage))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(item.percentage >= 85 ? item.color : .secondary)
                            .frame(minWidth: 36, alignment: .trailing)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    if let resetsAt = item.resetsAt {
                        Text(ClaudeDetailFormat.absoluteResetLabel(for: resetsAt))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .padding(.leading, 96)
                    }
                }
            }
        }
    }

    private func insightsSection(_ insights: ClaudeInsights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Insights · last 24h · approx.")

            let contextWarning = (insights.contextShareOver150k ?? 0) >= ClaudeInsights.contextWarningThreshold
            let subagentWarning = (insights.subagentShare ?? 0) >= ClaudeInsights.subagentWarningThreshold

            if contextWarning, let share = insights.contextShareOver150k {
                insightRow(
                    stat: "\(Int(share))% of usage at >150k context",
                    hint: "/compact mid-task, /clear between tasks"
                )
            }
            if subagentWarning, let share = insights.subagentShare {
                insightRow(
                    stat: "\(Int(share))% from subagent-heavy sessions",
                    hint: "Be deliberate about spawning subagents"
                )
            }
            if !contextWarning && !subagentWarning {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("No usage warnings — last 24h looks efficient")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func insightRow(stat: String, hint: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(stat)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func breakdownSection(_ insights: ClaudeInsights) -> some View {
        HStack(alignment: .top, spacing: 16) {
            if !insights.skills.isEmpty {
                breakdownColumn(title: "Top skills", shares: insights.skills)
            }
            if !insights.subagents.isEmpty {
                breakdownColumn(title: "Top agents", shares: insights.subagents)
            }
        }
    }

    private func breakdownColumn(title: String, shares: [UsageShare]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(title)
            ForEach(shares, id: \.name) { share in
                HStack(spacing: 4) {
                    Text(share.name)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(share.name)
                    Spacer(minLength: 4)
                    Text(share.share < 1 ? "<1%" : "\(Int(share.share))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func todaySection(_ today: TodayStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Today")
            Text("\(ClaudeProvider.formatDollars(today.cost.rounded(toPlaces: 2))) est · \(today.sessionCount) session\(today.sessionCount == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .monospacedDigit()
            Text("\(ClaudeDetailFormat.tokenCount(today.totalTokens)) tokens · +\(today.linesAdded) / −\(today.linesRemoved) lines")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    private var footerLink: some View {
        HStack {
            Spacer()
            Button {
                NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
            } label: {
                HStack(spacing: 3) {
                    Text("Open claude.ai usage")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .kerning(0.5)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
```

Note: `ClaudeProvider.formatDollars` was made `static` (not actor-isolated) in Task 5, so calling it from the view is legal. `today.cost` is rounded to cents first so whole-dollar values render as "$4" and fractional as "$4.12".

- [ ] **Step 2: Add navigation to MenuBarView**

In `MenuBarView.swift`, add state and restructure `body`:

```swift
struct MenuBarView: View {
    @ObservedObject var appState: AppState

    private enum Screen: Equatable {
        case list
        case claudeDetail
    }

    @State private var screen: Screen = .list

    var body: some View {
        Group {
            switch screen {
            case .list:
                listScreen
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .claudeDetail:
                ClaudeDetailView(appState: appState) {
                    withAnimation(.easeInOut(duration: 0.2)) { screen = .list }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: screen)
        .task {
            await appState.refresh()
        }
    }

    private var listScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.visibleProviders.isEmpty && !appState.isLoading {
                emptyState
            } else {
                providerList
            }

            Divider()
                .padding(.vertical, 8)

            footer
        }
        .padding(12)
        .frame(width: 340)
    }
    // ... emptyState, maxProvider, displayedProvider, footer unchanged ...
}
```

(The old `body`'s `VStack` content moves into `listScreen`; `.padding(12)`/`.frame(width: 340)` move with it; `.task` stays on the outer `Group` so refresh fires regardless of screen.)

In `providerList`, pass the drill-in handler for Claude only:

```swift
                    ProviderRow(
                        provider: $appState.providers[index],
                        isDisplayedInBar: provider.id == displayedProvider?.id && appState.maxPercentage > 0,
                        isPinned: { itemLabel in
                            appState.isPinned(providerId: provider.id, itemLabel: itemLabel)
                        },
                        onTogglePin: { itemLabel in
                            appState.togglePin(providerId: provider.id, itemLabel: itemLabel)
                        },
                        onOpenDetail: provider.id == "claude" ? {
                            withAnimation(.easeInOut(duration: 0.2)) { screen = .claudeDetail }
                        } : nil
                    )
```

- [ ] **Step 3: Add the hover-revealed chevron to ProviderRow**

In `ProviderRow.swift`:

Add the property after `onTogglePin`:

```swift
    var onOpenDetail: (() -> Void)? = nil
    @State private var isCardHovered = false
```

Add `.onHover` to the outer `VStack`'s `.background(...)` chain (after the existing `.background`):

```swift
        .onHover { hovering in
            isCardHovered = hovering
        }
```

In `providerHeader`'s `HStack`, insert the chevron between `Spacer()` and the status `switch`:

```swift
                Spacer()

                if let onOpenDetail, isCardHovered {
                    Button(action: onOpenDetail) {
                        Image(systemName: "chevron.right.circle")
                    }
                    .buttonStyle(.icon)
                    .help("Claude details & insights")
                }

                switch provider.status {
```

Important: the header is itself a `Button` — a `Button` nested inside a `Button` label doesn't receive clicks. Restructure `providerHeader` so the expand/collapse tap and the chevron are siblings: change the header `Button { ... } label: { HStack { ...everything except the chevron... } }` to an `HStack` where the expand/collapse content is wrapped in the `Button(action:)` with `.buttonStyle(.plain)` and the chevron `Button` sits beside it:

```swift
    private var providerHeader: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    provider.isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: provider.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    Image(systemName: provider.icon)
                        .font(.system(size: 12))
                        .foregroundColor(provider.displayColor)

                    Text(provider.name)
                        .font(.system(size: 13, weight: .medium))

                    // (existing boostStatus badge block stays here unchanged)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onOpenDetail, isCardHovered {
                Button(action: onOpenDetail) {
                    Image(systemName: "chevron.right.circle")
                }
                .buttonStyle(.icon)
                .help("Claude details & insights")
            }

            // (existing status switch stays here unchanged)
        }
    }
```

- [ ] **Step 4: Fix popover sizing in StatusBarController**

In `StatusBarController.swift`, replace:

```swift
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
```

with:

```swift
        popover = NSPopover()
        popover.behavior = .transient
        let hosting = NSHostingController(rootView: contentView)
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
```

- [ ] **Step 5: Build and verify manually**

Run: `swift build && swift test`
Expected: clean build, all tests pass.

Then run the app and check each item:

```bash
.build/debug/UsageTracker
```

Manual checklist (all must hold):
1. Popover opens at the right width (no clipped/blank margins — sizing fix works).
2. Hovering the Claude card reveals a `chevron.right.circle` button; other providers never show it.
3. Clicking it slides to the detail page; bars show with absolute "resets …" captions.
4. Insights section shows either warnings or the all-clear line; skills/agents columns show real 24h data (this machine has active transcripts).
5. Today section shows plausible cost/sessions/tokens/lines.
6. Back button and Esc both return to the list; expand/collapse on the Claude header still works.
7. "Open claude.ai usage" opens the browser.

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageTracker/Views/ClaudeDetailView.swift Sources/UsageTracker/Views/MenuBarView.swift Sources/UsageTracker/Views/ProviderRow.swift Sources/UsageTracker/StatusBarController.swift
git commit -m "feat(ui): Claude detail page with insights, navigation, self-sizing popover

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Main-list polish

**Files:**
- Modify: `Sources/UsageTracker/Views/ProviderRow.swift`

**Interfaces:**
- Consumes: `Provider.insights.hasWarnings` (Tasks 1/5).
- Produces: visual changes only — no new API.

- [ ] **Step 1: Apply the polish edits**

All in `ProviderRow.swift`:

a) **Warning badge** — in `providerHeader`, right after the `Text(provider.name)` line (before the boost badge):

```swift
                    if provider.insights?.hasWarnings == true {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                            .help("Usage insights available — open Claude details")
                    }
```

b) **Monospaced digits on the header percentage** — in the `.loaded` case:

```swift
                case .loaded:
                    Text("\(Int(provider.maxPercentage))%")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
```

c) **Red value label in the red band** — in `UsageItemRow`, the value `Text` from Task 4 gets a conditional color:

```swift
            Text(item.valueText ?? "\(Int(item.percentage))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(item.percentage >= 85 ? item.color : .secondary)
                .frame(minWidth: 32, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
```

d) **Label column width** — in `UsageItemRow`, the label `HStack`'s frame:

```swift
            .frame(width: 92, alignment: .leading)
```

e) **Monospaced digits on the reset label** — in `UsageItemRow`:

```swift
            Text(item.resetLabel ?? "")
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .trailing)
```

- [ ] **Step 2: Build, test, and eyeball**

Run: `swift build && swift test`
Expected: clean build, all tests pass.

Run `.build/debug/UsageTracker` and verify: ⚠ appears on the Claude row when a warning is active (compare against the detail page), numbers don't shift on refresh, an item at ≥85% (if any) shows a red value.

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageTracker/Views/ProviderRow.swift
git commit -m "polish(ui): warning badge, monospaced digits, red-band value labels, wider labels

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Docs and final verification

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md` (Features list, if it enumerates them)

- [ ] **Step 1: Update CLAUDE.md**

In `## Architecture → Key Files`, add:

```markdown
- `Providers/ClaudeInsightsAnalyzer.swift` - Incremental transcript analysis: monthly cost + 24h usage insights (replaces ClaudeCostEstimator)
- `Views/ClaudeDetailView.swift` - Claude drill-in page: limit bars, insights, skills/agents breakdown, today stats
```

Remove any stale mention of `ClaudeCostEstimator`. In `## Features`, add:

```markdown
- Claude detail page: extra-usage credits, 24h insights (context size, subagent share), top skills/agents, today stats
```

In the Provider Status table, update the Claude row's "What it shows" to: `Session %, Weekly %, Sonnet %, Opus %, extra credits, cost estimate, usage insights`.

- [ ] **Step 2: Update README.md features section** (only if it lists features — mirror the CLAUDE.md wording).

- [ ] **Step 3: Full verification**

```bash
swift test 2>&1 | tail -5
swift build 2>&1 | tail -3
```

Expected: all tests pass, clean build. Then dispatch the `verifier` agent with the original request ("incorporate Claude Code /usage data into UsageTracker: insights, skills/subagents breakdown, session stats, extra credits, via a drill-in detail page, plus popover polish") and the list of changes, and let it exercise the build/tests/app.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: document Claude usage insights feature

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
