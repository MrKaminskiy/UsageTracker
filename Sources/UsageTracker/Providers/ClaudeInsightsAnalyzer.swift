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

    /// Default/floor for the active-chat recency window: a chat only counts as "active" for the
    /// context alert if its last turn is newer than this, so a stale large session (Claude closed,
    /// chat cleared/switched, or app restarted hours later) doesn't fire a misleading notification.
    /// Callers widen it to at least the refresh interval so a crossing isn't missed between refreshes.
    static let activeRecencyWindow: TimeInterval = 15 * 60

    static func aggregate(recentEvents: [TranscriptEvent], monthlyCost: Double, now: Date, calendar: Calendar = .current,
                          sessionMeta: [String: SessionMeta] = [:],
                          activeRecency: TimeInterval = activeRecencyWindow) -> ClaudeInsights {
        var insights = ClaudeInsights(monthlyCost: monthlyCost)

        let windowStart = now.addingTimeInterval(-24 * 3600)
        var usage24: [UsageEvent] = []
        var patches: [PatchEvent] = []
        for event in recentEvents {
            switch event {
            // +1s: transcript timestamps are ms-rounded and can land slightly ahead of our clock
            case .usage(let u) where u.timestamp >= windowStart && u.timestamp <= now.addingTimeInterval(1):
                usage24.append(u)
            case .patch(let p) where p.timestamp <= now:
                patches.append(p)
            default:
                break
            }
        }

        // Active chat = the most recent main-thread (non-sidechain) turn, but only if that turn
        // is recent (see activeRecencyWindow) — a large session last touched hours ago is history,
        // not the chat the user is in now. Its context is the live size being carried; drives the
        // "context too large" alert. Sidechain turns run at their own smaller context and don't
        // reflect the main chat, so they're excluded.
        let activeCutoff = now.addingTimeInterval(-activeRecency)
        if let active = usage24.filter({ !$0.isSidechain }).max(by: { $0.timestamp < $1.timestamp }),
           active.timestamp >= activeCutoff {
            insights.activeContextTokens = active.contextTokens
            insights.activeSessionId = active.sessionId
            if let sid = active.sessionId {
                insights.activeSessionTitle = sessionMeta[sid]?.title ?? sessionMeta[sid]?.project
            }
        }

        let totalTokens = usage24.reduce(0) { $0 + $1.totalTokens }
        if totalTokens > 0 {
            let total = Double(totalTokens)

            let overTokens = usage24.filter { $0.contextTokens > 150_000 }.reduce(0) { $0 + $1.totalTokens }
            insights.contextShareOver150k = Double(overTokens) / total * 100

            // Decompose that >150k share by chat: which sessions actually grew large.
            // heavy = tokens a session spent while its context was >150k; peak = its largest context.
            var sessionHeavy: [String: Int] = [:]
            var sessionPeak: [String: Int] = [:]
            for u in usage24 {
                guard let sid = u.sessionId else { continue }
                sessionPeak[sid] = max(sessionPeak[sid] ?? 0, u.contextTokens)
                if u.contextTokens > 150_000 { sessionHeavy[sid, default: 0] += u.totalTokens }
            }
            insights.heaviestSessions = sessionHeavy
                .filter { $0.value > 0 }
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(5)
                .map { sid, heavy in
                    let meta = sessionMeta[sid]
                    let title = meta?.title ?? meta?.project ?? "Untitled chat"
                    return HeavySession(title: title,
                                        project: meta?.project,
                                        peakContextTokens: sessionPeak[sid] ?? 0,
                                        share: Double(heavy) / total * 100)
                }

            let contextSum = usage24.reduce(0) { $0 + $1.contextTokens }
            insights.avgContextTokens = contextSum / usage24.count

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
                today.cacheReadTokens += u.cacheRead
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
        let size: Int
        let monthKey: String            // "yyyy-MM" the summary was computed for
        let monthCost: Double           // cost of usage events within that month
        let recentEvents: [TranscriptEvent]  // events within 25h of parse time
        let sessionId: String?          // this transcript's session (the file name)
        let title: String?              // aiTitle from the transcript, if any
        let project: String?            // short project name (cwd leaf)
    }

    private var fileCache: [String: FileSummary] = [:]

    func analyze(projectsDir: URL? = nil, now: Date = Date(),
                 activeRecency: TimeInterval = activeRecencyWindow) async -> ClaudeInsights? {
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

        let jsonlFiles: [(url: URL, modDate: Date, size: Int)] = {
            guard let enumerator = FileManager.default.enumerator(
                at: resolvedDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            var result: [(URL, Date, Int)] = []
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl" else { continue }
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let modDate = resourceValues.contentModificationDate,
                      modDate >= walkCutoff else { continue }
                let size = resourceValues.fileSize ?? 0
                result.append((fileURL, modDate, size))
            }
            return result
        }()

        var totalCost: Double = 0
        var recentEvents: [TranscriptEvent] = []
        var sessionMeta: [String: SessionMeta] = [:]

        for (fileURL, modDate, size) in jsonlFiles {
            let path = fileURL.path
            let summary: FileSummary
            if let cached = fileCache[path], cached.modDate == modDate, cached.size == size, cached.monthKey == monthKey {
                summary = cached
            } else {
                summary = Self.parseFile(at: fileURL, modDate: modDate, size: size, monthKey: monthKey,
                                         monthStart: monthStart, now: now, recentCutoff: recentCutoff)
                fileCache[path] = summary
            }
            totalCost += summary.monthCost
            // A file whose mtime is older than the recent cutoff cannot contain in-window
            // events (event timestamps <= file mtime) — skip re-appending dead events for
            // every month-old file on each refresh.
            if modDate >= recentCutoff {
                recentEvents.append(contentsOf: summary.recentEvents)
                if let sid = summary.sessionId {
                    sessionMeta[sid] = SessionMeta(title: summary.title, project: summary.project)
                }
            }
        }

        return Self.aggregate(recentEvents: recentEvents, monthlyCost: totalCost, now: now,
                              calendar: calendar, sessionMeta: sessionMeta, activeRecency: activeRecency)
    }

    private static func parseFile(at url: URL, modDate: Date, size: Int, monthKey: String,
                                  monthStart: Date, now: Date, recentCutoff: Date) -> FileSummary {
        // The file name is the session id; keep it even if the file can't be read.
        let sessionId = url.deletingPathExtension().lastPathComponent
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return FileSummary(modDate: modDate, size: size, monthKey: monthKey, monthCost: 0,
                               recentEvents: [], sessionId: sessionId, title: nil, project: nil)
        }

        var monthCost: Double = 0
        var recentEvents: [TranscriptEvent] = []
        var title: String? = nil     // human-readable chat title (aiTitle)
        var project: String? = nil   // short project name from cwd
        content.enumerateLines { line, _ in
            // Cheap string pre-check before JSON-parsing for the two metadata fields.
            if title == nil, line.contains("\"aiTitle\""), let t = stringField("aiTitle", in: line) { title = t }
            if project == nil, line.contains("\"cwd\""), let c = stringField("cwd", in: line) {
                project = URL(fileURLWithPath: c).lastPathComponent
            }
            guard let event = parseEvent(line) else { return }
            switch event {
            case .usage(let u):
                // +1s: transcript timestamps are ms-rounded and can land slightly ahead of our clock
                if u.timestamp >= monthStart && u.timestamp <= now.addingTimeInterval(1) {
                    monthCost += costForTokens(model: u.model, input: u.input, output: u.output,
                                               cacheWrite: u.cacheWrite, cacheRead: u.cacheRead)
                }
                if u.timestamp >= recentCutoff { recentEvents.append(event) }
            case .patch(let p):
                if p.timestamp >= recentCutoff { recentEvents.append(event) }
            }
        }
        return FileSummary(modDate: modDate, size: size, monthKey: monthKey, monthCost: monthCost,
                           recentEvents: recentEvents, sessionId: sessionId, title: title, project: project)
    }

    /// Parse one JSONL line and return a top-level string field, or nil.
    private static func stringField(_ key: String, in line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj[key] as? String
    }

    private static func monthKey(for monthStart: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.timeZone = .current
        return f.string(from: monthStart)
    }
}
