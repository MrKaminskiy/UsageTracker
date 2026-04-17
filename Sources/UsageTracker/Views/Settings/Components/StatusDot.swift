// Sources/UsageTracker/Views/Settings/Components/StatusDot.swift
import SwiftUI

/// Small colored dot indicating a provider's connection status.
/// Returns an empty view when status is `.disabled`.
struct StatusDot: View {
    let status: ConnectionStatus

    var body: some View {
        if let color = status.color {
            Circle()
                .fill(color)
                .frame(width: SettingsDesign.statusDotSize, height: SettingsDesign.statusDotSize)
                .accessibilityElement()
                .accessibilityLabel(status.voiceOverLabel)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        StatusDot(status: .connected)
        StatusDot(status: .idle)
        StatusDot(status: .failed)
        StatusDot(status: .disabled)
    }
    .padding()
}
