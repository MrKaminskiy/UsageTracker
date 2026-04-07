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

    @Test("estimateCurrentMonth with custom directory returns zero cost for empty dir")
    func emptyProjectsDir() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let estimator = ClaudeCostEstimator()
        let result = await estimator.estimateCurrentMonth(projectsDir: tmpDir)
        // An empty directory has no JSONL files — should return a zero-cost estimate (not nil,
        // because the directory exists)
        #expect(result != nil)
        #expect(result?.totalCost == 0.0)
    }
}
