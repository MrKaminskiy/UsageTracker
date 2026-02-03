import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLogin: Bool = false

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Interval", selection: Binding(
                    get: { appState.config.refreshIntervalMinutes },
                    set: { appState.updateRefreshInterval($0) }
                )) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("60 minutes").tag(60)
                }
                .pickerStyle(.segmented)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("Providers") {
                HStack {
                    Image(systemName: "brain")
                    Text("Claude")
                    Spacer()
                    Text("via Claude Code")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Image(systemName: "cursorarrow.rays")
                    Text("Cursor")
                    Spacer()
                    Text("via Cursor app")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Section("About") {
                HStack {
                    Text("UsageTracker")
                    Spacer()
                    Text("v1.0")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 280)
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
            print("Failed to set launch at login: \(error)")
        }
    }
}
