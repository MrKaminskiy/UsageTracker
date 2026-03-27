import Foundation

actor OpenRouterProvider {
    private let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!
    private let keyInfoURL = URL(string: "https://openrouter.ai/api/v1/key")!
    private let settingsURL = URL(string: "https://openrouter.ai/settings/keys")!

    private var apiKey: String? {
        let configPath = NSString(string: "~/.usagetracker/openrouter.json").expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: configPath),
              let config = try? JSONDecoder().decode(APIKeyConfig.self, from: data) else {
            return nil
        }
        return config.apiKey
    }

    struct APIKeyConfig: Codable {
        var apiKey: String?

        enum CodingKeys: String, CodingKey {
            case apiKey = "api_key"
        }
    }

    struct CreditsResponse: Codable {
        var data: CreditsData

        struct CreditsData: Codable {
            var totalCredits: Double?
            var totalUsage: Double?

            enum CodingKeys: String, CodingKey {
                case totalCredits = "total_credits"
                case totalUsage = "total_usage"
            }
        }
    }

    struct KeyResponse: Codable {
        var data: KeyData

        struct KeyData: Codable {
            var usage: Double?
            var usageDaily: Double?
            var usageWeekly: Double?
            var usageMonthly: Double?
            var limit: Double?
            var limitRemaining: Double?
            var isFreeTier: Bool?

            enum CodingKeys: String, CodingKey {
                case usage
                case usageDaily = "usage_daily"
                case usageWeekly = "usage_weekly"
                case usageMonthly = "usage_monthly"
                case limit
                case limitRemaining = "limit_remaining"
                case isFreeTier = "is_free_tier"
            }
        }
    }

    func fetchUsage() async throws -> Provider {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            return Provider(
                id: "openrouter",
                name: "OpenRouter",
                icon: "arrow.trianglehead.branch",
                items: [],
                status: .notConnected(url: settingsURL)
            )
        }

        // Try /api/v1/credits first (management key — account-level totals)
        if let result = try? await fetchCredits(apiKey) {
            return result
        }

        // Fall back to /api/v1/key (regular key — per-key usage)
        return try await fetchKeyUsage(apiKey)
    }

    private func fetchCredits(_ apiKey: String) async throws -> Provider {
        var request = URLRequest(url: creditsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw URLError(.badServerResponse)
        }

        let credits = try JSONDecoder().decode(CreditsResponse.self, from: data)
        let totalCredits = credits.data.totalCredits ?? 0
        let totalUsage = credits.data.totalUsage ?? 0
        let remaining = totalCredits - totalUsage

        var items: [UsageItem] = []

        if totalCredits > 0 {
            let percentage = (totalUsage / totalCredits) * 100
            items.append(UsageItem(
                label: "Credits Used",
                current: percentage,
                limit: 100,
                resetLabel: String(format: "$%.2f / $%.2f", totalUsage, totalCredits)
            ))
        } else {
            items.append(UsageItem(
                label: "Total Usage",
                current: 0,
                limit: 0,
                resetLabel: String(format: "$%.2f", totalUsage)
            ))
        }

        return Provider(id: "openrouter", name: "OpenRouter", icon: "arrow.trianglehead.branch", items: items, status: .loaded)
    }

    private func fetchKeyUsage(_ apiKey: String) async throws -> Provider {
        var request = URLRequest(url: keyInfoURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return Provider(id: "openrouter", name: "OpenRouter", icon: "arrow.trianglehead.branch", items: [], status: .error("Invalid response"))
        }

        if httpResponse.statusCode == 401 {
            return Provider(id: "openrouter", name: "OpenRouter", icon: "arrow.trianglehead.branch", items: [], status: .error("Invalid key"))
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            return Provider(id: "openrouter", name: "OpenRouter", icon: "arrow.trianglehead.branch", items: [], status: .error(httpErrorMessage(httpResponse.statusCode)))
        }

        guard let keyResponse = try? JSONDecoder().decode(KeyResponse.self, from: data) else {
            return Provider(id: "openrouter", name: "OpenRouter", icon: "arrow.trianglehead.branch", items: [], status: .error("Failed to parse response"))
        }

        let keyData = keyResponse.data
        let usageMonthly = keyData.usageMonthly ?? 0
        let usageDaily = keyData.usageDaily ?? 0

        var items: [UsageItem] = []

        if let limit = keyData.limit, limit > 0 {
            let percentage = (usageMonthly / limit) * 100
            items.append(UsageItem(
                label: "Monthly Spend",
                current: percentage,
                limit: 100,
                resetLabel: String(format: "$%.2f / $%.2f", usageMonthly, limit)
            ))
        } else {
            items.append(UsageItem(
                label: "Monthly Spend",
                current: 0,
                limit: 0,
                resetLabel: String(format: "$%.2f", usageMonthly)
            ))
        }

        items.append(UsageItem(
            label: "Daily Spend",
            current: 0,
            limit: 0,
            resetLabel: String(format: "$%.2f today", usageDaily)
        ))

        return Provider(id: "openrouter", name: "OpenRouter", icon: "arrow.trianglehead.branch", items: items, status: .loaded)
    }
}
