# Claude 2x Indicator & API Cost Tracking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 2x capacity badge and estimated API cost row to the Claude provider card in UsageTracker.

**Architecture:** Two independent features sharing only the `Provider` model. `Claude2xDetector` is a pure struct reading a JSON config + system clock. `ClaudeCostEstimator` is an actor that recursively parses JSONL session files with file-level caching. Both integrate through `ClaudeProvider.fetchUsage()` and surface via `ProviderRow`.

**Tech Stack:** Swift 6.0, SwiftUI, Swift Testing (`@Test` / `#expect`), macOS 14+

**Spec:** `docs/superpowers/specs/2026-03-25-claude-2x-and-cost-tracking-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `Sources/UsageTracker/Providers/Claude2xDetector.swift` | Load `claude_2x.json`, evaluate time-based 2x rules |
| Create | `Sources/UsageTracker/Providers/ClaudeCostEstimator.swift` | Recursively parse `~/.claude/projects/**/*.jsonl`, compute monthly cost |
| Modify | `Sources/UsageTracker/Models.swift` | Add `costEstimate: Double?` and `is2xActive: Bool?` to `Provider` |
| Modify | `Sources/UsageTracker/Providers/ClaudeProvider.swift` | Call detector + estimator, populate new fields |
| Modify | `Sources/UsageTracker/Views/ProviderRow.swift` | Render 2x badge in header + cost row with separator |
| Create | `Tests/UsageTrackerTests/Claude2xDetectorTests.swift` | Unit tests for time-based detection |
| Create | `Tests/UsageTrackerTests/ClaudeCostEstimatorTests.swift` | Unit tests for JSONL parsing + cost math |

---

## Task 1: Add `is2xActive` and `costEstimate` fields to Provider model

**Files:**
- Modify: `Sources/UsageTracker/Models.swift:41-60`
- Modify: `Tests/UsageTrackerTests/ModelsTests.swift`

- [ ] **Step 1: Add fields to Provider**

In `Sources/UsageTracker/Models.swift`, add two optional fields to the `Provider` struct after `isExpanded`:

```swift
struct Provider: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    var items: [UsageItem]
    var status: ProviderStatus
    var isExpanded: Bool = true
    var is2xActive: Bool? = nil      // nil = no promo configured
    var costEstimate: Double? = nil   // API cost estimate in dollars
    // ... existing computed properties unchanged ...
}
```

- [ ] **Step 2: Build to verify no regressions**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds. Existing code doesn't set these fields so defaults apply.

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageTracker/Models.swift
git commit -m "feat: add is2xActive and costEstimate fields to Provider model"
```

---

## Task 2: Implement Claude2xDetector

**Files:**
- Create: `Sources/UsageTracker/Providers/Claude2xDetector.swift`
- Create: `Tests/UsageTrackerTests/Claude2xDetectorTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/UsageTrackerTests/Claude2xDetectorTests.swift`:

