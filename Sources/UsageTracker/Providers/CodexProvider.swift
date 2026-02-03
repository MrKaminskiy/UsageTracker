import Foundation

actor CodexProvider {
    private let authPath = NSString(string: "~/.codex/auth.json").expandingTildeInPath
    private let usageURL = URL(string: "https://api.openai.com/v1/usage")!
    private let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    private let settingsURL = URL(string: "https://platform.openai.com/settings/organization/limits")!

    struct AuthFile: Codable {
        var accessToken: String?
        var refreshToken: String?
        var expiresAt: Double?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
        }
    }

    func fetchUsage() async throws -> Provider {
        // Read auth file
        guard let authData = FileManager.default.contents(atPath: authPath),
              let auth = try? JSONDecoder().decode(AuthFile.self, from: authData),
              let _ = auth.accessToken else {
            return Provider(
                id: "codex",
                name: "Codex",
                icon: "terminal.fill",
                items: [],
                status: .notConnected(url: settingsURL)
            )
        }

        // TODO: Implement token refresh and usage fetch
        return Provider(
            id: "codex",
            name: "Codex",
            icon: "terminal.fill",
            items: [],
            status: .error("Not implemented")
        )
    }
}
