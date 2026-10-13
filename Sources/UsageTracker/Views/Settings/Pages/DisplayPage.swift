// Sources/UsageTracker/Views/Settings/Pages/DisplayPage.swift
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

struct DisplayPage: View {
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
        SettingsForm {
            Section("Menu Bar") {
                Picker(selection: pinnedSelection) {
                    Text("Highest usage").tag(PinnedSelection.auto)
                    ForEach(menuBarOptions(), id: \.self) { option in
                        Text("\(option.providerName) \(option.displayLabel)")
                            .tag(PinnedSelection.pinned(providerId: option.providerId, itemLabel: option.pinKey))
                    }
                } label: {
                    Text("Menu Bar Shows")
                    Text("You can also click a limit in the popover to pin it.")
                }
            }

            Section("Popover") {
                Toggle(isOn: Binding(
                    get: { appState.config.hideNotConnected },
                    set: { appState.updateHideNotConnected($0) }
                )) {
                    Text("Hide Not Connected")
                    Text("Skip providers with no API key or sign-in.")
                }

                Toggle(isOn: Binding(
                    get: { appState.config.shouldShowExtraUsageInPopover },
                    set: { appState.updateShowExtraUsageInPopover($0) }
                )) {
                    Text("Show Claude Extra Credits")
                    Text("When hidden, they stay visible in Claude details.")
                }

                Toggle(isOn: Binding(
                    get: { appState.config.showCostEstimate },
                    set: { appState.updateShowCostEstimate($0) }
                )) {
                    Text("Show API Cost Estimate")
                    Text("Rough estimate from Claude Code logs, not billing data.")
                }
            }
        }
    }

    private struct MenuBarOption: Hashable {
        let providerId: String
        let providerName: String
        let displayLabel: String
        let pinKey: String
    }

    private func menuBarOptions() -> [MenuBarOption] {
        appState.popoverProviders.flatMap { provider in
            provider.items.map { item in
                MenuBarOption(providerId: provider.id, providerName: provider.name, displayLabel: item.label, pinKey: item.stablePinKey)
            }
        }
    }
}
