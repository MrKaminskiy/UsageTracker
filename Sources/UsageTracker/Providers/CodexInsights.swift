import Foundation

struct CodexTodayStats: Equatable, Sendable {
    let updatedThreadCount: Int
    let createdThreadCount: Int
    /// Codex's locally stored cumulative counter for the threads updated today.
    let activeThreadTokens: Int
}

struct CodexThreadSummary: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let project: String?
    let model: String?
    let tokensUsed: Int
    let updatedAt: Date
}

struct CodexModelSummary: Equatable, Sendable, Identifiable {
    let model: String
    let threadCount: Int

    var id: String { model }
}

struct CodexInsights: Equatable, Sendable {
    var today: CodexTodayStats? = nil
    var recentThreads: [CodexThreadSummary] = []
    var models: [CodexModelSummary] = []
    var creditBalance: String? = nil
}
