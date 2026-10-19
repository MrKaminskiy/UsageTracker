import Foundation
import Testing
@testable import UsageTracker

@Suite("AppState with several Claude accounts")
@MainActor
struct ClaudeAccountsStateTests {

    private let now = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0,
        of: Date(timeIntervalSince1970: 1_800_000_000)
    )!

    private func account(_ id: String, uuid: String? = nil) -> ClaudeAccount {
        let dir = URL(fileURLWithPath: "/Users/test/\(id)")
        return ClaudeAccount(
            providerID: id, configDir: dir, keychainService: "s",
            credentialsFile: dir.appendingPathComponent(".credentials.json"),
            projectsDir: dir.appendingPathComponent("projects"),
            email: nil, accountUuid: uuid, organizationUuid: nil, hasLogin: true
        )
    }

    private func provider(_ id: String, items: [UsageItem] = [UsageItem(label: "Weekly", current: 40, limit: 100, resetLabel: nil)],
                          status: ProviderStatus = .loaded) -> Provider {
        Provider(id: id, name: "Claude", icon: "brain", items: items, status: status)
    }

    // MARK: Config

    @Test("A 1.5.1 config keeps its pin, order and toggles; a new account lands right after Claude")
    func upgradesConfig151() throws {
        let json = #"{"refreshIntervalMinutes":5,"launchAtLogin":false,"hideNotConnected":true,"hasCompletedOnboarding":true,"showCostEstimate":false,"pinnedItem":{"providerId":"claude","itemLabel":"Weekly"},"enabledProviders":{"claude":true,"cursor":true,"codex":true,"elevenlabs":true,"stability":false,"runway":false,"openai":true,"openrouter":true},"providerOrder":["claude","cursor","codex","elevenlabs","stability","runway","openai","openrouter"]}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))

        let out = AppState.addingClaudeAccounts(["claude", "claude-2601a85c"], to: config)

        #expect(Array(out.providerOrder.prefix(3)) == ["claude", "claude-2601a85c", "cursor"])
        #expect(out.enabledProviders["claude-2601a85c"] == true)
        #expect(out.enabledProviders["stability"] == false)
        #expect(out.pinnedItem == PinnedItem(providerId: "claude", itemLabel: "Weekly"))
        #expect(AppState.addingClaudeAccounts(["claude", "claude-2601a85c"], to: out).providerOrder == out.providerOrder)
    }

    @Test("A new account follows Claude wherever the user moved it, without touching Claude's toggle")
    func insertsAfterMovedClaude() {
        var config = AppConfig()
        config.providerOrder = ["cursor", "codex", "claude", "openai"]
        config.enabledProviders["claude"] = false

        let out = AppState.addingClaudeAccounts(["claude", "claude-2601a85c"], to: config)

        #expect(out.providerOrder == ["cursor", "codex", "claude", "claude-2601a85c", "openai"])
        #expect(out.enabledProviders["claude"] == false)
        #expect(out.enabledProviders["claude-2601a85c"] == true)
    }

    // MARK: Names and staleness

    @Test("One account is plain Claude; with two, each card is named, a user's name winning")
    func displayNames() {
        #expect(AppState.claudeDisplayName(label: "a@x", override: nil, providerID: "claude", claudeCardCount: 1) == "Claude")
        #expect(AppState.claudeDisplayName(label: "a@x", override: nil, providerID: "claude", claudeCardCount: 2) == "Claude · a@x")
        #expect(AppState.claudeDisplayName(label: "a@x", override: "Work", providerID: "claude", claudeCardCount: 2) == "Claude · Work")
        #expect(AppState.claudeDisplayName(label: "a@x", override: "  ", providerID: "claude", claudeCardCount: 2) == "Claude · a@x")
        #expect(AppState.claudeDisplayName(label: nil, override: nil, providerID: "claude-2601a85c", claudeCardCount: 2) == "Claude · claude-2601a85c")
    }

    @Test("A reading is marked stale once it's older than two refreshes, at least 15 minutes")
    func staleLabels() {
        func label(_ age: TimeInterval, interval: Int = 5) -> String? {
            AppState.staleLabel(fetchedAt: now.addingTimeInterval(-age), refreshIntervalMinutes: interval, now: now)
        }
        #expect(label(10 * 60) == nil)
        #expect(label(20 * 60) == "as of 20m ago")
        #expect(label(9 * 3600) == "as of 9h ago")
        #expect(label(3 * 86400) == "as of 3d ago")
        #expect(label(40 * 60, interval: 30) == nil)
        #expect(AppState.staleLabel(fetchedAt: nil, refreshIntervalMinutes: 5, now: now) == nil)
    }

    // MARK: Fetch results

    @Test("An expired login keeps the last reading when there is one, else shows why")
    func resolveResults() {
        let fresh = provider("claude")
        let fallback = provider("claude", items: [], status: .error("Token expired. Run `claude` to log in again."))
        let expired = ClaudeProvider.LoginExpired(fallback: fallback)

        #expect(AppState.resolveClaudeResult(.success(fresh), previous: nil) == fresh)
        #expect(AppState.resolveClaudeResult(.failure(expired), previous: provider("claude")) == nil)
        #expect(AppState.resolveClaudeResult(.failure(expired), previous: provider("claude", items: [])) == fallback)
        #expect(AppState.resolveClaudeResult(.failure(expired), previous: nil) == fallback)
        #expect(AppState.resolveClaudeResult(.failure(URLError(.timedOut)), previous: nil) == nil)
    }

    // MARK: Shared insights

    @Test("Shared cost and insights sit on the first account card that has rows")
    func insightsGoToFirstLiveCard() throws {
        let insights = ClaudeInsights(monthlyCost: 12.5)
        let out = AppState.attachingClaudeInsights(
            insights, to: [provider("claude"), provider("claude-2601a85c")],
            accounts: [account("claude"), account("claude-2601a85c")]
        )
        #expect(out[0].insights == insights)
        #expect(out[0].costEstimate == 12.5)
        #expect(out[1].insights == nil)
        #expect(out[1].costEstimate == nil)
    }

    @Test("A card with no rows doesn't take the shared stats; no stats clears them everywhere")
    func insightsSkipDeadCards() throws {
        let insights = ClaudeInsights(monthlyCost: 12.5)
        let signedOut = provider("claude", items: [], status: .notConnected(url: URL(string: "https://claude.ai")!))
        var codex = Provider(id: "codex", name: "Codex", icon: "terminal", items: [], status: .loaded)
        codex.costEstimate = 3
        let accounts = [account("claude"), account("claude-2601a85c")]

        let out = AppState.attachingClaudeInsights(insights, to: [signedOut, provider("claude-2601a85c"), codex], accounts: accounts)
        #expect(out[0].insights == nil)
        #expect(out[1].insights == insights)
        #expect(out[2].costEstimate == 3)

        let cleared = AppState.attachingClaudeInsights(nil, to: out, accounts: accounts)
        for card in cleared where isClaudeProviderID(card.id) {
            #expect(card.insights == nil)
            #expect(card.costEstimate == nil)
        }
    }
}
