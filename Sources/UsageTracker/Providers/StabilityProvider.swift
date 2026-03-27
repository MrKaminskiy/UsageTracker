import Foundation

actor StabilityProvider {
    private let balanceURL = URL(string: "https://api.stability.ai/v1/user/balance")!
    private let settingsURL = URL(string: "https://platform.stability.ai/account/credits")!

    private var apiKey: String? {
        let configPath = NSString(string: "~/.usagetracker/stability.json").expandingTildeInPath
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

    struct BalanceResponse: Codable {
        var credits: Double?
    }

    func fetchUsage() async throws -> Provider {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            return Provider(
                id: "stability",
                name: "Stability AI",
                icon: "paintbrush",
                items: [],
                status: .notConnected(url: settingsURL)
            )
        }

        var request = URLRequest(url: balanceURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return Provider(
                id: "stability",
                name: "Stability AI",
                icon: "paintbrush",
                items: [],
                status: .error("Invalid response")
            )
        }

        if httpResponse.statusCode == 401 {
            return Provider(
                id: "stability",
                name: "Stability AI",
                icon: "paintbrush",
                items: [],
                status: .error("Invalid API key")
            )
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            return Provider(
                id: "stability",
                name: "Stability AI",
                icon: "paintbrush",
                items: [],
                status: .error(httpErrorMessage(httpResponse.statusCode))
            )
        }

        let balance = try JSONDecoder().decode(BalanceResponse.self, from: data)

        var items: [UsageItem] = []

        // Stability shows remaining credits, not percentage
        // Show as absolute value since there's no fixed limit
        if let credits = balance.credits {
            items.append(UsageItem(
                label: "Credits",
                current: 0, // No "used" concept - just balance
                limit: max(credits, 1), // Show remaining as the "limit"
                resetLabel: "\(String(format: "%.1f", credits)) left"
            ))
        }

        return Provider(
            id: "stability",
            name: "Stability AI",
            icon: "paintbrush",
            items: items,
            status: items.isEmpty ? .error("No balance data") : .loaded
        )
    }
}
