// Sources/UsageTracker/Views/Settings/Tabs/GeneralTab.swift
import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLogin: Bool = false

    private let refreshOptions: [Int] = [1, 2, 5, 10, 15, 30]
    private let contextThresholdOptions: [Int] = [100, 120, 150, 180, 200, 250]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCard {
                    HStack {
                        Text("Launch at login")
                        Spacer()
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: launchAtLogin) { _, newValue in
                                setLaunchAtLogin(newValue)
                            }
                    }
                    .settingsRowPadding()

                    SettingsCardDivider()

                    HStack {
                        Text("Refresh interval")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { appState.config.refreshIntervalMinutes },
                            set: { appState.updateRefreshInterval($0) }
                        )) {
                            ForEach(refreshOptions, id: \.self) { minutes in
                                Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }
                    .settingsRowPadding()
                }

                SettingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Large-context alert")
                            Text("Notify when the active Claude chat's context grows large.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { appState.config.isContextAlertEnabled },
                            set: { appState.updateContextAlertEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .settingsRowPadding()

                    if appState.config.isContextAlertEnabled {
                        SettingsCardDivider()

                        HStack {
                            Text("Alert threshold")
                            Spacer()
                            Picker("", selection: Binding(
                                get: { appState.config.contextAlertThresholdK ?? 150 },
                                set: { appState.updateContextAlertThresholdK($0) }
                            )) {
                                ForEach(contextThresholdOptions, id: \.self) { k in
                                    Text("\(k)k tokens").tag(k)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 130)
                        }
                        .settingsRowPadding()
                    }
                }

                SettingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Onboarding")
                            Text("Show the welcome screen again.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("Show Again") {
                            NotificationCenter.default.post(name: .showOnboarding, object: nil)
                        }
                        .controlSize(.small)
                    }
                    .settingsRowPadding()
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
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
