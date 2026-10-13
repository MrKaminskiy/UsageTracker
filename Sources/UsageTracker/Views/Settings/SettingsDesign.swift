// Sources/UsageTracker/Views/Settings/SettingsDesign.swift
import SwiftUI

/// Connection status for a provider, shown on its Settings page and in the sidebar.
enum ConnectionStatus: Equatable {
    case connected   // Loaded with data
    case idle        // Loading or no auth yet
    case failed      // Error fetching
    case disabled    // Toggled off

    static func from(providerStatus: ProviderStatus, enabled: Bool) -> ConnectionStatus {
        guard enabled else { return .disabled }
        switch providerStatus {
        case .loaded: return .connected
        case .loading: return .idle
        case .notConnected: return .idle
        case .error: return .failed
        }
    }

    var color: Color? {
        switch self {
        case .connected: return .green
        case .idle: return .gray.opacity(0.5)
        case .failed: return .red
        case .disabled: return nil
        }
    }

    var voiceOverLabel: String {
        switch self {
        case .connected: return "Status: connected"
        case .idle: return "Status: idle"
        case .failed: return "Status: failed"
        case .disabled: return "Status: disabled"
        }
    }
}

/// A page in the Settings sidebar.
enum SettingsPage: Hashable, Identifiable {
    case general
    case display
    case howItWorks
    case about
    case provider(String)

    static let appPages: [SettingsPage] = [.general, .display, .howItWorks, .about]

    var id: String { rawValue }

    /// Persisted in UserDefaults so the window reopens on the last page.
    var rawValue: String {
        switch self {
        case .general: return "general"
        case .display: return "display"
        case .howItWorks: return "help"
        case .about: return "about"
        case .provider(let id): return "provider.\(id)"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "general": self = .general
        case "display": self = .display
        case "help": self = .howItWorks
        case "about": self = .about
        default:
            guard rawValue.hasPrefix("provider.") else { return nil }
            self = .provider(String(rawValue.dropFirst("provider.".count)))
        }
    }

    var title: String {
        switch self {
        case .general: return "General"
        case .display: return "Display"
        case .howItWorks: return "How It Works"
        case .about: return "About"
        case .provider(let id): return ProviderCatalog.all[id]?.name ?? id
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .display: return "menubar.rectangle"
        case .howItWorks: return "questionmark"
        case .about: return "info"
        case .provider(let id): return ProviderCatalog.all[id]?.icon ?? "circle"
        }
    }

    /// Extra words the sidebar search matches, so "refresh" finds General.
    var keywords: [String] {
        switch self {
        case .general: return ["login", "launch", "refresh", "interval", "alert", "context", "notification", "onboarding", "welcome"]
        case .display: return ["menu bar", "popover", "pin", "hide", "credits", "cost", "estimate"]
        case .howItWorks: return ["help", "tips", "reorder", "api key"]
        case .about: return ["version", "update", "github", "issue", "license", "quit"]
        case .provider(let id):
            // "API Key" or "Browser Cookie", only for providers that take one.
            return ["limits", "usage"] + (ProviderCatalog.all[id]?.key.map { [$0.title] } ?? [])
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ([title] + keywords).contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// Rounded-square symbol tile, like the icons in System Settings and Raycast's sidebar.
struct IconTile: View {
    let symbol: String
    var tint: Color = Color(nsColor: .systemGray)
    var size: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                shape
                    .fill(tint)
                    .overlay(shape.fill(LinearGradient(
                        colors: [.white.opacity(0.22), .clear],
                        startPoint: .top, endPoint: .bottom)))
            )
            .overlay(shape.strokeBorder(Self.edge, lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    /// A dark edge on light backgrounds, a light one on dark: near-black tiles (Codex,
    /// ElevenLabs) otherwise dissolve into a dark sidebar.
    private static let edge = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.16)
            : NSColor.black.withAlphaComponent(0.08)
    })
}

/// The row every Settings page opens with: tile, title, one-line description, and an optional
/// trailing control. It stands in for the window title, which the unified toolbar hides.
struct SettingsPageHeader<Icon: View, Subtitle: View, Trailing: View>: View {
    let title: String
    let badge: String?
    let icon: Icon
    let subtitle: Subtitle
    let trailing: Trailing

    init(
        _ title: String,
        badge: String? = nil,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder subtitle: () -> Subtitle,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.badge = badge
        self.icon = icon()
        self.subtitle = subtitle()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(UsageLevel.warning.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(UsageLevel.warning.color.opacity(0.14)))
                    }
                }
                .accessibilityAddTraits(.isHeader)
                subtitle
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 4)
    }
}

/// Shared layout tokens for the Settings window and the grouped cards onboarding reuses.
enum SettingsDesign {
    static let windowDefaultWidth: CGFloat = 780
    static let windowDefaultHeight: CGFloat = 560
    /// Page header tile; the sidebar uses `IconTile`'s 22pt default.
    static let headerTileSize: CGFloat = 40
    static let windowMinWidth: CGFloat = 680
    static let windowMinHeight: CGFloat = 460

    static let cardCornerRadius: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 14
    static let hairlineColor = Color.primary.opacity(0.08)
    static let hairlineWidth: CGFloat = 0.5
}
