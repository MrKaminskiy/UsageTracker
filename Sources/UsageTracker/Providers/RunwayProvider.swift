import Foundation

actor RunwayProvider {
    private let organizationURL = URL(string: "https://api.dev.runwayml.com/v1/organization")!
    private let settingsURL = URL(string: "https://dev.runwayml.com/")!

    private var apiKey: String? {
        let configPath = NSString(string: "~/.usagetracker/runway.json").expandingTildeInPath
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

    struct OrganizationResponse: Codable {
        var creditBalance: Double?
        var spendLimit: Double?

        enum CodingKeys: String, CodingKey {
            case creditBalance = "credit_balance"
            case spendLimit = "spend_limit"
        }
    }

    func fetchUsage() async throws -> Provider {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            return Provider(
                id: "runway",
                name: "Runway",
                icon: "film",
                items: [],
                status: .notConnected(url: settingsURL)
            )
        }

        var request = URLRequest(url: organizationURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return Provider(
                id: "runway",
                name: "Runway",
                icon: "film",
                items: [],
                status: .error("Invalid response")
            )
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            return Provider(
                id: "runway",
                name: "Runway",
                icon: "film",
                items: [],
                status: .error("Invalid API key")
            )
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            // Rate limits and server errors are transient: throw so the caller keeps the
            // last-known reading instead of replacing it with an empty error row.
            if isTransientHTTPStatus(httpResponse.statusCode) {
                throw URLError(.init(rawValue: httpResponse.statusCode))
            }
            return Provider(
                id: "runway",
                name: "Runway",
                icon: "film",
                items: [],
                status: .error(httpErrorMessage(httpResponse.statusCode))
            )
        }

        let org = try JSONDecoder().decode(OrganizationResponse.self, from: data)

        var items: [UsageItem] = []

        if let balance = org.creditBalance {
            if let limit = org.spendLimit, limit > 0 {
                // Calculate usage percentage if we have a spend limit
                let used = limit - balance
                let percentage = (used / limit) * 100
                items.append(UsageItem(
                    label: "Credits",
                    current: max(0, percentage),
                    limit: 100,
                    resetLabel: "\(Int(balance)) left"
                ))
            } else {
                // Just show remaining balance
                items.append(UsageItem(
                    label: "Credits",
                    current: 0,
                    limit: max(balance, 1),
                    resetLabel: "\(Int(balance)) left"
                ))
            }
        }

        return Provider(
            id: "runway",
            name: "Runway",
            icon: "film",
            items: items,
            status: items.isEmpty ? .error("No balance data") : .loaded
        )
    }
}
