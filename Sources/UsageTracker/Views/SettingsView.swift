import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLogin: Bool = false

    // API Keys state
    @State private var elevenLabsKey: String = ""
    @State private var elevenLabsSaved: Bool = false
    @State private var stabilityKey: String = ""
    @State private var stabilitySaved: Bool = false
    @State private var runwayKey: String = ""
    @State private var runwaySaved: Bool = false
    @State private var openAIKey: String = ""
    @State private var openAISaved: Bool = false

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
                APIKeyInput(
                    icon: "waveform",
                    name: "ElevenLabs",
                    placeholder: "xi-api-key...",
                    hint: "elevenlabs.io/app/settings/api-keys",
                    key: $elevenLabsKey,
                    saved: $elevenLabsSaved,
                    onSave: { saveKey("elevenlabs", elevenLabsKey) }
                )

                APIKeyInput(
                    icon: "paintbrush",
                    name: "Stability AI",
                    placeholder: "sk-...",
                    hint: "platform.stability.ai/account/keys",
                    key: $stabilityKey,
                    saved: $stabilitySaved,
                    onSave: { saveKey("stability", stabilityKey) }
                )

                APIKeyInput(
                    icon: "film",
                    name: "Runway",
                    placeholder: "key_...",
                    hint: "dev.runwayml.com",
                    key: $runwayKey,
                    saved: $runwaySaved,
                    onSave: { saveKey("runway", runwayKey) }
                )

                APIKeyInput(
                    icon: "sparkles",
                    name: "OpenAI API",
                    placeholder: "sk-...",
                    hint: "platform.openai.com/api-keys",
                    key: $openAIKey,
                    saved: $openAISaved,
                    onSave: { saveKey("openai", openAIKey) }
                )
            }

            Section("Auto-Connected") {
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
        .frame(width: 400, height: 620)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loadAllKeys()
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

    private func loadAllKeys() {
        elevenLabsKey = loadKey("elevenlabs") ?? ""
        elevenLabsSaved = !elevenLabsKey.isEmpty

        stabilityKey = loadKey("stability") ?? ""
        stabilitySaved = !stabilityKey.isEmpty

        runwayKey = loadKey("runway") ?? ""
        runwaySaved = !runwayKey.isEmpty

        openAIKey = loadKey("openai") ?? ""
        openAISaved = !openAIKey.isEmpty
    }

    private func loadKey(_ name: String) -> String? {
        let path = configDir.appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: path),
              let config = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return config["api_key"]
    }

    private func saveKey(_ name: String, _ key: String) {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let path = configDir.appendingPathComponent("\(name).json")
        let config = ["api_key": key]

        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: path)

            // Update saved state
            switch name {
            case "elevenlabs": elevenLabsSaved = true
            case "stability": stabilitySaved = true
            case "runway": runwaySaved = true
            case "openai": openAISaved = true
            default: break
            }

            // Trigger refresh
            Task {
                await appState.refresh()
            }
        }
    }
}

struct APIKeyInput: View {
    let icon: String
    let name: String
    let placeholder: String
    let hint: String
    @Binding var key: String
    @Binding var saved: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(name)
                    .fontWeight(.medium)
            }

            HStack {
                SecureField(placeholder, text: $key)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: key) { _, _ in
                        saved = false
                    }

                Button(saved ? "✓" : "Save") {
                    onSave()
                }
                .disabled(key.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(saved ? .green : .blue)
                .frame(width: 50)
            }

            Text(hint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
