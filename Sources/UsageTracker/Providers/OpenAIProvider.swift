import Foundation

actor OpenAIProvider {
    private let usageURL = URL(string: "https://api.openai.com/v1/usage")!
    private let costsURL = URL(string: "https://api.openai.com/v1/organization/costs")!
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

    struct CostsResponse: Codable {
        var object: String?
        var data: [CostBucket]?

        struct CostBucket: Codable {
            var results: [CostResult]?
        }

        struct CostResult: Codable {
            var amount: CostAmount?

            struct CostAmount: Codable {
                var value: String?  // API returns string, not number

                var doubleValue: Double {
                    Double(value ?? "0") ?? 0
                }
            }
        }
    }

    struct UsageResponse: Codable {
        var object: String?
        var data: [UsageData]?
        var whisperApiData: [UsageData]?
        var dalleApiData: [UsageData]?
        var ttsApiData: [UsageData]?

        enum CodingKeys: String, CodingKey {
            case object, data
            case whisperApiData = "whisper_api_data"
            case dalleApiData = "dalle_api_data"
            case ttsApiData = "tts_api_data"
        }
    }

    struct UsageData: Codable {
        var aggregationTimestamp: Int?
        var nRequests: Int?
        var operation: String?
        var snapshotId: String?
        var nContext: Int?
        var nContextTokensTotal: Int?
        var nGenerated: Int?
        var nGeneratedTokensTotal: Int?

        enum CodingKeys: String, CodingKey {
            case aggregationTimestamp = "aggregation_timestamp"
            case nRequests = "n_requests"
            case operation
            case snapshotId = "snapshot_id"
            case nContext = "n_context"
            case nContextTokensTotal = "n_context_tokens_total"
            case nGenerated = "n_generated"
            case nGeneratedTokensTotal = "n_generated_tokens_total"
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

        // Detect key type: admin keys start with "sk-admin-"
        let isAdminKey = apiKey.hasPrefix("sk-admin-")

        if isAdminKey {
            return try await fetchWithAdminKey(apiKey)
        } else {
            return try await fetchWithProjectKey(apiKey)
        }
    }

    private func fetchWithAdminKey(_ apiKey: String) async throws -> Provider {
        // Get costs for current month using organization costs endpoint
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

        var urlComponents = URLComponents(url: costsURL, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [
            URLQueryItem(name: "start_time", value: "\(Int(startOfMonth.timeIntervalSince1970))"),
            URLQueryItem(name: "end_time", value: "\(Int(now.timeIntervalSince1970))"),
            URLQueryItem(name: "bucket_width", value: "1d")
        ]

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return Provider(id: "openai", name: "OpenAI API", icon: "sparkles", items: [], status: .error("Invalid response"))
        }

        if httpResponse.statusCode == 401 {
            return Provider(id: "openai", name: "OpenAI API", icon: "sparkles", items: [], status: .error("Invalid key"))
        }

        if httpResponse.statusCode == 403 {
            return Provider(id: "openai", name: "OpenAI API", icon: "sparkles", items: [], status: .error("Need usage scope"))
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            // Rate limits and server errors are transient: throw so the caller keeps the
            // last-known reading instead of replacing it with an empty error row.
            if isTransientHTTPStatus(httpResponse.statusCode) {
                throw URLError(.init(rawValue: httpResponse.statusCode))
            }
            return Provider(id: "openai", name: "OpenAI API", icon: "sparkles", items: [], status: .error(httpErrorMessage(httpResponse.statusCode)))
        }

        let costs = try? JSONDecoder().decode(CostsResponse.self, from: data)

        // Sum up all costs for the month
        var totalCost: Double = 0
        if let buckets = costs?.data {
            for bucket in buckets {
                for result in (bucket.results ?? []) {
                    totalCost += result.amount?.doubleValue ?? 0
                }
            }
        }

        // Show spending as dollar amount (no percentage since we don't have budget from API)
        let items = [UsageItem(
            label: "Spend",
            current: 0,
            limit: 100,
            resetLabel: String(format: "$%.2f this month", totalCost)
        )]

        return Provider(id: "openai", name: "OpenAI API", icon: "sparkles", items: items, status: .loaded)
    }

    private func fetchWithProjectKey(_ apiKey: String) async throws -> Provider {
        // Get usage for today using v1/usage endpoint
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        var urlComponents = URLComponents(url: usageURL, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "date", value: today)]

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return Provider(id: "openai", name: "OpenAI API", icon: "sparkles", items: [], status: .error("Invalid response"))
        }

        if httpResponse.statusCode == 401 {
            return Provider(id: "openai", name: "OpenAI API", icon: "sparkles", items: [], status: .error("Invalid key"))
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            // Rate limits and server errors are transient: throw so the caller keeps the
            // last-known reading instead of replacing it with an empty error row.
            if isTransientHTTPStatus(httpResponse.statusCode) {
                throw URLError(.init(rawValue: httpResponse.statusCode))
            }
            return Provider(id: "openai", name: "OpenAI API", icon: "sparkles", items: [], status: .error(httpErrorMessage(httpResponse.statusCode)))
        }

        let usage = try? JSONDecoder().decode(UsageResponse.self, from: data)

        var totalRequests = 0
        var totalTokens = 0

        if let dataItems = usage?.data {
            for item in dataItems {
                totalRequests += item.nRequests ?? 0
                totalTokens += (item.nContextTokensTotal ?? 0) + (item.nGeneratedTokensTotal ?? 0)
            }
        }

        for item in (usage?.whisperApiData ?? []) { totalRequests += item.nRequests ?? 0 }
        for item in (usage?.dalleApiData ?? []) { totalRequests += item.nRequests ?? 0 }
        for item in (usage?.ttsApiData ?? []) { totalRequests += item.nRequests ?? 0 }

        var items: [UsageItem] = []

        if totalRequests > 0 || totalTokens > 0 {
            items.append(UsageItem(
                label: "Requests",
                current: Double(min(totalRequests, 1000)),
                limit: 1000,
                resetLabel: "\(totalRequests) today"
            ))

            let tokensK = Double(totalTokens) / 1000.0
            items.append(UsageItem(
                label: "Tokens",
                current: min(tokensK, 1000),
                limit: 1000,
                resetLabel: String(format: "%.1fK today", tokensK)
            ))
        }

        if items.isEmpty {
            items.append(UsageItem(label: "Today", current: 0, limit: 100, resetLabel: "No usage"))
        }

        return Provider(id: "openai", name: "OpenAI API", icon: "sparkles", items: items, status: .loaded)
    }
}
