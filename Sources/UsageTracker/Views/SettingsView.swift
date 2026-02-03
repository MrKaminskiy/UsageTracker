import SwiftUI
import ServiceManagement
import AppKit

/// Settings screen for app configuration and provider access.
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

    /// Provider list with optional API key configuration.
    private var providerSettings: [ProviderSettingsItem] {
        [
            ProviderSettingsItem(
                id: "claude",
                icon: "brain",
                name: "Claude",
                hint: "via Claude Code",
                keyConfig: nil
            ),
            ProviderSettingsItem(
                id: "cursor",
                icon: "cursorarrow.rays",
                name: "Cursor",
                hint: "via Cursor app",
                keyConfig: nil
            ),
            ProviderSettingsItem(
                id: "codex",
                icon: "terminal.fill",
                name: "Codex",
                hint: "via codex login",
                keyConfig: nil
            ),
            ProviderSettingsItem(
                id: "elevenlabs",
                icon: "waveform",
                name: "ElevenLabs",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "xi-api-key...",
                    hint: "elevenlabs.io/app/settings/api-keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://elevenlabs.io/app/settings/api-keys"),
                    key: $elevenLabsKey,
                    saved: $elevenLabsSaved,
                    onSave: { saveKey("elevenlabs", elevenLabsKey) }
                )
            ),
            ProviderSettingsItem(
                id: "stability",
                icon: "paintbrush",
                name: "Stability AI",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "sk-...",
                    hint: "platform.stability.ai/account/keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://platform.stability.ai/account/keys"),
                    key: $stabilityKey,
                    saved: $stabilitySaved,
                    onSave: { saveKey("stability", stabilityKey) }
                )
            ),
            ProviderSettingsItem(
                id: "runway",
                icon: "film",
                name: "Runway",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "key_...",
                    hint: "dev.runwayml.com",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://dev.runwayml.com"),
                    key: $runwayKey,
                    saved: $runwaySaved,
                    onSave: { saveKey("runway", runwayKey) }
                )
            ),
            ProviderSettingsItem(
                id: "openai",
                icon: "sparkles",
                name: "OpenAI API",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "sk-...",
                    hint: "platform.openai.com/api-keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://platform.openai.com/api-keys"),
                    key: $openAIKey,
                    saved: $openAISaved,
                    onSave: { saveKey("openai", openAIKey) }
                )
            )
        ]
    }

    /// Returns the app version string for display.
    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?):
            return "v\(version) (\(build))"
        case let (version?, nil):
            return "v\(version)"
        case let (nil, build?):
            return "v\(build)"
        default:
            return "v1.0"
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Interval", selection: Binding(
                    get: { appState.config.refreshIntervalMinutes },
                    set: { appState.updateRefreshInterval($0) }
                )) {
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("60 minutes").tag(60)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Refresh")
            } footer: {
                Text("All providers refresh together. Default interval is 10 minutes.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("Display") {
                Toggle("Hide not connected", isOn: Binding(
                    get: { appState.config.hideNotConnected },
                    set: { appState.updateHideNotConnected($0) }
                ))
            }

            Section("Providers & Keys") {
                ForEach(providerSettings) { provider in
                    ProviderSettingsRow(provider: provider, appState: appState)
                }
            }

            Section("About") {
                HStack {
                    Text("UsageTracker")
                    Spacer()
                    Text(appVersionLabel)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Button("Open plugins folder") {
                        openPluginsFolder()
                    }

                    Spacer()

                    Button("Check for updates") {
                        checkForUpdates()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 780)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loadAllKeys()
        }
    }

    /// Enables or disables launch at login.
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

    /// Loads all stored API keys into view state.
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

    /// Loads a single API key from the config directory.
    private func loadKey(_ name: String) -> String? {
        let path = configDir.appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: path),
              let config = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return config["api_key"]
    }

    /// Saves an API key and triggers a refresh.
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

    /// Opens the plugins folder in Finder.
    private func openPluginsFolder() {
        let pluginsDir = configDir.appendingPathComponent("plugins")
        try? FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(pluginsDir)
    }

    /// Triggers a standard update check action if supported.
    private func checkForUpdates() {
        NSApp.sendAction(Selector(("checkForUpdates:")), to: nil, from: nil)
    }
}

/// API key entry UI with save button and link.
struct APIKeyInput: View {
    let icon: String
    let name: String
    let placeholder: String
    let hint: String
    let linkTitle: String
    let linkURL: URL?
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
            if let linkURL = linkURL {
                Link(linkTitle, destination: linkURL)
                    .font(.system(size: 10))
            }
        }
        .padding(.vertical, 4)
    }
}

/// Provider toggle row with icon and hint text.
struct ProviderToggle: View {
    let icon: String
    let name: String
    let hint: String
    let id: String
    @ObservedObject var appState: AppState

    var body: some View {
        Toggle(isOn: Binding(
            get: { appState.config.isProviderEnabled(id) },
            set: { appState.updateProviderEnabled(id, enabled: $0) }
        )) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(name)
                Spacer()
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Provider row that groups toggle and optional API key input.
struct ProviderSettingsRow: View {
    let provider: ProviderSettingsItem
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProviderToggle(
                icon: provider.icon,
                name: provider.name,
                hint: provider.hint,
                id: provider.id,
                appState: appState
            )

            if let keyConfig = provider.keyConfig {
                APIKeyInput(
                    icon: provider.icon,
                    name: provider.name,
                    placeholder: keyConfig.placeholder,
                    hint: keyConfig.hint,
                    linkTitle: keyConfig.linkTitle,
                    linkURL: keyConfig.linkURL,
                    key: keyConfig.key,
                    saved: keyConfig.saved,
                    onSave: keyConfig.onSave
                )
                .padding(.leading, 22)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Provider metadata for the settings UI.
struct ProviderSettingsItem: Identifiable {
    let id: String
    let icon: String
    let name: String
    let hint: String
    let keyConfig: ProviderKeyConfig?
}

/// API key settings payload for a provider.
struct ProviderKeyConfig {
    let placeholder: String
    let hint: String
    let linkTitle: String
    let linkURL: URL?
    let key: Binding<String>
    let saved: Binding<Bool>
    let onSave: () -> Void
}
