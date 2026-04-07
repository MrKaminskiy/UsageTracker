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

    func estimateCurrentMonth(projectsDir: URL? = nil) async -> CostEstimate? {
        let resolvedDir = projectsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard FileManager.default.fileExists(atPath: resolvedDir.path) else {
            return nil
        }

        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return nil
        }

        // Collect all .jsonl files synchronously before entering async context
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
                      modDate >= monthStart else { continue }
                result.append((fileURL, modDate))
            }
            return result
        }()

        var totalCost: Double = 0

        for (fileURL, modDate) in jsonlFiles {
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
