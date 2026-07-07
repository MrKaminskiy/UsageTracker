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
