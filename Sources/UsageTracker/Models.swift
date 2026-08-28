import SwiftUI

enum UsageItemKind: Equatable, Hashable {
    case standard
    case extraUsage
}

struct UsageItem: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let current: Double
    let limit: Double
    let resetLabel: String?
    var resetsAt: Date? = nil
    /// Stable identity for pin persistence, independent of the display label (which can vary, e.g. Codex's window duration labels). Falls back to `label` when a provider doesn't set one.
    var pinKey: String? = nil
    var kind: UsageItemKind = .standard

    var stablePinKey: String { pinKey ?? label }

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

/// Renders a reset deadline as the short countdown shown at the end of a usage row
/// ("45m", "4h 47m", "6d"). Returns nil once the deadline has passed, so a window that has
/// already reset shows no countdown at all rather than a negative one.
func relativeResetLabel(_ date: Date?, now: Date = Date()) -> String? {
    guard let date = date else { return nil }
    let diff = date.timeIntervalSince(now)
    if diff <= 0 { return nil }
    let hours = Int(diff / 3600)
    let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
    if hours > 24 {
        return "\(hours / 24)d"
    } else if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else {
        return "\(minutes)m"
    }
}

/// Whether an HTTP status means "try again later" rather than "this is broken".
///
/// A provider that hits one of these should throw, not return `.error`: `refresh()` keeps the
/// last-known reading for a provider that threw, and replaces it for one that returned a
/// status. Reporting a rate limit as `.error` would blank a perfectly good reading — including
/// the one just restored from `UsageCache` at launch — one refresh after the app opens.
func isTransientHTTPStatus(_ statusCode: Int) -> Bool {
    statusCode == 429 || statusCode >= 500
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
    /// When this reading came back from its source. Carried on providers restored from
    /// `UsageCache` and stamped on every fresh fetch, so a reading kept across failed
    /// refreshes can still be retired once it is too old to stand behind.
    var fetchedAt: Date? = nil
    var codexInsights: CodexInsights? = nil  // local CLI activity and account details (Codex only)

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
    // Optional for backward-compatible decoding of config files written by older builds.
    var showExtraUsageInPopover: Bool? = nil  // nil → on by default
    // Alert when the active Claude chat's context grows large. Optionals so a config.json
    // written by an older build (which lacks these keys) still decodes instead of resetting.
    var contextAlertEnabled: Bool? = nil        // nil → on by default
    var contextAlertThresholdK: Int? = nil      // threshold in thousands of tokens; nil → 150
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

    var isContextAlertEnabled: Bool { contextAlertEnabled ?? true }
    var shouldShowExtraUsageInPopover: Bool { showExtraUsageInPopover ?? true }
    /// Effective threshold in tokens (default 150k).
    var contextAlertThreshold: Int { (contextAlertThresholdK ?? 150) * 1000 }
}
