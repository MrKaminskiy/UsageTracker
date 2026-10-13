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
        /// Separately metered limits (e.g. a model with its own cap), each with its own windows.
        var additionalRateLimits: LossyArray<AdditionalRateLimit>?
        /// Workspace plans: the member's monthly credit cap.
        var spendControl: SpendControl?
        var rateLimitResetCredits: ResetCredits?

        enum CodingKeys: String, CodingKey {
            case rateLimit = "rate_limit"
            case codeReviewRateLimit = "code_review_rate_limit"
            case credits
            case planType = "plan_type"
            case additionalRateLimits = "additional_rate_limits"
            case spendControl = "spend_control"
            case rateLimitResetCredits = "rate_limit_reset_credits"
        }

        struct SpendControl: Codable {
            var individualLimit: IndividualLimit?

            enum CodingKeys: String, CodingKey {
                case individualLimit = "individual_limit"
            }
        }

        /// Codex's backend sends the amounts as strings; the percent and reset fields are
        /// read leniently too, so an unexpected type drops this row instead of failing the
        /// whole usage decode.
        struct IndividualLimit: Codable {
            var limit: Double?
            var used: Double?
            var remaining: Double?
            var usedPercent: Double?
            var remainingPercent: Double?
            var resetAfterSeconds: Int?
            var resetAt: Double?

            enum CodingKeys: String, CodingKey {
                case limit, used, remaining
                case usedPercent = "used_percent"
                case remainingPercent = "remaining_percent"
                case resetAfterSeconds = "reset_after_seconds"
                case resetAt = "reset_at"
            }

            init(limit: Double? = nil, used: Double? = nil, remaining: Double? = nil,
                 usedPercent: Double? = nil, remainingPercent: Double? = nil,
                 resetAfterSeconds: Int? = nil, resetAt: Double? = nil) {
                self.limit = limit
                self.used = used
                self.remaining = remaining
                self.usedPercent = usedPercent
                self.remainingPercent = remainingPercent
                self.resetAfterSeconds = resetAfterSeconds
                self.resetAt = resetAt
            }

            init(from decoder: Decoder) throws {
                self.init()
                guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
                func number(_ key: CodingKeys) -> Double? {
                    let value = (try? c.decodeIfPresent(Double.self, forKey: key))
                        ?? (try? c.decodeIfPresent(String.self, forKey: key)).flatMap { $0 }.flatMap(Double.init)
                    // `Double("nan")` and `Double("1e30")` parse; neither is a usable amount.
                    guard let value, value.isFinite, abs(value) < 1e12 else { return nil }
                    return value
                }
                limit = number(.limit)
                used = number(.used)
                remaining = number(.remaining)
                usedPercent = number(.usedPercent)
                remainingPercent = number(.remainingPercent)
                resetAfterSeconds = number(.resetAfterSeconds).map { Int($0) }
                resetAt = number(.resetAt)
            }
        }

        /// Banked "full reset" credits the user can redeem from Codex's /usage.
        struct ResetCredits: Codable {
            var availableCount: Int?

            enum CodingKeys: String, CodingKey {
                case availableCount = "available_count"
            }

            init(from decoder: Decoder) throws {
                availableCount = try? decoder.container(keyedBy: CodingKeys.self)
                    .decodeIfPresent(Int.self, forKey: .availableCount)
            }
        }

        struct AdditionalRateLimit: Codable {
            var limitName: String?
            var meteredFeature: String?
            var rateLimit: RateLimit?

            enum CodingKeys: String, CodingKey {
                case limitName = "limit_name"
                case meteredFeature = "metered_feature"
                case rateLimit = "rate_limit"
            }
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
            var hasCredits: Bool?
            var unlimited: Bool?
            var balance: String?

            enum CodingKeys: String, CodingKey {
                case hasCredits = "has_credits"
                case unlimited
                case balance
            }
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
            // Rate limits and server errors are transient: throw so the caller keeps the
            // last-known reading instead of replacing it with an empty error row.
            if isTransientHTTPStatus(httpResponse.statusCode) {
                throw URLError(.init(rawValue: httpResponse.statusCode))
            }
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

        // Primary usage: the five-hour window, except on Pro plans, which have no
        // five-hour limit and send their weekly window here with no secondary.
        if let percent = usage.rateLimit?.primaryWindow?.usedPercent {
            let window = usage.rateLimit?.primaryWindow
            let resetLabel = Self.formatResetTime(window?.resetAfterSeconds)
            items.append(UsageItem(
                label: Self.windowLabel(window, fallback: "Session"),
                current: percent,
                limit: 100,
                resetLabel: resetLabel,
                resetsAt: Self.resetDate(for: window),
                pinKey: Self.pinKey(for: window, fallback: "Session")
            ))
        }

        // Secondary usage (normally the weekly window).
        if let percent = usage.rateLimit?.secondaryWindow?.usedPercent {
            let window = usage.rateLimit?.secondaryWindow
            let resetLabel = Self.formatResetTime(window?.resetAfterSeconds)
            items.append(UsageItem(
                label: Self.windowLabel(window, fallback: "Weekly"),
                current: percent,
                limit: 100,
                resetLabel: resetLabel,
                resetsAt: Self.resetDate(for: window),
                pinKey: Self.pinKey(for: window, fallback: "Weekly")
            ))
        }

        items.append(contentsOf: Self.additionalLimitItems(usage.additionalRateLimits?.elements))
        if let spendItem = Self.spendControlItem(usage.spendControl) {
            items.append(spendItem)
        }

        // Code reviews
        if let percent = usage.codeReviewRateLimit?.primaryWindow?.usedPercent {
            let window = usage.codeReviewRateLimit?.primaryWindow
            let resetLabel = Self.formatResetTime(window?.resetAfterSeconds)
            items.append(UsageItem(
                label: "Code review",
                current: percent,
                limit: 100,
                resetLabel: resetLabel,
                resetsAt: Self.resetDate(for: window),
                pinKey: "Reviews"
            ))
        }

        let localInsights = await CodexInsightsAnalyzer().analyze()
        let accountInsights = CodexInsights(
            today: localInsights?.today,
            recentThreads: localInsights?.recentThreads ?? [],
            models: localInsights?.models ?? [],
            creditBalance: Self.creditBalance(usage.credits),
            resetCreditsAvailable: usage.rateLimitResetCredits?.availableCount
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

    private static func resetDate(for window: UsageResponse.Window?) -> Date? {
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

    private static func formatResetTime(_ seconds: Int?) -> String? {
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
        let day = 24 * 60 * 60
        switch seconds {
        case 0..<(60 * 60):
            let minutes = max(1, seconds / 60)
            return "\(minutes)m"
        case (60 * 60)..<day:
            let hours = max(1, seconds / 3600)
            return "\(hours)h"
        case day..<(2 * day):
            return "Daily"
        case (7 * day)..<(8 * day):
            return "Weekly"
        case (28 * day)..<(32 * day):
            return "Monthly"
        case (365 * day)..<(367 * day):
            return "Annual"
        default:
            return fallback
        }
    }

    static func additionalLimitItems(_ limits: [UsageResponse.AdditionalRateLimit]?) -> [UsageItem] {
        var items: [UsageItem] = []
        for limit in limits ?? [] {
            guard let name = limit.limitName ?? limit.meteredFeature, !name.isEmpty else { continue }
            let key = limit.meteredFeature ?? name
            for (window, fallback) in [(limit.rateLimit?.primaryWindow, "Session"), (limit.rateLimit?.secondaryWindow, "Weekly")] {
                guard let window, let percent = window.usedPercent else { continue }
                items.append(UsageItem(
                    label: "\(name) \(windowLabel(window, fallback: fallback))",
                    current: percent,
                    limit: 100,
                    resetLabel: formatResetTime(window.resetAfterSeconds),
                    resetsAt: resetDate(for: window),
                    pinKey: "\(key).\(fallback)"
                ))
            }
        }
        return items
    }

    /// Pins follow the window's length, not its slot: a Pro plan's weekly window arrives in
    /// the primary slot, and two windows must never share a key.
    static func pinKey(for window: UsageResponse.Window?, fallback: String) -> String {
        guard let seconds = window?.limitWindowSeconds, seconds > 0 else { return fallback }
        return seconds < 24 * 60 * 60 ? "Session" : windowLabel(window, fallback: fallback)
    }

    static func spendControlItem(_ spendControl: UsageResponse.SpendControl?) -> UsageItem? {
        guard let cap = spendControl?.individualLimit else { return nil }
        let used = cap.used ?? cap.limit.flatMap { limit in cap.remaining.map { limit - $0 } }
        let percent = cap.usedPercent ?? cap.remainingPercent.map { 100 - $0 } ?? {
            guard let used, let limit = cap.limit, limit > 0 else { return nil }
            return used / limit * 100
        }()
        guard let percent else { return nil }
        let amounts = used.flatMap { used in
            cap.limit.map { "\(ClaudeProvider.formatCredits(used))/\(ClaudeProvider.formatCredits($0))" }
        }
        let window = UsageResponse.Window(usedPercent: percent, limitWindowSeconds: nil,
                                          resetAfterSeconds: cap.resetAfterSeconds, resetAt: cap.resetAt)
        // When the trailing slot carries amounts, leave resetsAt unset: the cache restore
        // and carry-forward paths rewrite the label as a countdown for any dated row.
        return UsageItem(
            label: "Monthly credits",
            current: percent,
            limit: 100,
            resetLabel: amounts ?? formatResetTime(cap.resetAfterSeconds),
            resetsAt: amounts == nil ? resetDate(for: window) : nil,
            pinKey: "SpendControl"
        )
    }

    /// `has_credits: false` arrives with a `"0"` balance, which is noise rather than a reading.
    static func creditBalance(_ credits: UsageResponse.Credits?) -> String? {
        guard let credits else { return nil }
        if credits.unlimited == true { return "Unlimited" }
        if credits.hasCredits == false { return nil }
        return credits.balance
    }

    static func planLabel(from planType: String?) -> String? {
        guard let planType, !planType.isEmpty else { return nil }
        // Codex's PlanType enum (v0.153) splits these families into billing variants
        // whose raw names don't fit the plan chip.
        switch planType {
        case "prolite": return "Pro Lite"
        case "self_serve_business_prolite", "self_serve_business_usage_based": return "Business"
        case "ent26", "enterprise_cbp_automation", "enterprise_cbp_usage_based": return "Enterprise"
        case "edu_plus", "edu_pro", "education": return "Edu"
        default: return planType.replacingOccurrences(of: "_", with: " ").capitalized
        }
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
