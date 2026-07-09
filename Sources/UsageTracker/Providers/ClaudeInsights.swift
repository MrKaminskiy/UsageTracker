import Foundation

struct UsageShare: Equatable, Sendable {
    let name: String
    let share: Double   // 0–100, % of last-24h tokens
}

struct TodayStats: Equatable, Sendable {
    var cost: Double = 0
    var sessionCount: Int = 0
    var totalTokens: Int = 0
    var cacheReadTokens: Int = 0      // re-sent context; cheap, dominates totalTokens
    var linesAdded: Int = 0
    var linesRemoved: Int = 0

    /// input + output + cacheWrite — the tokens that aren't just re-read context
    var newTokens: Int { max(0, totalTokens - cacheReadTokens) }
}

struct ClaudeInsights: Equatable, Sendable {
    var monthlyCost: Double? = nil
    var contextShareOver150k: Double? = nil   // nil when no last-24h data
    var subagentShare: Double? = nil          // nil when no last-24h data
    var skills: [UsageShare] = []
    var subagents: [UsageShare] = []
    var today: TodayStats? = nil              // nil when nothing happened today

    static let contextWarningThreshold: Double = 40
    static let subagentWarningThreshold: Double = 30

    var hasWarnings: Bool {
        (contextShareOver150k ?? 0) >= Self.contextWarningThreshold
            || (subagentShare ?? 0) >= Self.subagentWarningThreshold
    }
}

struct UsageEvent: Equatable, Sendable {
    let timestamp: Date
    let model: String
    let input: Int
    let output: Int
    let cacheWrite: Int
    let cacheRead: Int
    let isSidechain: Bool
    let sessionId: String?
    let skill: String?
    let agent: String?

    var totalTokens: Int { input + output + cacheWrite + cacheRead }
    var contextTokens: Int { input + cacheWrite + cacheRead }
}

struct PatchEvent: Equatable, Sendable {
    let timestamp: Date
    let linesAdded: Int
    let linesRemoved: Int
}

enum TranscriptEvent: Equatable, Sendable {
    case usage(UsageEvent)
    case patch(PatchEvent)
}
