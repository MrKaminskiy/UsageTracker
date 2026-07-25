import Testing
import Foundation
@testable import UsageTracker

@Suite("ClaudeProvider credential parsing")
struct ClaudeProviderCredentialsTests {

    // The format Claude Code CLI writes to ~/.claude/.credentials.json,
    // including fields we don't model (scopes, rateLimitTier).
    @Test("Decodes credentials.json format with extra fields")
    func decodesCredentialsFile() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "sk-test-access",
            "refreshToken": "sk-test-refresh",
            "expiresAt": 1778187507488,
            "scopes": ["user:profile", "user:inference"],
            "subscriptionType": "max",
            "rateLimitTier": "default_claude_max_5x"
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let creds = try JSONDecoder().decode(ClaudeProvider.Credentials.self, from: data)

        #expect(creds.claudeAiOauth?.accessToken == "sk-test-access")
        #expect(creds.claudeAiOauth?.refreshToken == "sk-test-refresh")
        #expect(creds.claudeAiOauth?.expiresAt == 1778187507488)
        #expect(creds.claudeAiOauth?.subscriptionType == "max")
    }

    @Test("Decodes minimal credentials with only required fields")
    func decodesMinimalCredentials() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "sk-test"
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let creds = try JSONDecoder().decode(ClaudeProvider.Credentials.self, from: data)

        #expect(creds.claudeAiOauth?.accessToken == "sk-test")
        #expect(creds.claudeAiOauth?.refreshToken == nil)
        #expect(creds.claudeAiOauth?.expiresAt == nil)
    }
}

@Suite("ClaudeProvider token expiry (drives keychain cache reuse)")
struct ClaudeProviderNeedsRefreshTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func oauth(expiresInMs offset: Double?) -> ClaudeProvider.Credentials.OAuthData {
        .init(
            accessToken: "sk-test",
            refreshToken: "sk-refresh",
            expiresAt: offset.map { now.timeIntervalSince1970 * 1000 + $0 },
            subscriptionType: nil
        )
    }

    @Test("Token expiring well beyond the buffer does not need refresh")
    func farFutureExpiry() {
        #expect(!ClaudeProvider.needsRefresh(oauth(expiresInMs: 60 * 60 * 1000), now: now))
    }

    @Test("Token inside the 5-minute buffer needs refresh")
    func withinBuffer() {
        #expect(ClaudeProvider.needsRefresh(oauth(expiresInMs: 4 * 60 * 1000), now: now))
    }

    @Test("Expired token needs refresh")
    func expired() {
        #expect(ClaudeProvider.needsRefresh(oauth(expiresInMs: -1000), now: now))
    }

    @Test("Missing expiry or missing oauth needs refresh")
    func missingData() {
        #expect(ClaudeProvider.needsRefresh(oauth(expiresInMs: nil), now: now))
        #expect(ClaudeProvider.needsRefresh(nil, now: now))
    }

    // isExpired gates spending the refresh token, which rotates it and kills the
    // copy Claude Code holds. It must be strictly tighter than needsRefresh.
    @Test("Token inside the cache buffer but not yet expired is not spent on a refresh")
    func withinBufferIsNotExpired() {
        #expect(!ClaudeProvider.isExpired(oauth(expiresInMs: 4 * 60 * 1000), now: now))
    }

    @Test("Expired token, and token inside the 30s grace, count as expired")
    func expiredIsExpired() {
        #expect(ClaudeProvider.isExpired(oauth(expiresInMs: -1000), now: now))
        #expect(ClaudeProvider.isExpired(oauth(expiresInMs: 10 * 1000), now: now))
    }

    @Test("Unknown expiry is not refreshed preemptively; the 401 path handles it")
    func unknownExpiryIsNotExpired() {
        #expect(!ClaudeProvider.isExpired(oauth(expiresInMs: nil), now: now))
        #expect(!ClaudeProvider.isExpired(nil, now: now))
    }
}

// Regression: re-encoding our own Credentials struct into the shared store used to
// drop every key we don't model, breaking Claude Code's session and forcing a
// daily `/login`.
@Suite("ClaudeProvider write-back preserves Claude Code's fields")
struct ClaudeProviderMergeTests {

    private let raw: [String: Any] = [
        "claudeAiOauth": [
            "accessToken": "old-access",
            "refreshToken": "old-refresh",
            "expiresAt": 1_778_187_507_488,
            "scopes": ["user:profile", "user:inference"],
            "subscriptionType": "max",
            "rateLimitTier": "default_claude_max_5x"
        ] as [String: Any],
        "someFutureTopLevelKey": "keep me"
    ]

    private func merged() -> [String: Any] {
        ClaudeProvider.merging(
            .init(
                accessToken: "new-access",
                refreshToken: "new-refresh",
                expiresAt: 1_778_200_000_000,
                subscriptionType: "max"
            ),
            into: raw
        )
    }

    @Test("Token fields are replaced")
    func replacesTokens() throws {
        let oauth = try #require(merged()["claudeAiOauth"] as? [String: Any])
        #expect(oauth["accessToken"] as? String == "new-access")
        #expect(oauth["refreshToken"] as? String == "new-refresh")
    }

