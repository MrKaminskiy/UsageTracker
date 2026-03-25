import Testing
import Foundation
@testable import UsageTracker

@Suite("Claude2xDetector Tests")
struct Claude2xDetectorTests {

    // Helper: create a config with a promo window around a given date
    private func configAround(_ date: Date, peakStart: Int = 8, peakEnd: Int = 14) -> Claude2xConfig {
        Claude2xConfig(
            promoStart: date.addingTimeInterval(-86400 * 3),
            promoEnd: date.addingTimeInterval(86400 * 3),
            peakHoursET: Claude2xConfig.PeakHours(start: peakStart, end: peakEnd)
        )
    }

    private func dateET(year: Int = 2026, month: Int = 3, day: Int, hour: Int, minute: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test("Returns nil when no config provided")
    func nilWhenNoConfig() {
        let detector = Claude2xDetector(config: nil)
        #expect(detector.check(at: Date()) == nil)
    }

    @Test("Returns nil when date is before promo window")
    func nilBeforePromo() {
        let promoStart = dateET(day: 20, hour: 0)
        let config = Claude2xConfig(
            promoStart: promoStart,
            promoEnd: promoStart.addingTimeInterval(86400 * 7),
            peakHoursET: .init(start: 8, end: 14)
        )
        let detector = Claude2xDetector(config: config)
        let beforePromo = promoStart.addingTimeInterval(-86400)
        #expect(detector.check(at: beforePromo) == nil)
    }

    @Test("Returns nil when date is after promo window")
    func nilAfterPromo() {
        let promoEnd = dateET(day: 20, hour: 23)
        let config = Claude2xConfig(
            promoStart: promoEnd.addingTimeInterval(-86400 * 7),
            promoEnd: promoEnd,
            peakHoursET: .init(start: 8, end: 14)
        )
        let detector = Claude2xDetector(config: config)
        let afterPromo = promoEnd.addingTimeInterval(86400)
        #expect(detector.check(at: afterPromo) == nil)
    }

    @Test("Weekend during promo is always 2x")
    func weekendAlways2x() {
        // March 22, 2026 is a Sunday
        let sunday10am = dateET(day: 22, hour: 10)
        let detector = Claude2xDetector(config: configAround(sunday10am))
        #expect(detector.check(at: sunday10am) == true)
    }

    @Test("Weekend during peak hours still 2x")
    func weekendPeakStill2x() {
        // March 21, 2026 is a Saturday
        let saturday11am = dateET(day: 21, hour: 11)
        let detector = Claude2xDetector(config: configAround(saturday11am))
        #expect(detector.check(at: saturday11am) == true)
    }

    @Test("Weekday during peak hours returns false")
    func weekdayPeakFalse() {
        // March 23, 2026 is a Monday
        let monday10am = dateET(day: 23, hour: 10)
        let detector = Claude2xDetector(config: configAround(monday10am))
        #expect(detector.check(at: monday10am) == false)
    }

    @Test("Weekday before peak returns true")
    func weekdayBeforePeakTrue() {
        // March 23, 2026 is a Monday
        let monday6am = dateET(day: 23, hour: 6)
        let detector = Claude2xDetector(config: configAround(monday6am))
        #expect(detector.check(at: monday6am) == true)
    }

    @Test("Weekday after peak returns true")
    func weekdayAfterPeakTrue() {
        // March 23, 2026 is a Monday
        let monday15 = dateET(day: 23, hour: 15)
        let detector = Claude2xDetector(config: configAround(monday15))
        #expect(detector.check(at: monday15) == true)
    }

    @Test("Weekday at exactly peak start returns false")
    func weekdayExactPeakStart() {
        let monday8am = dateET(day: 23, hour: 8)
        let detector = Claude2xDetector(config: configAround(monday8am))
        #expect(detector.check(at: monday8am) == false)
    }

    @Test("Weekday at exactly peak end returns true")
    func weekdayExactPeakEnd() {
        let monday14 = dateET(day: 23, hour: 14)
        let detector = Claude2xDetector(config: configAround(monday14))
        #expect(detector.check(at: monday14) == true)
    }

    // MARK: - Status with timing tests

    @Test("Status during peak shows 'in' label")
    func statusDuringPeak() {
        // Monday 10am ET, peak is 8-14 → 2x starts at 14:00, so "in 4h 0m"
        let monday10am = dateET(day: 23, hour: 10)
        let detector = Claude2xDetector(config: configAround(monday10am))
        let status = detector.status(at: monday10am)
        #expect(status?.isActive == false)
        #expect(status?.nextTransitionLabel?.starts(with: "in ") == true)
    }

    @Test("Status after peak shows 'ends' label")
    func statusAfterPeak() {
        // Monday 15:00 ET, off-peak → active, ends at next peak start
        let monday15 = dateET(day: 23, hour: 15)
        let detector = Claude2xDetector(config: configAround(monday15))
        let status = detector.status(at: monday15)
        #expect(status?.isActive == true)
        #expect(status?.nextTransitionLabel?.starts(with: "ends ") == true)
    }

    @Test("Status on weekend shows 'ends' label")
    func statusWeekend() {
        let sunday10am = dateET(day: 22, hour: 10)
        let detector = Claude2xDetector(config: configAround(sunday10am))
        let status = detector.status(at: sunday10am)
        #expect(status?.isActive == true)
        #expect(status?.nextTransitionLabel?.starts(with: "ends ") == true)
    }

    @Test("Status nil when no config")
    func statusNilNoConfig() {
        let detector = Claude2xDetector(config: nil)
        #expect(detector.status(at: Date()) == nil)
    }
}
