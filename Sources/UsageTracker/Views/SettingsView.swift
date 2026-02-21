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
    @State private var openRouterKey: String = ""
    @State private var openRouterSaved: Bool = false

    private let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".usagetracker")

    /// All provider definitions
    private var allProviders: [String: ProviderSettingsItem] {
        [
            "claude": ProviderSettingsItem(
                id: "claude",
                icon: "brain",
                name: "Claude",
                hint: "via Claude Code",
                keyConfig: nil
            ),
            "cursor": ProviderSettingsItem(
                id: "cursor",
                icon: "cursorarrow.rays",
                name: "Cursor",
                hint: "via Cursor app",
                keyConfig: nil
            ),
            "codex": ProviderSettingsItem(
                id: "codex",
                icon: "terminal.fill",
                name: "Codex",
                hint: "via codex login",
                keyConfig: nil
            ),
            "elevenlabs": ProviderSettingsItem(
                id: "elevenlabs",
                icon: "waveform",
                name: "ElevenLabs",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "elevenlabs.io/app/settings/api-keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://elevenlabs.io/app/settings/api-keys"),
                    key: $elevenLabsKey,
                    saved: $elevenLabsSaved,
                    onSave: { saveKey("elevenlabs", elevenLabsKey) },
                    validateKey: validateElevenLabsKey
                )
            ),
            "stability": ProviderSettingsItem(
                id: "stability",
                icon: "paintbrush",
                name: "Stability AI",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "platform.stability.ai/account/keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://platform.stability.ai/account/keys"),
                    key: $stabilityKey,
                    saved: $stabilitySaved,
                    onSave: { saveKey("stability", stabilityKey) },
                    validateKey: validateStabilityKey
                )
            ),
            "runway": ProviderSettingsItem(
                id: "runway",
                icon: "film",
                name: "Runway",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "dev.runwayml.com",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://dev.runwayml.com"),
                    key: $runwayKey,
                    saved: $runwaySaved,
                    onSave: { saveKey("runway", runwayKey) },
                    validateKey: validateRunwayKey
                )
            ),
            "openai": ProviderSettingsItem(
                id: "openai",
                icon: "sparkles",
                name: "OpenAI API",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "platform.openai.com/api-keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://platform.openai.com/api-keys"),
                    key: $openAIKey,
                    saved: $openAISaved,
                    onSave: { saveKey("openai", openAIKey) },
                    validateKey: validateOpenAIKey
                )
            ),
            "openrouter": ProviderSettingsItem(
                id: "openrouter",
                icon: "arrow.trianglehead.branch",
                name: "OpenRouter",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "openrouter.ai/settings/keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://openrouter.ai/settings/keys"),
                    key: $openRouterKey,
                    saved: $openRouterSaved,
                    onSave: { saveKey("openrouter", openRouterKey) },
                    validateKey: validateOpenRouterKey
                )
            )
        ]
    }

    /// Provider list sorted by user's configured order
    private var providerSettings: [ProviderSettingsItem] {
        appState.config.providerOrder.compactMap { allProviders[$0] }
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
        NavigationStack {
            Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }

                Toggle("Hide not connected", isOn: Binding(
                    get: { appState.config.hideNotConnected },
                    set: { appState.updateHideNotConnected($0) }
                ))
            }

            Section("Providers & Keys") {
                ForEach(providerSettings) { provider in
                    ProviderSettingsRow(provider: provider, appState: appState)
                        .onDrag {
                            NSItemProvider(object: provider.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: ProviderDropDelegate(
                            item: provider.id,
                            appState: appState
                        ))
                }
            }

            Section("About") {
                NavigationLink {
                    HelpView()
                } label: {
                    Label("How It Works", systemImage: "questionmark.circle")
                }
            }

            Section {
                HStack {
                    Text("UsageTracker")
                    Spacer()
                    Text(appVersionLabel)
                        .foregroundColor(.secondary)
                }
            }
        }
            .formStyle(.grouped)
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
        }
        .frame(width: 400, height: 600)
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

        openRouterKey = loadKey("openrouter") ?? ""
        openRouterSaved = !openRouterKey.isEmpty
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
            case "openrouter": openRouterSaved = true
            default: break
            }

            // Trigger refresh
            Task {
                await appState.refresh()
            }
        }
    }

    // MARK: - API Key Validation

    private func validateElevenLabsKey(_ key: String) async -> (Bool, String?) {
        let url = URL(string: "https://api.elevenlabs.io/v1/user")!
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 { return (true, nil) }
                if httpResponse.statusCode == 401 { return (false, "Invalid API key") }
                return (false, "HTTP \(httpResponse.statusCode)")
            }
            return (false, "Invalid response")
        } catch {
            return (false, "Connection failed")
        }
    }

    private func validateStabilityKey(_ key: String) async -> (Bool, String?) {
        let url = URL(string: "https://api.stability.ai/v1/user/account")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 { return (true, nil) }
                if httpResponse.statusCode == 401 { return (false, "Invalid API key") }
                return (false, "HTTP \(httpResponse.statusCode)")
            }
            return (false, "Invalid response")
        } catch {
            return (false, "Connection failed")
        }
    }

    private func validateRunwayKey(_ key: String) async -> (Bool, String?) {
        // Runway doesn't have a simple validation endpoint, so we just check format
        if key.hasPrefix("key_") && key.count > 10 {
            return (true, nil)
        }
        return (false, "Key should start with 'key_'")
    }

    private func validateOpenRouterKey(_ key: String) async -> (Bool, String?) {
        let url = URL(string: "https://openrouter.ai/api/v1/key")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 { return (true, nil) }
                if httpResponse.statusCode == 401 { return (false, "Invalid API key") }
                return (false, "HTTP \(httpResponse.statusCode)")
            }
            return (false, "Invalid response")
        } catch {
            return (false, "Connection failed")
        }
    }

    private func validateOpenAIKey(_ key: String) async -> (Bool, String?) {
        // Admin keys (sk-admin-) use different endpoints than project keys
        let isAdminKey = key.hasPrefix("sk-admin-")

        let url: URL
        if isAdminKey {
            // Admin keys: test with organization costs endpoint
            let now = Int(Date().timeIntervalSince1970)
            let start = now - 86400 // 1 day ago
            url = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(start)&end_time=\(now)&bucket_width=1d")!
        } else {
            // Project keys: test with models endpoint
            url = URL(string: "https://api.openai.com/v1/models")!
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 { return (true, nil) }
                if httpResponse.statusCode == 401 { return (false, "Invalid API key") }
                if httpResponse.statusCode == 403 {
                    if isAdminKey {
                        return (false, "Need usage scope")
                    }
                    return (false, "Missing permissions")
                }
                return (false, "HTTP \(httpResponse.statusCode)")
            }
            return (false, "Invalid response")
        } catch {
            return (false, "Connection failed")
        }
    }

}

