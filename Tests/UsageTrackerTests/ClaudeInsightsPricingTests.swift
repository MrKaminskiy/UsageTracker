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
