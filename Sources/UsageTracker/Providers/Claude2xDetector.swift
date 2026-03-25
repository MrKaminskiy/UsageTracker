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

struct Claude2xStatus: Equatable, Sendable {
    let isActive: Bool
    let nextTransitionLabel: String?  // e.g. "in 2h 30m" or "ends in 5h"
}

struct Claude2xDetector: Sendable {
    let config: Claude2xConfig?

    private static let etTimeZone = TimeZone(identifier: "America/New_York")!

    /// Returns nil if no promo configured or outside promo window.
    func status(at date: Date = Date()) -> Claude2xStatus? {
        guard let config = config else { return nil }
        guard date >= config.promoStart && date <= config.promoEnd else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.etTimeZone

        let weekday = calendar.component(.weekday, from: date)
        let isWeekend = weekday == 1 || weekday == 7

        if isWeekend {
            // 2x all weekend — next transition is Monday peak start
            let nextMonday = nextWeekday(2, hour: config.peakHoursET.start, after: date, calendar: calendar)
            let label = formatDuration(from: date, to: min(nextMonday, config.promoEnd))
            return Claude2xStatus(isActive: true, nextTransitionLabel: label.map { "ends \($0)" })
        }

        let hour = calendar.component(.hour, from: date)

        if hour >= config.peakHoursET.start && hour < config.peakHoursET.end {
            // During peak — 2x starts at peakEnd today
            let peakEnd = calendar.date(bySettingHour: config.peakHoursET.end, minute: 0, second: 0, of: date)!
            let label = formatDuration(from: date, to: peakEnd)
            return Claude2xStatus(isActive: false, nextTransitionLabel: label.map { "in \($0)" })
        }

        // Off-peak weekday — 2x active
        if hour < config.peakHoursET.start {
            // Before peak — ends at peak start today
            let peakStart = calendar.date(bySettingHour: config.peakHoursET.start, minute: 0, second: 0, of: date)!
            let label = formatDuration(from: date, to: peakStart)
            return Claude2xStatus(isActive: true, nextTransitionLabel: label.map { "ends \($0)" })
        } else {
            // After peak — ends at next peak start (or weekend = Friday after peak lasts until Monday)
            let isFriday = weekday == 6
            let nextEnd: Date
            if isFriday {
                nextEnd = nextWeekday(2, hour: config.peakHoursET.start, after: date, calendar: calendar)
            } else {
                // Tomorrow peak start
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: date)!
                nextEnd = calendar.date(bySettingHour: config.peakHoursET.start, minute: 0, second: 0, of: tomorrow)!
            }
            let label = formatDuration(from: date, to: min(nextEnd, config.promoEnd))
            return Claude2xStatus(isActive: true, nextTransitionLabel: label.map { "ends \($0)" })
        }
    }

    /// Legacy convenience — returns Bool? like before
    func check(at date: Date = Date()) -> Bool? {
        status(at: date)?.isActive
    }

    private func nextWeekday(_ targetWeekday: Int, hour: Int, after date: Date, calendar: Calendar) -> Date {
        var d = date
        // Advance to the next occurrence of targetWeekday
        repeat {
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        } while calendar.component(.weekday, from: d) != targetWeekday
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: d)!
    }

    private func formatDuration(from: Date, to: Date) -> String? {
        let diff = to.timeIntervalSince(from)
        guard diff > 0 else { return nil }

        let hours = Int(diff / 3600)
        let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 24 {
            return "\(hours / 24)d \(hours % 24)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
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