```swift
import Testing
import Foundation
@testable import UsageTracker

@Suite("Claude2xDetector Tests")
struct Claude2xDetectorTests {

    // Helper: create a config with a promo window around a given date
    private func configAround(_ date: Date, peakStart: Int = 8, peakEnd: Int = 14) -> Claude2xConfig {
        Claude2xConfig(
            promoStart: date.addingTimeInterval(-86400 * 3),
            promoEnd: date.addingTimeInterval(86400 * 3),
            peakHoursET: Claude2xConfig.PeakHours(start: peakStart, end: peakEnd)
        )
    }

    // Helper: create a date for a specific ET hour on a specific weekday
    // weekday: 1=Sun, 2=Mon, ... 7=Sat
    private func dateET(year: Int = 2026, month: Int = 3, day: Int, hour: Int, minute: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test("Returns nil when no config provided")
    func nilWhenNoConfig() {
        let detector = Claude2xDetector(config: nil)
        #expect(detector.check(at: Date()) == nil)
    }

    @Test("Returns nil when date is before promo window")
    func nilBeforePromo() {
        let promoStart = dateET(day: 20, hour: 0)
        let config = Claude2xConfig(
            promoStart: promoStart,
            promoEnd: promoStart.addingTimeInterval(86400 * 7),
            peakHoursET: .init(start: 8, end: 14)
        )
        let detector = Claude2xDetector(config: config)
        let beforePromo = promoStart.addingTimeInterval(-86400)
        #expect(detector.check(at: beforePromo) == nil)
    }

    @Test("Returns nil when date is after promo window")
    func nilAfterPromo() {
        let promoEnd = dateET(day: 20, hour: 23)
        let config = Claude2xConfig(
            promoStart: promoEnd.addingTimeInterval(-86400 * 7),
            promoEnd: promoEnd,
            peakHoursET: .init(start: 8, end: 14)
        )
        let detector = Claude2xDetector(config: config)
        let afterPromo = promoEnd.addingTimeInterval(86400)
        #expect(detector.check(at: afterPromo) == nil)
    }

    @Test("Weekend during promo is always 2x")
    func weekendAlways2x() {
        // March 22, 2026 is a Sunday
        let sunday10am = dateET(day: 22, hour: 10)
        let detector = Claude2xDetector(config: configAround(sunday10am))
        #expect(detector.check(at: sunday10am) == true)
    }

    @Test("Weekend during peak hours still 2x")
    func weekendPeakStill2x() {
        // March 21, 2026 is a Saturday
        let saturday11am = dateET(day: 21, hour: 11)
        let detector = Claude2xDetector(config: configAround(saturday11am))
        #expect(detector.check(at: saturday11am) == true)
    }

    @Test("Weekday during peak hours returns false")
    func weekdayPeakFalse() {
        // March 23, 2026 is a Monday
        let monday10am = dateET(day: 23, hour: 10)
        let detector = Claude2xDetector(config: configAround(monday10am))
        #expect(detector.check(at: monday10am) == false)
    }

    @Test("Weekday before peak returns true")
    func weekdayBeforePeakTrue() {
        // March 23, 2026 is a Monday
        let monday6am = dateET(day: 23, hour: 6)
        let detector = Claude2xDetector(config: configAround(monday6am))
        #expect(detector.check(at: monday6am) == true)
    }

    @Test("Weekday after peak returns true")
    func weekdayAfterPeakTrue() {
        // March 23, 2026 is a Monday
        let monday15 = dateET(day: 23, hour: 15)
        let detector = Claude2xDetector(config: configAround(monday15))
        #expect(detector.check(at: monday15) == true)
    }

    @Test("Weekday at exactly peak start returns false")
    func weekdayExactPeakStart() {
        let monday8am = dateET(day: 23, hour: 8)
        let detector = Claude2xDetector(config: configAround(monday8am))
        #expect(detector.check(at: monday8am) == false)
    }

    @Test("Weekday at exactly peak end returns true")
    func weekdayExactPeakEnd() {
        let monday14 = dateET(day: 23, hour: 14)
        let detector = Claude2xDetector(config: configAround(monday14))
        #expect(detector.check(at: monday14) == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter Claude2xDetector 2>&1 | tail -10`
Expected: Compilation errors — `Claude2xDetector`, `Claude2xConfig` don't exist yet.

- [ ] **Step 3: Implement Claude2xDetector**

Create `Sources/UsageTracker/Providers/Claude2xDetector.swift`:

