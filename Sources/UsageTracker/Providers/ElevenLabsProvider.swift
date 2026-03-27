import Foundation

actor ElevenLabsProvider {
    private let subscriptionURL = URL(string: "https://api.elevenlabs.io/v1/user/subscription")!
    private let settingsURL = URL(string: "https://elevenlabs.io/app/subscription")!

    private var apiKey: String? {
        // Read from config file
        let configPath = NSString(string: "~/.usagetracker/elevenlabs.json").expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: configPath),
              let config = try? JSONDecoder().decode(ElevenLabsConfig.self, from: data) else {
            return nil
        }
        return config.apiKey
    }

    struct ElevenLabsConfig: Codable {
        var apiKey: String?

        enum CodingKeys: String, CodingKey {
            case apiKey = "api_key"
        }
    }

    struct SubscriptionResponse: Codable {
        var characterCount: Int?
        var characterLimit: Int?
        var nextCharacterCountResetUnix: Double?

        enum CodingKeys: String, CodingKey {
            case characterCount = "character_count"
            case characterLimit = "character_limit"
            case nextCharacterCountResetUnix = "next_character_count_reset_unix"
        }
    }

    func fetchUsage() async throws -> Provider {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            return Provider(
                id: "elevenlabs",
                name: "ElevenLabs",
                icon: "waveform",
                items: [],
                status: .notConnected(url: settingsURL)
            )
        }

        var request = URLRequest(url: subscriptionURL)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return Provider(
                id: "elevenlabs",
                name: "ElevenLabs",
                icon: "waveform",
                items: [],
                status: .error("Invalid response")
            )
        }

        if httpResponse.statusCode == 401 {
            return Provider(
                id: "elevenlabs",
                name: "ElevenLabs",
                icon: "waveform",
                items: [],
                status: .error("Invalid API key")
            )
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            return Provider(
                id: "elevenlabs",
                name: "ElevenLabs",
                icon: "waveform",
                items: [],
                status: .error(httpErrorMessage(httpResponse.statusCode))
            )
        }

        let subscription = try JSONDecoder().decode(SubscriptionResponse.self, from: data)

        var items: [UsageItem] = []

        if let used = subscription.characterCount,
           let limit = subscription.characterLimit,
           limit > 0 {
            let percentage = (Double(used) / Double(limit)) * 100
            let resetLabel = formatResetTime(subscription.nextCharacterCountResetUnix)
            items.append(UsageItem(
                label: "Characters",
                current: percentage,
                limit: 100,
                resetLabel: resetLabel
            ))
        }

        return Provider(
            id: "elevenlabs",
            name: "ElevenLabs",
            icon: "waveform",
            items: items,
            status: items.isEmpty ? .error("No usage data") : .loaded
        )
    }

    private func formatResetTime(_ timestamp: Double?) -> String? {
        guard let timestamp = timestamp else { return nil }

        let resetDate = Date(timeIntervalSince1970: timestamp)
        let diff = resetDate.timeIntervalSinceNow
        if diff <= 0 { return nil }

        let days = Int(diff / 86400)
        if days > 0 {
            return "\(days)d"
        }

        let hours = Int(diff / 3600)
        let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
