import Foundation

actor CodexProvider {
    private let authPath = NSString(string: "~/.codex/auth.json").expandingTildeInPath
    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    private let settingsURL = URL(string: "https://chatgpt.com/")!

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
            var accountId: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case accountId = "account_id"
            }
        }
    }

    struct UsageResponse: Codable {
        var rateLimit: RateLimit?
        var codeReviewRateLimit: CodeReviewRateLimit?
        var credits: Credits?

        enum CodingKeys: String, CodingKey {
            case rateLimit = "rate_limit"
            case codeReviewRateLimit = "code_review_rate_limit"
            case credits
        }

        struct RateLimit: Codable {
            var primaryWindow: Window?
            var secondaryWindow: Window?

            enum CodingKeys: String, CodingKey {
                case primaryWindow = "primary_window"
                case secondaryWindow = "secondary_window"
            }
        }

        struct CodeReviewRateLimit: Codable {
            var primaryWindow: Window?

            enum CodingKeys: String, CodingKey {
                case primaryWindow = "primary_window"
            }
        }

        struct Window: Codable {
            var usedPercent: Double?
            var resetAfterSeconds: Int?
            var resetAt: Double?

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case resetAfterSeconds = "reset_after_seconds"
                case resetAt = "reset_at"
            }
        }

        struct Credits: Codable {
            var balance: String?
        }
    }

    func fetchUsage() async throws -> Provider {
        // Read auth file
        guard let authData = FileManager.default.contents(atPath: authPath),
              let auth = try? JSONDecoder().decode(AuthFile.self, from: authData),
              let accessToken = auth.tokens?.accessToken else {
            return Provider(
                id: "codex",
                name: "Codex",
                icon: "terminal.fill",
                items: [],
                status: .notConnected(url: settingsURL)
            )
        }

        // Fetch usage
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UsageTracker", forHTTPHeaderField: "User-Agent")
        if let accountId = auth.tokens?.accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return Provider(
                id: "codex",
                name: "Codex",
                icon: "terminal.fill",
                items: [],
                status: .error("Invalid response")
            )
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            return Provider(
                id: "codex",
                name: "Codex",
                icon: "terminal.fill",
                items: [],
                status: .error("Token expired. Run `codex login`")
            )
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            return Provider(
                id: "codex",
                name: "Codex",
                icon: "terminal.fill",
                items: [],
                status: .error("HTTP \(httpResponse.statusCode)")
            )
        }

        let usage = try JSONDecoder().decode(UsageResponse.self, from: data)

        var items: [UsageItem] = []

        // Session usage (5 hour window)
        if let percent = usage.rateLimit?.primaryWindow?.usedPercent {
            let resetLabel = formatResetTime(usage.rateLimit?.primaryWindow?.resetAfterSeconds)
            items.append(UsageItem(
                label: "Session",
                current: percent,
                limit: 100,
                resetLabel: resetLabel
            ))
        }

        // Weekly usage
        if let percent = usage.rateLimit?.secondaryWindow?.usedPercent {
            let resetLabel = formatResetTime(usage.rateLimit?.secondaryWindow?.resetAfterSeconds)
            items.append(UsageItem(
                label: "Weekly",
                current: percent,
                limit: 100,
                resetLabel: resetLabel
            ))
        }

        // Code reviews
        if let percent = usage.codeReviewRateLimit?.primaryWindow?.usedPercent {
            let resetLabel = formatResetTime(usage.codeReviewRateLimit?.primaryWindow?.resetAfterSeconds)
            items.append(UsageItem(
                label: "Reviews",
                current: percent,
                limit: 100,
                resetLabel: resetLabel
            ))
        }

        return Provider(
            id: "codex",
            name: "Codex",
            icon: "terminal.fill",
            items: items,
            status: items.isEmpty ? .error("No usage data") : .loaded
        )
    }

    private func formatResetTime(_ seconds: Int?) -> String? {
        guard let seconds = seconds, seconds > 0 else { return nil }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours >= 24 {
            let days = hours / 24
            return "\(days)d"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