```swift
import Foundation

struct Claude2xConfig: Codable, Sendable {
    let promoStart: Date
    let promoEnd: Date
    let peakHoursET: PeakHours

    struct PeakHours: Codable, Sendable {
        let start: Int  // hour in ET (0-23)
        let end: Int    // hour in ET (0-23)
    }
}

struct Claude2xDetector: Sendable {
    let config: Claude2xConfig?

    private static let etTimeZone = TimeZone(identifier: "America/New_York")!

    /// Returns nil if no promo configured or outside promo window.
    /// Returns true if 2x is active, false if within peak hours.
    func check(at date: Date = Date()) -> Bool? {
        guard let config = config else { return nil }

        // Outside promo window
        guard date >= config.promoStart && date <= config.promoEnd else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.etTimeZone

        let weekday = calendar.component(.weekday, from: date)
        // Sunday = 1, Saturday = 7
        let isWeekend = weekday == 1 || weekday == 7
        if isWeekend { return true }

        let hour = calendar.component(.hour, from: date)
        // Peak hours: [start, end) — no boost during peak
        if hour >= config.peakHoursET.start && hour < config.peakHoursET.end {
            return false
        }

        return true
    }

    /// Load config from ~/.usagetracker/claude_2x.json.
    /// Returns a detector with nil config if file doesn't exist or is malformed.
    static func loadFromDisk() -> Claude2xDetector {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker/claude_2x.json")

        guard let data = try? Data(contentsOf: url) else {
            return Claude2xDetector(config: nil)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let config = try? decoder.decode(Claude2xConfig.self, from: data) else {
            return Claude2xDetector(config: nil)
        }

        return Claude2xDetector(config: config)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter Claude2xDetector 2>&1 | tail -15`
Expected: All 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageTracker/Providers/Claude2xDetector.swift Tests/UsageTrackerTests/Claude2xDetectorTests.swift
git commit -m "feat: implement Claude2xDetector with time-based promo detection"
```

---

## Task 3: Implement ClaudeCostEstimator

**Files:**
- Create: `Sources/UsageTracker/Providers/ClaudeCostEstimator.swift`
- Create: `Tests/UsageTrackerTests/ClaudeCostEstimatorTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/UsageTrackerTests/ClaudeCostEstimatorTests.swift`:

```swift
import Testing
import Foundation
@testable import UsageTracker

@Suite("ClaudeCostEstimator Tests")
struct ClaudeCostEstimatorTests {

    // MARK: - Pricing logic tests

    @Test("Opus model pricing")
    func opusPricing() {
        let cost = ClaudeCostEstimator.costForTokens(
            model: "claude-opus-4-6",
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 1_000_000,
            cacheRead: 1_000_000
        )
        // input: $15 + output: $75 + cacheWrite: $18.75 + cacheRead: $1.50 = $110.25
        #expect(abs(cost - 110.25) < 0.01)
    }

    @Test("Sonnet model pricing")
    func sonnetPricing() {
        let cost = ClaudeCostEstimator.costForTokens(
            model: "claude-sonnet-4-5-20250929",
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 0,
            cacheRead: 0
        )
        // input: $3 + output: $15 = $18
        #expect(abs(cost - 18.0) < 0.01)
    }

    @Test("Haiku model pricing")
    func haikuPricing() {
        let cost = ClaudeCostEstimator.costForTokens(
            model: "claude-haiku-4-5-20251001",
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 0,
            cacheRead: 0
        )
        // input: $0.80 + output: $4 = $4.80
        #expect(abs(cost - 4.80) < 0.01)
    }

    @Test("Unknown model falls back to Sonnet pricing")
    func unknownModelFallback() {
        let cost = ClaudeCostEstimator.costForTokens(
            model: "claude-unknown-99",
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 0,
            cacheRead: 0
        )
        #expect(abs(cost - 18.0) < 0.01)
    }

    @Test("Case insensitive model matching")
    func caseInsensitive() {
        let cost = ClaudeCostEstimator.costForTokens(
            model: "Claude-OPUS-4-6",
            input: 1_000_000,
            output: 0,
            cacheWrite: 0,
            cacheRead: 0
        )
        #expect(abs(cost - 15.0) < 0.01)
    }

    @Test("Zero tokens returns zero cost")
    func zeroTokens() {
        let cost = ClaudeCostEstimator.costForTokens(
            model: "claude-opus-4-6",
            input: 0,
            output: 0,
            cacheWrite: 0,
            cacheRead: 0
        )
        #expect(cost == 0.0)
    }

    // MARK: - JSONL line parsing tests

