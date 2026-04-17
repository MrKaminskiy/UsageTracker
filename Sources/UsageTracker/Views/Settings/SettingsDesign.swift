// Sources/UsageTracker/Views/Settings/SettingsDesign.swift
import SwiftUI

/// Connection status for a provider, used to drive the row status dot.
enum ConnectionStatus: Equatable {
    case connected   // Loaded with data
    case idle        // Loading or no auth yet
    case failed      // Error fetching
    case disabled    // Toggled off — dot hidden

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

/// The five tabs in the Settings window, in display order.
enum SettingsTabKind: String, CaseIterable, Identifiable {
    case general
    case providers
    case display
    case help
    case about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .providers: return "Providers"
        case .display: return "Display"
        case .help: return "Help"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .providers: return "bolt.horizontal.circle"
        case .display: return "eye"
        case .help: return "questionmark.circle"
        case .about: return "info.circle"
        }
    }

    /// Keyboard shortcut character: "1"..."5".
    var shortcut: Character {
        switch self {
        case .general: return "1"
        case .providers: return "2"
        case .display: return "3"
        case .help: return "4"
        case .about: return "5"
        }
    }
}

/// Shared layout/style tokens for the Settings window.
enum SettingsDesign {
    static let windowDefaultWidth: CGFloat = 560
    static let windowDefaultHeight: CGFloat = 600
    static let windowMinWidth: CGFloat = 480
    static let windowMinHeight: CGFloat = 540

    static let cardCornerRadius: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 14
    static let hairlineColor = Color.primary.opacity(0.08)
    static let hairlineWidth: CGFloat = 0.5

    static let tabIconSize: CGFloat = 32
    static let tabCornerRadius: CGFloat = 6

    static let statusDotSize: CGFloat = 6
}
