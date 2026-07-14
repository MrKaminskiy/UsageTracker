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
            var idToken: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case accountId = "account_id"
                case idToken = "id_token"
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
            case planType = "plan_type"
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
            var limitWindowSeconds: Int?
            var resetAfterSeconds: Int?
            var resetAt: Double?

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case limitWindowSeconds = "limit_window_seconds"
                case resetAfterSeconds = "reset_after_seconds"
                case resetAt = "reset_at"
            }
        }

        struct Credits: Codable {
            var balance: String?
        }

        var planType: String?
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
                status: .error(httpErrorMessage(httpResponse.statusCode))
            )
        }

        let usage = try JSONDecoder().decode(UsageResponse.self, from: data)

        var items: [UsageItem] = []

        // Primary usage (normally the five-hour window).
        if let percent = usage.rateLimit?.primaryWindow?.usedPercent {
            let window = usage.rateLimit?.primaryWindow
            let resetLabel = formatResetTime(window?.resetAfterSeconds)
            items.append(UsageItem(
                label: Self.windowLabel(window, fallback: "Session"),
                current: percent,
                limit: 100,
                resetLabel: resetLabel,
                resetsAt: resetDate(for: window),
                pinKey: "Session"
            ))
        }

        // Secondary usage (normally the weekly window).
        if let percent = usage.rateLimit?.secondaryWindow?.usedPercent {
            let window = usage.rateLimit?.secondaryWindow
            let resetLabel = formatResetTime(window?.resetAfterSeconds)
            items.append(UsageItem(
                label: Self.windowLabel(window, fallback: "Weekly"),
                current: percent,
                limit: 100,
                resetLabel: resetLabel,
                resetsAt: resetDate(for: window),
                pinKey: "Weekly"
            ))
        }

        // Code reviews
        if let percent = usage.codeReviewRateLimit?.primaryWindow?.usedPercent {
            let window = usage.codeReviewRateLimit?.primaryWindow
            let resetLabel = formatResetTime(window?.resetAfterSeconds)
            items.append(UsageItem(
                label: "Code review",
                current: percent,
                limit: 100,
                resetLabel: resetLabel,
                resetsAt: resetDate(for: window),
                pinKey: "Reviews"
            ))
        }

        let localInsights = await CodexInsightsAnalyzer().analyze()
        let accountInsights = CodexInsights(
            today: localInsights?.today,
            recentThreads: localInsights?.recentThreads ?? [],
            models: localInsights?.models ?? [],
            creditBalance: usage.credits?.balance
        )

        return Provider(
            id: "codex",
            name: "Codex",
            icon: "terminal.fill",
            items: items,
            status: items.isEmpty ? .error("No usage data") : .loaded,
            planLabel: Self.planLabel(from: usage.planType) ?? Self.planLabel(fromIDToken: auth.tokens?.idToken),
            codexInsights: accountInsights
        )
    }

    private func resetDate(for window: UsageResponse.Window?) -> Date? {
        if let seconds = window?.resetAfterSeconds, seconds > 0 {
            return Date().addingTimeInterval(TimeInterval(seconds))
        }
        guard let timestamp = window?.resetAt, timestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: timestamp)
        // Rate-limit windows reset within days/weeks; a value this far out means the
        // timestamp unit assumption (seconds) was wrong, so surface nothing rather than garbage.
        guard date.timeIntervalSinceNow < 400 * 24 * 60 * 60 else { return nil }
        return date
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

    static func windowLabel(_ window: UsageResponse.Window?, fallback: String) -> String {
        guard let seconds = window?.limitWindowSeconds, seconds > 0 else { return fallback }
        switch seconds {
        case 0..<(60 * 60):
            let minutes = max(1, seconds / 60)
            return "\(minutes)m"
        case (60 * 60)..<(24 * 60 * 60):
            let hours = max(1, seconds / 3600)
            return "\(hours)h"
        default:
            return fallback
        }
    }

    static func planLabel(from planType: String?) -> String? {
        guard let planType, !planType.isEmpty else { return nil }
        return planType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func planLabel(fromIDToken idToken: String?) -> String? {
        guard let idToken else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let authClaims = json["https://api.openai.com/auth"] as? [String: Any]
        let plan = json["chatgpt_plan_type"] as? String
            ?? authClaims?["chatgpt_plan_type"] as? String
            ?? authClaims?["plan_type"] as? String
        return planLabel(from: plan)
    }
}