    @Test("Parses valid assistant message with usage")
    func parsesValidLine() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = """
        {"message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":200,"cache_read_input_tokens":300}},"timestamp":"\(timestamp)","type":"assistant"}
        """
        let result = ClaudeCostEstimator.parseLine(line, monthStart: Date().addingTimeInterval(-86400), monthEnd: Date().addingTimeInterval(86400))
        #expect(result != nil)
        #expect(result?.model == "claude-opus-4-6")
        #expect(result?.input == 100)
        #expect(result?.output == 50)
        #expect(result?.cacheWrite == 200)
        #expect(result?.cacheRead == 300)
    }

    @Test("Skips non-assistant messages")
    func skipsNonAssistant() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = """
        {"message":{"role":"user"},"timestamp":"\(timestamp)","type":"human"}
        """
        let result = ClaudeCostEstimator.parseLine(line, monthStart: Date().addingTimeInterval(-86400), monthEnd: Date().addingTimeInterval(86400))
        #expect(result == nil)
    }

    @Test("Skips messages outside month range")
    func skipsOutsideMonth() {
        let oldDate = "2025-01-01T00:00:00.000Z"
        let line = """
        {"message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":100,"output_tokens":50}},"timestamp":"\(oldDate)","type":"assistant"}
        """
        let result = ClaudeCostEstimator.parseLine(line, monthStart: Date().addingTimeInterval(-86400), monthEnd: Date().addingTimeInterval(86400))
        #expect(result == nil)
    }

    @Test("Handles malformed JSON gracefully")
    func handlesMalformedJSON() {
        let result = ClaudeCostEstimator.parseLine("{invalid json", monthStart: Date(), monthEnd: Date())
        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ClaudeCostEstimator 2>&1 | tail -10`
Expected: Compilation errors — `ClaudeCostEstimator` doesn't exist yet.

- [ ] **Step 3: Implement ClaudeCostEstimator**

Create `Sources/UsageTracker/Providers/ClaudeCostEstimator.swift`:

```swift
import Foundation

struct ModelPricing: Sendable {
    let patterns: [String]           // case-insensitive substrings to match
    let inputPerMTok: Double         // $ per million input tokens
    let outputPerMTok: Double        // $ per million output tokens
    let cacheWritePerMTok: Double    // $ per million cache write tokens
    let cacheReadPerMTok: Double     // $ per million cache read tokens
}

struct ParsedUsage: Sendable {
    let model: String
    let input: Int
    let output: Int
    let cacheWrite: Int
    let cacheRead: Int
}

struct CostEstimate: Equatable, Sendable {
    let totalCost: Double
    let periodStart: Date
    let periodEnd: Date
}

actor ClaudeCostEstimator {
    private static let pricingTable: [ModelPricing] = [
        ModelPricing(patterns: ["opus-4-6", "opus-4-5"], inputPerMTok: 15, outputPerMTok: 75, cacheWritePerMTok: 18.75, cacheReadPerMTok: 1.50),
        ModelPricing(patterns: ["sonnet-4-6", "sonnet-4-5"], inputPerMTok: 3, outputPerMTok: 15, cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30),
        ModelPricing(patterns: ["haiku-4-5"], inputPerMTok: 0.80, outputPerMTok: 4, cacheWritePerMTok: 1.00, cacheReadPerMTok: 0.08),
    ]

    // Fallback = Sonnet pricing
    private static let fallbackPricing = ModelPricing(patterns: [], inputPerMTok: 3, outputPerMTok: 15, cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30)

    // File-level cache: [filePath: (modDate, cost)]
    private var fileCache: [String: (modDate: Date, cost: Double)] = [:]

    func estimateCurrentMonth() async -> CostEstimate? {
        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard FileManager.default.fileExists(atPath: projectsDir.path) else {
            return nil
        }

        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return nil
        }

        // Find all .jsonl files recursively
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var totalCost: Double = 0

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            // Check modification date — skip files not modified this month
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = resourceValues.contentModificationDate,
                  modDate >= monthStart else {
                continue
            }

            let filePath = fileURL.path

            // Check file cache
            if let cached = fileCache[filePath], cached.modDate == modDate {
                totalCost += cached.cost
                continue
            }

            // Parse the file
            let fileCost = Self.parseFile(at: fileURL, monthStart: monthStart, monthEnd: now)
            fileCache[filePath] = (modDate: modDate, cost: fileCost)
            totalCost += fileCost
        }

        return CostEstimate(totalCost: totalCost, periodStart: monthStart, periodEnd: now)
    }

    // MARK: - Static helpers (testable)

    static func costForTokens(model: String, input: Int, output: Int, cacheWrite: Int, cacheRead: Int) -> Double {
        let pricing = pricingForModel(model)
        let inputCost = Double(input) / 1_000_000 * pricing.inputPerMTok
        let outputCost = Double(output) / 1_000_000 * pricing.outputPerMTok
        let cacheWriteCost = Double(cacheWrite) / 1_000_000 * pricing.cacheWritePerMTok
        let cacheReadCost = Double(cacheRead) / 1_000_000 * pricing.cacheReadPerMTok
        return inputCost + outputCost + cacheWriteCost + cacheReadCost
    }

    static func parseLine(_ line: String, monthStart: Date, monthEnd: Date) -> ParsedUsage? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Must be an assistant message
        guard let type = json["type"] as? String, type == "assistant" else {
            return nil
        }

        // Check timestamp is within month
        guard let timestampStr = json["timestamp"] as? String,
              let timestamp = parseTimestamp(timestampStr),
              timestamp >= monthStart && timestamp <= monthEnd else {
            return nil
        }

        // Extract usage from message
        guard let message = json["message"] as? [String: Any],
              let model = message["model"] as? String,
              let usage = message["usage"] as? [String: Any] else {
            return nil
        }

        return ParsedUsage(
            model: model,
            input: usage["input_tokens"] as? Int ?? 0,
            output: usage["output_tokens"] as? Int ?? 0,
            cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0
        )
    }

    // MARK: - Private

    private static func parseFile(at url: URL, monthStart: Date, monthEnd: Date) -> Double {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return 0 }

        var cost: Double = 0
        content.enumerateLines { line, _ in
            guard let usage = parseLine(line, monthStart: monthStart, monthEnd: monthEnd) else { return }
            cost += costForTokens(
                model: usage.model,
                input: usage.input,
                output: usage.output,
                cacheWrite: usage.cacheWrite,
                cacheRead: usage.cacheRead
            )
        }
        return cost
    }

    private static func pricingForModel(_ model: String) -> ModelPricing {
        let lowered = model.lowercased()
        for pricing in pricingTable {
            for pattern in pricing.patterns {
                if lowered.contains(pattern) {
                    return pricing
                }
            }
        }
        return fallbackPricing
    }

    private static func parseTimestamp(_ str: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: str) { return date }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: str)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClaudeCostEstimator 2>&1 | tail -15`
Expected: All 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageTracker/Providers/ClaudeCostEstimator.swift Tests/UsageTrackerTests/ClaudeCostEstimatorTests.swift
git commit -m "feat: implement ClaudeCostEstimator with JSONL parsing and pricing"
```

