import SwiftUI

struct UsageItem: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let current: Double
    let limit: Double
    let resetLabel: String?
    var resetsAt: Date? = nil
    var valueText: String? = nil     // overrides the "NN%" value display (e.g. "$12 of $50")

    var percentage: Double {
        guard limit > 0 else { return 0 }
        return (current / limit) * 100
    }

    var gradientColors: (start: Color, end: Color) {
        switch percentage {
        case 0..<60:
            return (Color(red: 0.204, green: 0.780, blue: 0.349),  // #34C759
                    Color(red: 0.188, green: 0.820, blue: 0.345))  // #30D158
        case 60..<85:
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

/// Maps HTTP status codes to user-friendly error messages.
func httpErrorMessage(_ statusCode: Int) -> String {
    switch statusCode {
    case 401: return "Invalid API key"
    case 403: return "Access denied"
    case 429: return "Rate limited"
    case 500...599: return "Service unavailable"
    default: return "Error (\(statusCode))"
    }
}

struct Provider: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    var items: [UsageItem]
    var status: ProviderStatus
    var isExpanded: Bool = true
    var boostStatus: Claude2xStatus? = nil  // nil = no promo configured
    var costEstimate: Double? = nil          // API cost estimate in dollars
    var planLabel: String? = nil             // e.g. "Max" from subscriptionType (Claude only)
    var insights: ClaudeInsights? = nil      // local transcript insights (Claude only)

    var maxPercentage: Double {
        items.map(\.percentage).max() ?? 0
    }

    var displayColor: Color {
        switch maxPercentage {
        case 0..<60: return .green
        case 60..<85: return .yellow
        default: return .red
        }
    }
}

struct PinnedItem: Codable, Equatable {
    var providerId: String
    var itemLabel: String
}

struct AppConfig: Codable {
    var refreshIntervalMinutes: Int = 5
    var launchAtLogin: Bool = false
    var hideNotConnected: Bool = true
    var hasCompletedOnboarding: Bool = false
    var showCostEstimate: Bool = false
    var pinnedItem: PinnedItem? = nil
    var enabledProviders: [String: Bool] = [
        "claude": true,
        "cursor": true,
        "codex": true,
        "elevenlabs": true,
        "stability": false,   // untested — hidden by default
        "runway": false,      // untested — hidden by default
        "openai": true,
        "openrouter": true
    ]
    var providerOrder: [String] = [
        "claude",
        "cursor",
        "codex",
        "elevenlabs",
        "stability",
        "runway",
        "openai",
        "openrouter"
    ]

    func isProviderEnabled(_ id: String) -> Bool {
        enabledProviders[id] ?? true
    }
}
