// Sources/UsageTracker/Views/Settings/Tabs/GeneralTab.swift
import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLogin: Bool = false

    private let refreshOptions: [Int] = [1, 2, 5, 10, 15, 30]

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
        }
    }
}