---

## Task 4: Integrate detector and estimator into ClaudeProvider

**Files:**
- Modify: `Sources/UsageTracker/Providers/ClaudeProvider.swift:4-10` (add stored properties)
- Modify: `Sources/UsageTracker/Providers/ClaudeProvider.swift:44-167` (fetchUsage method)

- [ ] **Step 1: Add stored properties to ClaudeProvider**

In `ClaudeProvider.swift`, add after line 10 (`private let refreshBufferMs`):

```swift
    private let costEstimator = ClaudeCostEstimator()
```

- [ ] **Step 2: Update fetchUsage to populate new fields**

In the `fetchUsage()` method, right before the final `return Provider(...)` at line 160, add the 2x detection and cost estimation. Note: the early-return error paths (not connected, token expired, HTTP error) intentionally leave `is2xActive` and `costEstimate` as nil defaults — the badge and cost row only show on successful loads:

```swift
        // 2x detection
        let detector = Claude2xDetector.loadFromDisk()
        let is2xActive = detector.check()

        // Cost estimation
        let costEstimate = await costEstimator.estimateCurrentMonth()
```

Then update the final return statement (line 160-166) to include the new fields:

```swift
        return Provider(
            id: "claude",
            name: "Claude",
            icon: "brain",
            items: items,
            status: items.isEmpty ? .error("No usage data") : .loaded,
            is2xActive: is2xActive,
            costEstimate: costEstimate?.totalCost
        )
```

