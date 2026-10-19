import Foundation

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

    /// This row once its window has reset since the reading was taken: nothing used yet as far
    /// as we know, labeled so. Keeps `resetsAt`, so carrying it again changes nothing.
    func markedReset() -> UsageItem {
        UsageItem(label: label, current: 0, limit: limit, resetLabel: "reset",
                  resetsAt: resetsAt, pinKey: pinKey, kind: kind)
    }
}

/// Every Claude account card: the default `claude`, plus `claude-<hash>` for each other Claude
/// Code config folder (see `ClaudeAccountDiscovery`).
func isClaudeProviderID(_ id: String) -> Bool {
    id == "claude" || id.hasPrefix("claude-")
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

/// An array from a usage response whose elements the server defines and may extend.
/// Elements that are null or the wrong shape are dropped, and a value that isn't an array
/// at all reads as empty, so one odd row can't fail the whole response decode.
struct LossyArray<Element: Codable>: Codable {
    var elements: [Element]

    private struct Slot: Codable {
        var value: Element?
        init(from decoder: Decoder) throws { value = try? Element(from: decoder) }
        func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
    }

    init(_ elements: [Element]) { self.elements = elements }

    init(from decoder: Decoder) throws {
        let slots = try? decoder.singleValueContainer().decode([Slot].self)
        elements = slots?.compactMap(\.value) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(elements)
    }
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
    var name: String
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
    var productShares: [UsageShare] = []     // this week's usage split by product (Claude only)
    var accountLabel: String? = nil          // the account's email, or its config folder name (Claude only)
    var accountUuid: String? = nil           // which account the reading belongs to (Claude only)

    var maxPercentage: Double {
        items.map(\.percentage).max() ?? 0
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
    /// Names the user gave Claude accounts in Settings, by provider ID. Optional so older
    /// config files decode.
    var claudeAccountNames: [String: String]? = nil
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
