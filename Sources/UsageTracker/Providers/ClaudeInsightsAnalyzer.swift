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