- [ ] **Step 3: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/UsageTracker/Providers/ClaudeProvider.swift
git commit -m "feat: integrate 2x detector and cost estimator into ClaudeProvider"
```

---

## Task 5: Render 2x badge in provider header

**Files:**
- Modify: `Sources/UsageTracker/Views/ProviderRow.swift:67-108` (providerHeader)

- [ ] **Step 1: Add 2x badge to providerHeader**

In `ProviderRow.swift`, inside the `providerHeader` computed property, add the badge after the `Text(provider.name)` line (line 84). Replace lines 83-84:

```swift
                Text(provider.name)
                    .font(.system(size: 13, weight: .medium))
```

with:

```swift
                Text(provider.name)
                    .font(.system(size: 13, weight: .medium))

                if provider.is2xActive == true {
                    Text("\u{26A1}2x")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                        )
                }
```

- [ ] **Step 2: Build and test visually**

Run: `swift build && .build/debug/UsageTracker`

To test: create `~/.usagetracker/claude_2x.json` with a promo window covering now:

```bash
cat > ~/.usagetracker/claude_2x.json << 'EOF'
{
  "promoStart": "2026-03-13T00:00:00-05:00",
  "promoEnd": "2026-03-29T03:59:59-04:00",
  "peakHoursET": { "start": 8, "end": 14 }
}
EOF
```

Expected: The Claude provider header shows `Claude ⚡2x 6%` with a blue pill badge (if current time is outside 8-14 ET, i.e. after 14:00 EDT / after 20:00 CEST).

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageTracker/Views/ProviderRow.swift
git commit -m "feat: render 2x capacity badge in Claude provider header"
```

---

## Task 6: Render cost estimate row in provider card

**Files:**
- Modify: `Sources/UsageTracker/Views/ProviderRow.swift:27-54` (expanded content area)

- [ ] **Step 1: Add cost row after usage items**

In `ProviderRow.swift`, inside the `else if provider.isExpanded && !provider.items.isEmpty` block, add the cost row **inside** the `VStack` (lines 33–45) that contains the `ForEach`, right before the VStack's closing `}` on line 45. This keeps the cost row inside the inset styled box:

```swift
                    // ... existing ForEach block above ...

                    if let cost = provider.costEstimate {
                        Divider()
                            .padding(.vertical, 4)

                        HStack(spacing: 8) {
                            Text("API cost est.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(Self.formatCost(cost))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)

                            Text("this month")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .frame(width: 60, alignment: .trailing)
                        }
                        .padding(.leading, 24)
                    }
                }  // end of VStack
```

- [ ] **Step 2: Add the formatCost helper**

Add a static method to `ProviderRow`, after the `providerHeader` computed property (before the struct's closing `}` at line 109):

```swift
    private static func formatCost(_ cost: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: cost)) ?? String(format: "$%.2f", cost)
    }
```

- [ ] **Step 3: Build and test visually**

Run: `swift build && .build/debug/UsageTracker`
Expected: The Claude provider card shows a separator line and "API cost est. $XX.XX this month" below the usage bars, computed from your local `~/.claude/projects/` JSONL files.

- [ ] **Step 4: Commit**

```bash
git add Sources/UsageTracker/Views/ProviderRow.swift
git commit -m "feat: render API cost estimate row in Claude provider card"
```

---

## Task 7: Final build verification and cleanup

**Files:** All modified files

- [ ] **Step 1: Run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass (existing + new).

- [ ] **Step 2: Full build and smoke test**

Run: `swift build && .build/debug/UsageTracker`
Expected: App launches, Claude provider shows usage rows + 2x badge (if applicable) + cost estimate row.

- [ ] **Step 3: Verify edge case — no config file**

```bash
mv ~/.usagetracker/claude_2x.json ~/.usagetracker/claude_2x.json.bak
```

Run app, verify no 2x badge shows. Restore:

```bash
mv ~/.usagetracker/claude_2x.json.bak ~/.usagetracker/claude_2x.json
```

- [ ] **Step 4: Commit any final adjustments**

If any tweaks were needed, commit them.
