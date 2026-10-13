// Sources/UsageTracker/Views/Settings/Pages/GeneralPage.swift
import SwiftUI
import ServiceManagement

struct GeneralPage: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLogin: Bool = false

    private let refreshOptions: [Int] = [1, 2, 5, 10, 15, 30]
    private let contextThresholdOptions: [Int] = [100, 120, 150, 180, 200, 250]

    var body: some View {
        SettingsForm {
            Section {
                SettingsPageHeader("General") {
                    IconTile(symbol: SettingsPage.general.icon, size: SettingsDesign.headerTileSize)
                } subtitle: {
                    Text("Startup, refresh, and alerts.")
                }
            }

            Section {
                // Binding setter, not onChange: onAppear's status read must not call register().
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))

                Picker(selection: Binding(
                    get: { appState.config.refreshIntervalMinutes },
                    set: { appState.updateRefreshInterval($0) }
                )) {
                    ForEach(refreshOptions, id: \.self) { minutes in
                        Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                    }
                } label: {
                    Text("Refresh Interval")
                    Text("Claude rate-limits frequent checks. 5 minutes or more is safest.")
                }
            }

            Section("Notifications") {
                Toggle(isOn: Binding(
                    get: { appState.config.isContextAlertEnabled },
                    set: { appState.updateContextAlertEnabled($0) }
                )) {
                    Text("Large-Context Alert")
                    Text("Notify when the active Claude chat's context grows large.")
                }

                if appState.config.isContextAlertEnabled {
                    Picker("Alert Threshold", selection: Binding(
                        get: { appState.config.contextAlertThresholdK ?? 150 },
                        set: { appState.updateContextAlertThresholdK($0) }
                    )) {
                        ForEach(contextThresholdOptions, id: \.self) { k in
                            Text("\(k)k tokens").tag(k)
                        }
                    }
                }
            }

            Section {
                LabeledContent {
                    Button("Show Again") {
                        NotificationCenter.default.post(name: .showOnboarding, object: nil)
                    }
                } label: {
                    Text("Welcome Screen")
                    Text("The introduction shown on first launch.")
                }
            }
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.error("Failed to set launch at login: \(error)")
            // Revert the toggle so its visual state matches the actual OS state
            DispatchQueue.main.async {
                launchAtLogin = !enabled
            }
        }
    }
}
