// Sources/UsageTracker/Views/Settings/Tabs/DisplayTab.swift
import SwiftUI

/// Tag type for the menu-bar pinned-item Picker.
enum PinnedSelection: Hashable {
    case auto
    case pinned(providerId: String, itemLabel: String)

    init(from pinnedItem: PinnedItem?) {
        if let pin = pinnedItem {
            self = .pinned(providerId: pin.providerId, itemLabel: pin.itemLabel)
        } else {
            self = .auto
        }
    }

    var asPinnedItem: PinnedItem? {
        switch self {
        case .auto: return nil
        case .pinned(let providerId, let itemLabel):
            return PinnedItem(providerId: providerId, itemLabel: itemLabel)
        }
    }
}

struct DisplayTab: View {
    @ObservedObject var appState: AppState

    private var pinnedSelection: Binding<PinnedSelection> {
        Binding(
            get: { PinnedSelection(from: appState.config.pinnedItem) },
            set: { newValue in
                appState.config.pinnedItem = newValue.asPinnedItem
                appState.saveConfig()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCard {
                    HStack {
                        Text("Hide not connected")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { appState.config.hideNotConnected },
                            set: { appState.updateHideNotConnected($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .settingsRowPadding()

                    SettingsCardDivider()

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show API cost estimate")
                            Text("Rough estimate based on Claude Code conversation logs. Not actual billing data — may differ significantly from real costs.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { appState.config.showCostEstimate },
                            set: { appState.updateShowCostEstimate($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .settingsRowPadding()
                }

                SettingsCard {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Menu bar shows")
                            Text("Which usage item appears in the menu bar.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Picker("", selection: pinnedSelection) {
                            Text("Auto (highest %)").tag(PinnedSelection.auto)
                            ForEach(menuBarOptions(), id: \.self) { option in
                                Text("\(option.providerName) · \(option.itemLabel)")
                                    .tag(PinnedSelection.pinned(providerId: option.providerId, itemLabel: option.itemLabel))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220)
                    }
                    .settingsRowPadding()
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    private struct MenuBarOption: Hashable {
        let providerId: String
        let providerName: String
        let itemLabel: String
    }

    private func menuBarOptions() -> [MenuBarOption] {
        appState.visibleProviders.flatMap { provider in
            provider.items.map { item in
                MenuBarOption(providerId: provider.id, providerName: provider.name, itemLabel: item.label)
            }
        }
    }
}
