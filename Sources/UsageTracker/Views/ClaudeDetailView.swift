import AppKit
import SwiftUI

enum ClaudeDetailFormat {
    /// "resets 4:40 PM" for today, "resets Sat 11 PM" otherwise.
    static func absoluteResetLabel(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "h:mm a"
        } else {
            let minute = calendar.component(.minute, from: date)
            formatter.dateFormat = minute == 0 ? "EEE h a" : "EEE h:mm a"
        }
        return "resets \(formatter.string(from: date))"
    }

    /// 123 → "123", 45600 → "46k", 1200000 → "1.2M"
    static func tokenCount(_ count: Int) -> String {
        switch count {
        case ..<1000:
            return "\(count)"
        case ..<999_500:
            return "\(Int((Double(count) / 1000).rounded()))k"
        default:
            let millions = Double(count) / 1_000_000
            let formatted = millions >= 10
                ? "\(Int(millions.rounded()))"
                : String(format: "%.1f", millions).replacingOccurrences(of: ".0", with: "")
            return "\(formatted)M"
        }
    }
}
