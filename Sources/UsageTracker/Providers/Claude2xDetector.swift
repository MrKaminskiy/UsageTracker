import Foundation

struct Claude2xConfig: Codable, Sendable {
    let promoStart: Date
    let promoEnd: Date
    let peakHoursET: PeakHours

    struct PeakHours: Codable, Sendable {
        let start: Int  // hour in ET (0-23)
        let end: Int    // hour in ET (0-23)
    }
}

struct Claude2xDetector: Sendable {
    let config: Claude2xConfig?

    private static let etTimeZone = TimeZone(identifier: "America/New_York")!

    /// Returns nil if no promo configured or outside promo window.
    /// Returns true if 2x is active, false if within peak hours.
    func check(at date: Date = Date()) -> Bool? {
        guard let config = config else { return nil }

        // Outside promo window
        guard date >= config.promoStart && date <= config.promoEnd else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.etTimeZone

        let weekday = calendar.component(.weekday, from: date)
        // Sunday = 1, Saturday = 7
        let isWeekend = weekday == 1 || weekday == 7
        if isWeekend { return true }

        let hour = calendar.component(.hour, from: date)
        // Peak hours: [start, end) — no boost during peak
        if hour >= config.peakHoursET.start && hour < config.peakHoursET.end {
            return false
        }

        return true
    }

    /// Load config from ~/.usagetracker/claude_2x.json.
    /// Returns a detector with nil config if file doesn't exist or is malformed.
    static func loadFromDisk() -> Claude2xDetector {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker/claude_2x.json")

        guard let data = try? Data(contentsOf: url) else {
            return Claude2xDetector(config: nil)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let config = try? decoder.decode(Claude2xConfig.self, from: data) else {
            return Claude2xDetector(config: nil)
        }

        return Claude2xDetector(config: config)
    }
}
