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

            Section("Plugins") {
                HStack {
                    Text("~/.usagetracker/plugins/")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Open") {
                        openPluginsFolder()
                    }
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
        .frame(width: 350, height: 250)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func openPluginsFolder() {
        let pluginsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker/plugins")

        try? FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(pluginsDir)
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
