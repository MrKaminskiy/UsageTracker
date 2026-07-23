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

/// One chat (session) that spent tokens while its context was above 150k — a
/// per-session decomposition of `contextShareOver150k`, so the user can see
/// *which* chat grew instead of just an aggregate percentage.
struct HeavySession: Equatable, Sendable {
    let title: String            // aiTitle from the transcript, or project-name fallback
    let project: String?         // short project (cwd leaf) for context; nil if unknown
    let peakContextTokens: Int   // largest context this chat reached in the window
    let share: Double            // % of last-24h tokens this chat spent while >150k context
}

/// Title/project for a session, captured while parsing its transcript file.
struct SessionMeta: Equatable, Sendable {
    let title: String?
    let project: String?
}

struct ClaudeInsights: Equatable, Sendable {
    var monthlyCost: Double? = nil
    var contextShareOver150k: Double? = nil   // nil when no last-24h data
    var subagentShare: Double? = nil          // nil when no last-24h data
    var avgContextTokens: Int? = nil          // mean context (input+cache) per turn, last 24h
    var skills: [UsageShare] = []
    var subagents: [UsageShare] = []
    var heaviestSessions: [HeavySession] = [] // chats driving the >150k share, ranked
    var today: TodayStats? = nil              // nil when nothing happened today

    // The currently-active chat (most recent main-thread turn), for the context-size alert.
    var activeContextTokens: Int? = nil       // its latest context (input+cache); nil when no 24h data
    var activeSessionId: String? = nil        // session id of that chat, for alert de-duplication
    var activeSessionTitle: String? = nil     // aiTitle/project of that chat, for the alert body

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
