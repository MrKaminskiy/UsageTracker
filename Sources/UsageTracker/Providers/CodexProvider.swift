import Foundation

actor CodexProvider {
    private let authPath = NSString(string: "~/.codex/auth.json").expandingTildeInPath
    private let usageURL = URL(string: "https://api.openai.com/v1/usage")!
    private let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    private let settingsURL = URL(string: "https://platform.openai.com/settings/organization/limits")!

    struct AuthFile: Codable {
        var tokens: Tokens?
        var lastRefresh: String?

        enum CodingKeys: String, CodingKey {
            case tokens
            case lastRefresh = "last_refresh"
        }

        struct Tokens: Codable {
            var accessToken: String?
            var refreshToken: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
            }
        }
    }

    struct UsageResponse: Codable {
        var data: UsageData?

        struct UsageData: Codable {
            var hardLimitUsd: Double?
            var softLimitUsd: Double?
            var totalUsageUsd: Double?

            enum CodingKeys: String, CodingKey {
                case hardLimitUsd = "hard_limit_usd"
                case softLimitUsd = "soft_limit_usd"
                case totalUsageUsd = "total_usage_usd"
            }
        }
    }

    func fetchUsage() async throws -> Provider {
        // Check if auth file exists (means user has logged in to Codex)
        guard let authData = FileManager.default.contents(atPath: authPath),
              let auth = try? JSONDecoder().decode(AuthFile.self, from: authData),
              auth.tokens?.accessToken != nil else {
            return Provider(
                id: "codex",
                name: "Codex",
                icon: "terminal.fill",
                items: [],
                status: .notConnected(url: settingsURL)
            )
        }

        // Codex uses ChatGPT Plus subscription - usage is shared with ChatGPT
        // The ChatGPT API is protected by Cloudflare, so we show "Connected" status
        // with a link to view usage on the web
        return Provider(
            id: "codex",
            name: "Codex",
            icon: "terminal.fill",
            items: [],
            status: .notConnected(url: URL(string: "https://chatgpt.com/#settings/Profile")!)
        )
    }

    private func parseISO8601(_ string: String?) -> Double? {
        guard let string = string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date.timeIntervalSince1970
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)?.timeIntervalSince1970
    }

    private func needsRefresh(_ lastRefresh: Double?) -> Bool {
        guard let lastRefresh = lastRefresh else { return true }
        let now = Date().timeIntervalSince1970
        let tokenLifetimeSeconds: Double = 55 * 60 // Assume 1-hour tokens, refresh at 55 min
        return now - lastRefresh >= tokenLifetimeSeconds
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
