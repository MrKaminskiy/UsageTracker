import SwiftUI

/// Rounded grouped container for settings rows. Children are stacked
/// vertically with hairline dividers between them.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(SettingsDesign.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesign.cardCornerRadius)
                .stroke(SettingsDesign.hairlineColor, lineWidth: SettingsDesign.hairlineWidth)
        )
    }
}

/// Hairline divider used between rows inside a `SettingsCard`.
struct SettingsCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsDesign.hairlineColor)
            .frame(height: SettingsDesign.hairlineWidth)
    }
}

/// Standard horizontal/vertical padding for a single row inside a `SettingsCard`.
struct SettingsRowPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, SettingsDesign.rowVerticalPadding)
            .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
    }
}

extension View {
    func settingsRowPadding() -> some View {
        modifier(SettingsRowPadding())
    }
}
