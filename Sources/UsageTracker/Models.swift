import SwiftUI

struct UsageItem: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let current: Double
    let limit: Double
    let resetLabel: String?

    var percentage: Double {
        guard limit > 0 else { return 0 }
        return (current / limit) * 100
    }

    var gradientColors: (start: Color, end: Color) {
        switch percentage {
        case 0..<50:
            return (Color(red: 0.204, green: 0.780, blue: 0.349),  // #34C759
                    Color(red: 0.188, green: 0.820, blue: 0.345))  // #30D158
        case 50..<80:
            return (Color(red: 1.0, green: 0.624, blue: 0.039),    // #FF9F0A
                    Color(red: 1.0, green: 0.702, blue: 0.251))    // #FFB340
        default:
            return (Color(red: 1.0, green: 0.231, blue: 0.188),    // #FF3B30
                    Color(red: 1.0, green: 0.412, blue: 0.380))    // #FF6961
        }
    }

    var color: Color {
        gradientColors.start
    }
}

enum ProviderStatus: Equatable {
    case loading
    case loaded
    case notConnected(url: URL)
    case error(String)
}

struct Provider: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    var items: [UsageItem]
    var status: ProviderStatus
    var isExpanded: Bool = true

    var maxPercentage: Double {
        items.map(\.percentage).max() ?? 0
    }

    var displayColor: Color {
        switch maxPercentage {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }
}

struct AppConfig: Codable {
    var refreshIntervalMinutes: Int = 15
    var launchAtLogin: Bool = false
}
