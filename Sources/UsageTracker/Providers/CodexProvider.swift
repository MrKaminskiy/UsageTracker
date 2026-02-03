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

    private func needsRefresh(_ expiresAt: Double?) -> Bool {
        guard let expiresAt = expiresAt else { return true }
        let now = Date().timeIntervalSince1970
        let bufferSeconds: Double = 5 * 60 // 5 minutes
        return now + bufferSeconds >= expiresAt
    }

    private func refreshTokenRequest(_ refreshToken: String) async throws -> (accessToken: String, expiresAt: Double)? {
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            return nil
        }

        struct RefreshResponse: Codable {
            var access_token: String?
            var expires_in: Double?
        }

        let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)

        guard let token = refreshResponse.access_token else { return nil }

        let expiresAt = Date().timeIntervalSince1970 + (refreshResponse.expires_in ?? 3600)
        return (token, expiresAt)
    }

    private func saveAuth(_ auth: AuthFile) {
        guard let data = try? JSONEncoder().encode(auth) else { return }
        FileManager.default.createFile(atPath: authPath, contents: data)
    }
}
