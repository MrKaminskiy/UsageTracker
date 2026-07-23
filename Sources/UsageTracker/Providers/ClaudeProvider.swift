import Foundation
import Security

actor ClaudeProvider {
    private let keychainService = "Claude Code-credentials"
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let scopes = "user:profile user:inference user:sessions:claude_code user:mcp_servers"
    private let refreshBufferMs: Double = 5 * 60 * 1000 // 5 minutes
    private let insightsAnalyzer = ClaudeInsightsAnalyzer()

    struct Credentials: Codable {
        var claudeAiOauth: OAuthData?

        struct OAuthData: Codable {
            var accessToken: String
            var refreshToken: String?
            var expiresAt: Double?
            var subscriptionType: String?
        }
    }

    struct UsageResponse: Codable {
        var five_hour: UsageData?
        var seven_day: UsageData?
        var seven_day_sonnet: UsageData?
        var seven_day_opus: UsageData?
        var extra_usage: ExtraUsage?

        struct UsageData: Codable {
            var utilization: Double?
            var resets_at: String?
        }

        struct ExtraUsage: Codable {
            var is_enabled: Bool?
            var used_credits: Double?
            var monthly_limit: Double?
        }
    }

    private let settingsURL = URL(string: "https://claude.ai/settings/usage")!

    private enum CredentialSource {
        case keychain
        case file(URL)
    }

    func fetchUsage() async throws -> Provider {
        guard let loaded = loadCredentials() else {
            return Provider(
                id: "claude",
                name: "Claude",
                icon: "brain",
                items: [],
                status: .notConnected(url: settingsURL)
            )
        }
        var credentials = loaded.credentials
        let source = loaded.source

        // Refresh token if needed
        if needsRefresh(credentials.claudeAiOauth) {
            if let refreshed = try? await refreshToken(credentials: &credentials) {
                credentials.claudeAiOauth?.accessToken = refreshed
                saveCredentials(credentials, to: source)
            }
        }

        guard let oauth = credentials.claudeAiOauth else {
            return Provider(
                id: "claude",
                name: "Claude",
                icon: "brain",
                items: [],
                status: .error("Invalid credentials")
            )
        }

        // Fetch usage
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(oauth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("UsageTracker", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return Provider(
                id: "claude",
                name: "Claude",
                icon: "brain",
                items: [],
                status: .error("Invalid response")
            )
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            // Try refresh and retry once
            if let refreshed = try? await refreshToken(credentials: &credentials) {
                credentials.claudeAiOauth?.accessToken = refreshed
                saveCredentials(credentials, to: source)
                return try await fetchUsage() // Retry
            }
            return Provider(
                id: "claude",
                name: "Claude",
                icon: "brain",
                items: [],
                status: .error("Token expired. Run `claude` to log in again.")
            )
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            // Throw on transient errors (rate limit, server errors) so the caller can
            // preserve the last-known data instead of replacing it with an error state.
            if httpResponse.statusCode == 429 || httpResponse.statusCode >= 500 {
                throw URLError(.init(rawValue: httpResponse.statusCode))
            }
            return Provider(
                id: "claude",
                name: "Claude",
                icon: "brain",
                items: [],
                status: .error(httpErrorMessage(httpResponse.statusCode))
            )
        }

        let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
        var items: [UsageItem] = []

        if let fiveHour = usage.five_hour, let utilization = fiveHour.utilization {
            let resetDate = parseResetDate(fiveHour.resets_at)
            items.append(UsageItem(
                label: "Session",
                current: utilization,
                limit: 100,
                resetLabel: relativeResetLabel(resetDate),
                resetsAt: resetDate
            ))
        }

        if let sevenDay = usage.seven_day, let utilization = sevenDay.utilization {
            let resetDate = parseResetDate(sevenDay.resets_at)
            items.append(UsageItem(
                label: "Weekly",
                current: utilization,
                limit: 100,
                resetLabel: relativeResetLabel(resetDate),
                resetsAt: resetDate
            ))
        }

        if let sonnet = usage.seven_day_sonnet, let utilization = sonnet.utilization {
            let resetDate = parseResetDate(sonnet.resets_at)
            items.append(UsageItem(
                label: "Sonnet",
                current: utilization,
                limit: 100,
                resetLabel: relativeResetLabel(resetDate),
                resetsAt: resetDate
            ))
        }

        if let opus = usage.seven_day_opus, let utilization = opus.utilization {
            let resetDate = parseResetDate(opus.resets_at)
            items.append(UsageItem(
                label: "Opus",
                current: utilization,
                limit: 100,
                resetLabel: relativeResetLabel(resetDate),
                resetsAt: resetDate
            ))
        }

        if let extraItem = Self.extraCreditsItem(from: usage.extra_usage) {
            items.append(extraItem)
        }

        // 2x detection
        let detector = Claude2xDetector.loadFromDisk()
        let boostStatus = detector.status()

        // Cost estimation + local usage insights (caller controls cost visibility via showCostEstimate)
        let insights = await insightsAnalyzer.analyze()

        return Provider(
            id: "claude",
            name: "Claude",
            icon: "brain",
            items: items,
            status: items.isEmpty ? .error("No usage data") : .loaded,
            boostStatus: boostStatus,
            costEstimate: insights?.monthlyCost,
            planLabel: Self.planLabel(from: oauth.subscriptionType),
            insights: insights
        )
    }

    private func loadCredentials() -> (credentials: Credentials, source: CredentialSource)? {
        if let creds = loadFromKeychain() {
            return (creds, .keychain)
        }
        let fileURL = credentialsFileURL()
        if let creds = loadFromFile(fileURL) {
            return (creds, .file(fileURL))
        }
        return nil
    }

    private func credentialsFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }

    private func loadFromKeychain() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
            return nil
        }

        return credentials
    }

    private func loadFromFile(_ url: URL) -> Credentials? {
        guard let data = try? Data(contentsOf: url),
              let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
            return nil
        }
        return credentials
    }

    private func saveCredentials(_ credentials: Credentials, to source: CredentialSource) {
        switch source {
        case .keychain:
            guard let data = try? JSONEncoder().encode(credentials) else { return }
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        case .file:
            // Skip persisting to ~/.claude/.credentials.json — Claude Code CLI owns
            // the file and stores fields beyond our schema (scopes, rateLimitTier)
            // that a round-trip would strip. The refreshed access token is used
            // in-memory for this session; Claude Code refreshes its own copy.
            break
        }
    }

    private func needsRefresh(_ oauth: Credentials.OAuthData?) -> Bool {
        guard let oauth = oauth, let expiresAt = oauth.expiresAt else { return true }
        let now = Date().timeIntervalSince1970 * 1000
        return now + refreshBufferMs >= expiresAt
    }

    private func refreshToken(credentials: inout Credentials) async throws -> String? {
        guard let refreshToken = credentials.claudeAiOauth?.refreshToken else { return nil }

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "scope": scopes
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            return nil
        }

        struct RefreshResponse: Codable {
            var access_token: String
            var refresh_token: String?
            var expires_in: Int?
        }

        let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)

        credentials.claudeAiOauth?.accessToken = refreshResponse.access_token
        if let newRefresh = refreshResponse.refresh_token {
            credentials.claudeAiOauth?.refreshToken = newRefresh
        }
        if let expiresIn = refreshResponse.expires_in {
            credentials.claudeAiOauth?.expiresAt = Date().timeIntervalSince1970 * 1000 + Double(expiresIn * 1000)
        }

        return refreshResponse.access_token
    }

    static func extraCreditsItem(from extra: UsageResponse.ExtraUsage?) -> UsageItem? {
        guard let extra, extra.is_enabled == true,
              let limitMinor = extra.monthly_limit, limitMinor > 0 else { return nil }
        // The API reports credits in minor units (verified live: 1610/5000 =
        // €16.10 of €50.00) and exposes no currency, so no symbol is shown.
        // Amounts ride in the trailing detail slot (resetLabel) so the row
        // keeps the standard bar + percentage layout.
        let used = (extra.used_credits ?? 0) / 100
        let limit = limitMinor / 100
        return UsageItem(
            label: "Extra credits",
            current: used,
            limit: limit,
            resetLabel: "\(formatCredits(used))/\(formatCredits(limit))",
            kind: .extraUsage
        )
    }

    static func formatCredits(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }

    static func formatDollars(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "$%.0f", value)
            : String(format: "$%.2f", value)
    }

    static func planLabel(from subscriptionType: String?) -> String? {
        guard let type = subscriptionType, !type.isEmpty else { return nil }
        switch type.lowercased() {
        case "max": return "Max"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return type.capitalized
        }
    }

    private func parseResetDate(_ isoString: String?) -> Date? {
        guard let isoString = isoString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString)
    }

    private func relativeResetLabel(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return nil }
        let hours = Int(diff / 3600)
        let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 24 {
            return "\(hours / 24)d"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
