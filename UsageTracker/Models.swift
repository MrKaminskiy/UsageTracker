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

    var color: Color {
        switch percentage {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }
}

enum ProviderStatus: Equatable {
    case loading
    case loaded
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
