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
