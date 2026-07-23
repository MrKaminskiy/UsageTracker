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
