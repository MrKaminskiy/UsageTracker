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

    // MARK: - File walk + incremental cache

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
}