/// Validation state for API keys
enum KeyValidationState {
    case idle
    case checking
    case valid
    case invalid(String)
}

/// API key entry UI with auto-validation.
struct APIKeyInput: View {
    let placeholder: String
    let hint: String
    let linkTitle: String
    let linkURL: URL?
    @Binding var key: String
    @Binding var saved: Bool
    let onSave: () -> Void
    let validateKey: (String) async -> (Bool, String?)

    @State private var validationState: KeyValidationState = .idle
    @State private var validationTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SecureField(placeholder, text: $key)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(borderColor, lineWidth: 1)
                    )
                    .onChange(of: key) { _, newValue in
                        saved = false
                        validateKeyDebounced(newValue)
                    }

                if case .checking = validationState {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 44, height: 24)
                } else {
                    Button(buttonLabel) {
                        onSave()
                    }
                    .disabled(key.isEmpty || !isValid)
                    .buttonStyle(.borderedProminent)
                    .tint(buttonTint)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 4) {
                if case .invalid(let message) = validationState {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                } else if case .valid = validationState {
                    Text("Key valid")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                } else {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let linkURL = linkURL {
                        Link(linkTitle, destination: linkURL)
                            .font(.system(size: 10))
                    }
                }
            }
        }
    }

    private var borderColor: Color {
        switch validationState {
        case .invalid: return Color.red.opacity(0.8)
        case .valid: return Color.green.opacity(0.8)
        default: return Color.gray.opacity(0.3)
        }
    }

    private var isValid: Bool {
        if case .invalid = validationState { return false }
        return true
    }

    private var buttonLabel: String {
        if saved { return "✓" }
        if case .valid = validationState { return "Save" }
        return "Save"
    }

    private var buttonTint: Color {
        if saved { return .green }
        if case .valid = validationState { return .blue }
        return .gray
    }

    private func validateKeyDebounced(_ newKey: String) {
        validationTask?.cancel()

        guard !newKey.isEmpty else {
            validationState = .idle
            return
        }

        validationTask = Task {
            // Debounce - wait before validating
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run { validationState = .checking }

            let (isValid, errorMessage) = await validateKey(newKey)

            guard !Task.isCancelled else { return }
            await MainActor.run {
                if isValid {
                    validationState = .valid
                } else {
                    validationState = .invalid(errorMessage ?? "Invalid key")
                }
            }
        }
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
        HStack {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundColor(Color.gray.opacity(0.5))
                .frame(width: 16)

            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { appState.config.isProviderEnabled(id) },
                set: { appState.updateProviderEnabled(id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }
}

/// Provider row that groups toggle and optional API key input.
struct ProviderSettingsRow: View {
    let provider: ProviderSettingsItem
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderToggle(
                icon: provider.icon,
                name: provider.name,
                hint: provider.hint,
                id: provider.id,
                appState: appState
            )

            if let keyConfig = provider.keyConfig {
                APIKeyInput(
                    placeholder: keyConfig.placeholder,
                    hint: keyConfig.hint,
                    linkTitle: keyConfig.linkTitle,
                    linkURL: keyConfig.linkURL,
                    key: keyConfig.key,
                    saved: keyConfig.saved,
                    onSave: keyConfig.onSave,
                    validateKey: keyConfig.validateKey
                )
                .padding(.leading, 44)
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
    let validateKey: (String) async -> (Bool, String?)
}

/// Drop delegate for provider reordering
struct ProviderDropDelegate: DropDelegate {
    let item: String
    let appState: AppState

    func performDrop(info: DropInfo) -> Bool {
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = info.itemProviders(for: [.text]).first else { return }

        draggedItem.loadObject(ofClass: NSString.self) { reading, _ in
            guard let draggedId = reading as? String, draggedId != item else { return }

            DispatchQueue.main.async {
                var order = appState.config.providerOrder
                guard let fromIndex = order.firstIndex(of: draggedId),
                      let toIndex = order.firstIndex(of: item) else { return }

                withAnimation {
                    order.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                    appState.updateProviderOrder(order)
                }
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

/// Help page view
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Auto-Detected Services") {
                HelpRow(
                    icon: "brain",
                    iconColor: .purple,
                    title: "Claude",
                    description: "Detected from Claude Code CLI. Run 'claude' in terminal to sign in."
                )
                HelpRow(
                    icon: "cursorarrow.rays",
                    iconColor: .blue,
                    title: "Cursor",
                    description: "Detected from Cursor app. Sign in to Cursor to see your usage."
                )
                HelpRow(
                    icon: "terminal.fill",
                    iconColor: .green,
                    title: "Codex",
                    description: "Detected from Codex CLI. Run 'codex login' in terminal to sign in."
                )
            }

            Section("API Key Services") {
                HelpRow(
                    icon: "sparkles",
                    iconColor: .teal,
                    title: "OpenAI",
                    description: "Add API key from platform.openai.com/api-keys"
                )
                HelpRow(
                    icon: "waveform",
                    iconColor: .pink,
                    title: "ElevenLabs",
                    description: "Add API key from elevenlabs.io/app/settings/api-keys"
                )
                HelpRow(
                    icon: "paintbrush",
                    iconColor: .orange,
                    title: "Stability AI",
                    description: "Add API key from platform.stability.ai/account/keys"
                )
                HelpRow(
                    icon: "film",
                    iconColor: .red,
                    title: "Runway",
                    description: "Add API key from dev.runwayml.com"
                )
                HelpRow(
                    icon: "arrow.trianglehead.branch",
                    iconColor: .cyan,
                    title: "OpenRouter",
                    description: "Add API key from openrouter.ai/settings/keys"
                )
            }

            Section("Tips") {
                HelpRow(
                    icon: "cursorarrow.click.2",
                    iconColor: .blue,
                    title: "View Usage",
                    description: "Left-click the menu bar icon to see your usage stats."
                )
                HelpRow(
                    icon: "contextualmenu.and.cursorarrow",
                    iconColor: .gray,
                    title: "Quick Access",
                    description: "Right-click for Settings, Clear Cache, and Quit options."
                )
                HelpRow(
                    icon: "line.3.horizontal",
                    iconColor: .purple,
                    title: "Reorder",
                    description: "Drag providers in Settings to change display order."
                )
                HelpRow(
                    icon: "eye.slash",
                    iconColor: .secondary,
                    title: "Hide Services",
                    description: "Toggle off services you don't use in Settings."
                )
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.never)
        .navigationTitle("How It Works")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

/// Help row for the How It Works section
struct HelpRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}
