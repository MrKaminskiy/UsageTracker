import Foundation

actor OpenAIProvider {
    private let billingURL = URL(string: "https://api.openai.com/v1/dashboard/billing/subscription")!
    private let usageURL = URL(string: "https://api.openai.com/v1/dashboard/billing/usage")!
    private let settingsURL = URL(string: "https://platform.openai.com/usage")!

    private var apiKey: String? {
        let configPath = NSString(string: "~/.usagetracker/openai.json").expandingTildeInPath
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

    struct SubscriptionResponse: Codable {
        var hardLimitUsd: Double?
        var softLimitUsd: Double?

        enum CodingKeys: String, CodingKey {
            case hardLimitUsd = "hard_limit_usd"
            case softLimitUsd = "soft_limit_usd"
        }
    }

    struct UsageResponse: Codable {
        var totalUsage: Double? // in cents

        enum CodingKeys: String, CodingKey {
            case totalUsage = "total_usage"
        }
    }

    func fetchUsage() async throws -> Provider {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            return Provider(
                id: "openai",
                name: "OpenAI API",
                icon: "sparkles",
                items: [],
                status: .notConnected(url: settingsURL)
            )
        }

        // Get subscription info (limits)
        var subRequest = URLRequest(url: billingURL)
        subRequest.httpMethod = "GET"
        subRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        subRequest.timeoutInterval = 10

        // Get usage for current month
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

        var usageURLWithParams = URLComponents(url: usageURL, resolvingAgainstBaseURL: false)!
        usageURLWithParams.queryItems = [
            URLQueryItem(name: "start_date", value: formatDate(startOfMonth)),
            URLQueryItem(name: "end_date", value: formatDate(now))
        ]

        var usageRequest = URLRequest(url: usageURLWithParams.url!)
        usageRequest.httpMethod = "GET"
        usageRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        usageRequest.timeoutInterval = 10

        // Fetch both concurrently
        async let subResult = URLSession.shared.data(for: subRequest)
        async let usageResult = URLSession.shared.data(for: usageRequest)

        let (subData, subResponse) = try await subResult
        let (usageData, usageResponse) = try await usageResult

        guard let subHttpResponse = subResponse as? HTTPURLResponse,
              let usageHttpResponse = usageResponse as? HTTPURLResponse else {
            return Provider(
                id: "openai",
                name: "OpenAI API",
                icon: "sparkles",
                items: [],
                status: .error("Invalid response")
            )
        }

        if subHttpResponse.statusCode == 401 || usageHttpResponse.statusCode == 401 {
            return Provider(
                id: "openai",
                name: "OpenAI API",
                icon: "sparkles",
                items: [],
                status: .error("Invalid API key")
            )
        }

        guard subHttpResponse.statusCode >= 200 && subHttpResponse.statusCode < 300,
              usageHttpResponse.statusCode >= 200 && usageHttpResponse.statusCode < 300 else {
            return Provider(
                id: "openai",
                name: "OpenAI API",
                icon: "sparkles",
                items: [],
                status: .error("HTTP error")
            )
        }

        let subscription = try? JSONDecoder().decode(SubscriptionResponse.self, from: subData)
        let usage = try? JSONDecoder().decode(UsageResponse.self, from: usageData)

        var items: [UsageItem] = []

        if let totalUsageCents = usage?.totalUsage {
            let usedUsd = totalUsageCents / 100.0
            let limit = subscription?.hardLimitUsd ?? subscription?.softLimitUsd ?? 120.0

            if limit > 0 {
                let percentage = (usedUsd / limit) * 100
                let daysLeft = daysUntilEndOfMonth()
                items.append(UsageItem(
                    label: "Usage",
                    current: min(percentage, 100),
                    limit: 100,
                    resetLabel: "\(daysLeft)d"
                ))
            }
        }

        return Provider(
            id: "openai",
            name: "OpenAI API",
            icon: "sparkles",
            items: items,
            status: items.isEmpty ? .error("No usage data") : .loaded
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func daysUntilEndOfMonth() -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1),
                                              to: calendar.date(from: calendar.dateComponents([.year, .month], from: now))!) else {
            return 0
        }
        let days = calendar.dateComponents([.day], from: now, to: endOfMonth).day ?? 0
        return max(0, days)
    }
}
