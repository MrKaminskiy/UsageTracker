import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLogin: Bool = false
    @State private var elevenLabsKey: String = ""
    @State private var elevenLabsKeySaved: Bool = false

    private let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".usagetracker")

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

            Section("API Keys") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "waveform")
                        Text("ElevenLabs")
                    }

                    HStack {
                        SecureField("xi-api-key...", text: $elevenLabsKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: elevenLabsKey) { _, _ in
                                elevenLabsKeySaved = false
                            }

                        Button(elevenLabsKeySaved ? "Saved ✓" : "Save") {
                            saveElevenLabsKey()
                        }
                        .disabled(elevenLabsKey.isEmpty)
                        .buttonStyle(.borderedProminent)
                        .tint(elevenLabsKeySaved ? .green : .blue)
                    }

                    Text("Get your key from elevenlabs.io/app/settings/api-keys")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
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

                HStack {
                    Image(systemName: "terminal.fill")
                    Text("Codex")
                    Spacer()
                    Text("via codex login")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Image(systemName: "waveform")
                    Text("ElevenLabs")
                    Spacer()
                    Text("via API key")
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
        .frame(width: 380, height: 480)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loadElevenLabsKey()
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

    private func loadElevenLabsKey() {
        let path = configDir.appendingPathComponent("elevenlabs.json")
        guard let data = try? Data(contentsOf: path),
              let config = try? JSONDecoder().decode([String: String].self, from: data),
              let key = config["api_key"] else {
            return
        }
        // Show masked version
        if !key.isEmpty {
            elevenLabsKey = key
            elevenLabsKeySaved = true
        }
    }

    private func saveElevenLabsKey() {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let path = configDir.appendingPathComponent("elevenlabs.json")
        let config = ["api_key": elevenLabsKey]

        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: path)
            elevenLabsKeySaved = true

            // Trigger refresh to pick up new key
            Task {
                await appState.refresh()
            }
        }
    }
}
