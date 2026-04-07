import Foundation
import Security

actor ClaudeProvider {
    private let keychainService = "Claude Code-credentials"
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let scopes = "user:profile user:inference user:sessions:claude_code user:mcp_servers"
    private let refreshBufferMs: Double = 5 * 60 * 1000 // 5 minutes
    private let costEstimator = ClaudeCostEstimator()

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

    func fetchUsage() async throws -> Provider {
        guard var credentials = loadCredentials() else {
            return Provider(
                id: "claude",
                name: "Claude",
                icon: "brain",
                items: [],
                status: .notConnected(url: settingsURL)
            )
        }

        // Refresh token if needed
        if needsRefresh(credentials.claudeAiOauth) {
            if let refreshed = try? await refreshToken(credentials: &credentials) {
                credentials.claudeAiOauth?.accessToken = refreshed
                saveCredentials(credentials)
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
                saveCredentials(credentials)
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
            items.append(UsageItem(
                label: "Session",
                current: utilization,
                limit: 100,
                resetLabel: formatResetTime(fiveHour.resets_at)
            ))
        }

        if let sevenDay = usage.seven_day, let utilization = sevenDay.utilization {
            items.append(UsageItem(
                label: "Weekly",
                current: utilization,
                limit: 100,
                resetLabel: formatResetTime(sevenDay.resets_at)
            ))
        }

        if let sonnet = usage.seven_day_sonnet, let utilization = sonnet.utilization {
            items.append(UsageItem(
                label: "Sonnet",
                current: utilization,
                limit: 100,
                resetLabel: formatResetTime(sonnet.resets_at)
            ))
        }

        if let opus = usage.seven_day_opus, let utilization = opus.utilization {
            items.append(UsageItem(
                label: "Opus",
                current: utilization,
                limit: 100,
                resetLabel: formatResetTime(opus.resets_at)
            ))
        }

        // 2x detection
        let detector = Claude2xDetector.loadFromDisk()
        let boostStatus = detector.status()

        // Cost estimation (caller controls visibility via showCostEstimate)
        let costEstimate = await costEstimator.estimateCurrentMonth()

        return Provider(
            id: "claude",
            name: "Claude",
            icon: "brain",
            items: items,
            status: items.isEmpty ? .error("No usage data") : .loaded,
            boostStatus: boostStatus,
            costEstimate: costEstimate?.totalCost
        )
    }

    private func loadCredentials() -> Credentials? {
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

    private func saveCredentials(_ credentials: Credentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
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

    private func formatResetTime(_ isoString: String?) -> String? {
        guard let isoString = isoString else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else {
            return nil
        }

        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return nil }

        let hours = Int(diff / 3600)
        let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 24 {
            let days = hours / 24
            return "\(days)d"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
