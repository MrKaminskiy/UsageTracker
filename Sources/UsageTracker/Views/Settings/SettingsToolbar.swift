// Sources/UsageTracker/Views/Settings/SettingsToolbar.swift
import SwiftUI

/// Top tab bar with five icon buttons. Active tab gets accent fill.
struct SettingsToolbar: View {
    @Binding var selected: SettingsTabKind

    var body: some View {
        VStack(spacing: 8) {
            Text("Preferences")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, 6)

            HStack(spacing: 16) {
                ForEach(SettingsTabKind.allCases) { tab in
                    tabButton(tab)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SettingsDesign.hairlineColor)
                .frame(height: SettingsDesign.hairlineWidth)
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: SettingsTabKind) -> some View {
        let isActive = (selected == tab)
        Button {
            selected = tab
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: SettingsDesign.tabCornerRadius)
                        .fill(isActive ? Color.accentColor : Color.clear)
                        .frame(width: SettingsDesign.tabIconSize, height: SettingsDesign.tabIconSize)
                    Image(systemName: tab.icon)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(isActive ? .white : .secondary)
                }
                Text(tab.label)
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                    .fontWeight(isActive ? .medium : .regular)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(tab.shortcut, modifiers: .command)
        .accessibilityLabel("\(tab.label) settings")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}
