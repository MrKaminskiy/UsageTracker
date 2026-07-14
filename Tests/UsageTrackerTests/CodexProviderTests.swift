import Testing
@testable import UsageTracker

@Suite("CodexProvider presentation helpers")
struct CodexProviderTests {
    @Test("Labels known usage windows")
    func windowLabels() {
        let fiveHours = CodexProvider.UsageResponse.Window(usedPercent: 1, limitWindowSeconds: 18_000, resetAfterSeconds: nil, resetAt: nil)
        let week = CodexProvider.UsageResponse.Window(usedPercent: 1, limitWindowSeconds: 604_800, resetAfterSeconds: nil, resetAt: nil)
        #expect(CodexProvider.windowLabel(fiveHours, fallback: "Session") == "5h")
        #expect(CodexProvider.windowLabel(week, fallback: "Weekly") == "Weekly")
    }

    @Test("Formats plan names")
    func planLabels() {
        #expect(CodexProvider.planLabel(from: "chatgpt_plus") == "Chatgpt Plus")
        #expect(CodexProvider.planLabel(from: nil) == nil)
    }
}