    @Test("Unmodelled fields survive the round-trip")
    func keepsUnknownFields() throws {
        let result = merged()
        let oauth = try #require(result["claudeAiOauth"] as? [String: Any])
        #expect(oauth["scopes"] as? [String] == ["user:profile", "user:inference"])
        #expect(oauth["rateLimitTier"] as? String == "default_claude_max_5x")
        #expect(result["someFutureTopLevelKey"] as? String == "keep me")
    }

    @Test("expiresAt stays an integer, as Claude Code writes it")
    func expiryStaysInteger() throws {
        let oauth = try #require(merged()["claudeAiOauth"] as? [String: Any])
        #expect(oauth["expiresAt"] as? Int == 1_778_200_000_000)

        let data = try JSONSerialization.data(withJSONObject: merged())
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("1778200000000"))
        #expect(!text.contains("1778200000000.0"))
    }

    // The store is re-read right before writing: Claude Code may have logged in
    // while our refresh request was in flight, and its tokens would then be newer
    // than ours. Overwriting them would cost the user yet another /login.
    @Test("Store still holding the token we spent is safe to overwrite")
    func storeUnchanged() {
        let stored = ClaudeProvider.Credentials.OAuthData(
            accessToken: "old-access", refreshToken: "old-refresh",
            expiresAt: nil, subscriptionType: nil
        )
        #expect(!ClaudeProvider.storeMovedOn(stored, spentRefreshToken: "old-refresh"))
    }

    @Test("Store holding a different token means Claude Code moved on")
    func storeChangedUnderUs() {
        let relogged = ClaudeProvider.Credentials.OAuthData(
            accessToken: "cli-access", refreshToken: "cli-refresh",
            expiresAt: nil, subscriptionType: nil
        )
        #expect(ClaudeProvider.storeMovedOn(relogged, spentRefreshToken: "old-refresh"))
        #expect(ClaudeProvider.storeMovedOn(nil, spentRefreshToken: "old-refresh"))
        #expect(!ClaudeProvider.storeMovedOn(nil, spentRefreshToken: nil))
    }

    @Test("Merged object is JSON-serializable and re-decodes")
    func roundTrips() throws {
        let data = try JSONSerialization.data(withJSONObject: merged())
        let creds = try JSONDecoder().decode(ClaudeProvider.Credentials.self, from: data)
        #expect(creds.claudeAiOauth?.accessToken == "new-access")
        #expect(creds.claudeAiOauth?.expiresAt == 1_778_200_000_000)
    }
}

@Suite("ClaudeProvider extra credits and plan label")
struct ClaudeProviderExtrasTests {

    // API reports credits in minor units (cents): verified live 2026-07-08 —
    // raw used=1610 limit=5000 corresponds to €16.10 of €50.00 on claude.ai.
    // No currency is exposed, so the amounts render without a symbol; they go
    // in the trailing detail slot (resetLabel) so the row keeps the normal
    // bar + percentage layout.
    @Test("Extra credits item converts minor units; amounts in trailing detail slot")
    func extraCreditsMapping() {
        let extra = ClaudeProvider.UsageResponse.ExtraUsage(is_enabled: true, used_credits: 1610, monthly_limit: 5000)
        let item = ClaudeProvider.extraCreditsItem(from: extra)
        #expect(item != nil)
        #expect(item?.label == "Extra credits")
        #expect(item?.kind == .extraUsage)
        #expect(item?.resetLabel == "16.10/50")
        #expect(abs((item?.percentage ?? 0) - 32.2) < 0.01)
    }

    @Test("Extra credits hidden when disabled, missing, or zero limit")
    func extraCreditsHidden() {
        #expect(ClaudeProvider.extraCreditsItem(from: nil) == nil)
        #expect(ClaudeProvider.extraCreditsItem(from: .init(is_enabled: false, used_credits: 5, monthly_limit: 50)) == nil)
        #expect(ClaudeProvider.extraCreditsItem(from: .init(is_enabled: true, used_credits: 5, monthly_limit: 0)) == nil)
        #expect(ClaudeProvider.extraCreditsItem(from: .init(is_enabled: true, used_credits: 5, monthly_limit: nil)) == nil)
    }

    @Test("Whole credit amounts drop decimals")
    func extraCreditsWhole() {
        let extra = ClaudeProvider.UsageResponse.ExtraUsage(is_enabled: true, used_credits: 1200, monthly_limit: 5000)
        #expect(ClaudeProvider.extraCreditsItem(from: extra)?.resetLabel == "12/50")
    }

    @Test("Plan label mapping")
    func planLabels() {
        #expect(ClaudeProvider.planLabel(from: "max") == "Max")
        #expect(ClaudeProvider.planLabel(from: "pro") == "Pro")
        #expect(ClaudeProvider.planLabel(from: "enterprise") == "Enterprise")
        #expect(ClaudeProvider.planLabel(from: "some_new_tier") == "Some_new_tier".capitalized)
        #expect(ClaudeProvider.planLabel(from: nil) == nil)
        #expect(ClaudeProvider.planLabel(from: "") == nil)
    }
}
