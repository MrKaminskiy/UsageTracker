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

    // MARK: - Integration tests (file-level)

    @Test("Aggregates cost across two JSONL files")
    func aggregatesMultipleFiles() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let timestamp = ISO8601DateFormatter().string(from: Date())

        // File 1: 1M opus input tokens → $15
        let line1 = """
        {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try line1.write(to: tmpDir.appendingPathComponent("proj1.jsonl"), atomically: true, encoding: .utf8)

        // File 2: 1M sonnet output tokens → $15
        let line2 = """
        {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"claude-sonnet-4-6","role":"assistant","usage":{"input_tokens":0,"output_tokens":1000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try line2.write(to: tmpDir.appendingPathComponent("proj2.jsonl"), atomically: true, encoding: .utf8)

        let estimator = ClaudeCostEstimator()
        let result = await estimator.estimateCurrentMonth(projectsDir: tmpDir)
        #expect(result != nil)
        // Opus 1M input = $15, Sonnet 1M output = $15, total = $30
        #expect(abs((result?.totalCost ?? 0) - 30.0) < 0.01)
    }

    @Test("Skips lines from previous months")
    func skipsOldLines() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Old timestamp (Jan 2025) — should be filtered out by parseLine date check
        let oldLine = """
        {"type":"assistant","timestamp":"2025-01-15T10:00:00.000Z","message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try oldLine.write(to: tmpDir.appendingPathComponent("old.jsonl"), atomically: true, encoding: .utf8)

        let estimator = ClaudeCostEstimator()
        let result = await estimator.estimateCurrentMonth(projectsDir: tmpDir)
        // File mod date is now (within month), so file is included, but line timestamp is Jan 2025 — filtered
        #expect(result != nil)
        #expect(result?.totalCost == 0.0)
    }

    @Test("Handles malformed lines mixed with valid lines")
    func handlesMixedLines() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let content = """
        {bad json here}
        {"type":"human","timestamp":"\(timestamp)","message":{"role":"user","content":"hello"}}
        {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"claude-sonnet-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        // Sonnet 1M input = $3; malformed and human lines are skipped
        try content.write(to: tmpDir.appendingPathComponent("mixed.jsonl"), atomically: true, encoding: .utf8)

        let estimator = ClaudeCostEstimator()
        let result = await estimator.estimateCurrentMonth(projectsDir: tmpDir)
        #expect(result != nil)
        #expect(abs((result?.totalCost ?? 0) - 3.0) < 0.01)
    }

    @Test("Returns nil when projects directory does not exist")
    func nilForMissingDirectory() async {
        let nonexistent = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString)")
        let estimator = ClaudeCostEstimator()
        let result = await estimator.estimateCurrentMonth(projectsDir: nonexistent)
        #expect(result == nil)
    }
}
