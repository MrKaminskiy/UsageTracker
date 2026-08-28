// Sources/UsageTracker/Views/Settings/Tabs/ProvidersTab.swift
import SwiftUI

struct ProvidersTab: View {
    @ObservedObject var appState: AppState

    @State private var claudeCookie: String = ""
    @State private var claudeCookieSaved: Bool = false
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

    private var allProviders: [String: ProviderSettingsItem] {
        [
            "claude": ProviderSettingsItem(
                id: "claude", icon: "brain", name: "Claude",
                hint: "via Claude Code, or a browser cookie",
                keyConfig: ProviderKeyConfig(
                    placeholder: "sessionKey cookie (web-only users)",
                    hint: "claude.ai → DevTools → Application → Cookies → sessionKey",
                    linkTitle: "Open claude.ai",
                    linkURL: URL(string: "https://claude.ai"),
                    key: $claudeCookie, saved: $claudeCookieSaved,
                    onSave: { saveKey("claude-web", claudeCookie) },
                    validateKey: validateClaudeCookie
                )
            ),
            "cursor": ProviderSettingsItem(
                id: "cursor", icon: "cursorarrow.rays", name: "Cursor",
                hint: "via Cursor app", keyConfig: nil
            ),
            "codex": ProviderSettingsItem(
                id: "codex", icon: "terminal.fill", name: "Codex",
                hint: "via codex login", keyConfig: nil
            ),
            "elevenlabs": ProviderSettingsItem(
                id: "elevenlabs", icon: "waveform", name: "ElevenLabs",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "elevenlabs.io/app/settings/api-keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://elevenlabs.io/app/settings/api-keys"),
                    key: $elevenLabsKey, saved: $elevenLabsSaved,
                    onSave: { saveKey("elevenlabs", elevenLabsKey) },
                    validateKey: validateElevenLabsKey
                )
            ),
            "stability": ProviderSettingsItem(
                id: "stability", icon: "paintbrush", name: "Stability AI",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "platform.stability.ai/account/keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://platform.stability.ai/account/keys"),
                    key: $stabilityKey, saved: $stabilitySaved,
                    onSave: { saveKey("stability", stabilityKey) },
                    validateKey: validateStabilityKey
                )
            ),
            "runway": ProviderSettingsItem(
                id: "runway", icon: "film", name: "Runway",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "dev.runwayml.com",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://dev.runwayml.com"),
                    key: $runwayKey, saved: $runwaySaved,
                    onSave: { saveKey("runway", runwayKey) },
                    validateKey: validateRunwayKey
                )
            ),
            "openai": ProviderSettingsItem(
                id: "openai", icon: "sparkles", name: "OpenAI API",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "platform.openai.com/api-keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://platform.openai.com/api-keys"),
                    key: $openAIKey, saved: $openAISaved,
                    onSave: { saveKey("openai", openAIKey) },
                    validateKey: validateOpenAIKey
                )
            ),
            "openrouter": ProviderSettingsItem(
                id: "openrouter", icon: "arrow.trianglehead.branch", name: "OpenRouter",
                hint: "API key required",
                keyConfig: ProviderKeyConfig(
                    placeholder: "API key",
                    hint: "openrouter.ai/settings/keys",
                    linkTitle: "Get key",
                    linkURL: URL(string: "https://openrouter.ai/settings/keys"),
                    key: $openRouterKey, saved: $openRouterSaved,
                    onSave: { saveKey("openrouter", openRouterKey) },
                    validateKey: validateOpenRouterKey
                )
            )
        ]
    }

    private var providerSettings: [ProviderSettingsItem] {
        appState.config.providerOrder.compactMap { allProviders[$0] }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCard {
                    ForEach(Array(providerSettings.enumerated()), id: \.element.id) { index, provider in
                        ProviderDisclosureRow(provider: provider, appState: appState)
                            .onDrag {
                                NSItemProvider(object: provider.id as NSString)
                            }
                            .onDrop(of: [.text], delegate: ProviderDropDelegate(
                                item: provider.id,
                                appState: appState
                            ))
                        if index < providerSettings.count - 1 {
                            SettingsCardDivider()
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .onAppear {
            loadAllKeys()
        }
    }

    // MARK: - Key persistence

    private func loadAllKeys() {
        elevenLabsKey = loadKey("elevenlabs") ?? ""
        elevenLabsSaved = !elevenLabsKey.isEmpty

        claudeCookie = loadKey("claude-web") ?? ""
        claudeCookieSaved = !claudeCookie.isEmpty

        stabilityKey = loadKey("stability") ?? ""
        stabilitySaved = !stabilityKey.isEmpty

        runwayKey = loadKey("runway") ?? ""
        runwaySaved = !runwayKey.isEmpty

        openAIKey = loadKey("openai") ?? ""
        openAISaved = !openAIKey.isEmpty

        openRouterKey = loadKey("openrouter") ?? ""
        openRouterSaved = !openRouterKey.isEmpty
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

            switch name {
            case "claude-web": claudeCookieSaved = true
            case "elevenlabs": elevenLabsSaved = true
            case "stability": stabilitySaved = true
            case "runway": runwaySaved = true
            case "openai": openAISaved = true
            case "openrouter": openRouterSaved = true
            default: break
            }

            Task { await appState.refresh() }
        }
    }

    // MARK: - Validators (copied verbatim from current SettingsView)

    /// Confirms a pasted claude.ai session cookie by asking for the account's organizations —
    /// the same call `ClaudeWebProvider` makes first, so a pass here means usage will load.
    private func validateClaudeCookie(_ raw: String) async -> (Bool, String?) {
        guard let key = ClaudeWebProvider.extractSessionKey(from: raw) else {
            return (false, "No sessionKey found in that text")
        }
        var request = URLRequest(url: URL(string: "https://claude.ai/api/organizations")!)
        request.setValue("sessionKey=\(key)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return (false, "Invalid response") }
            if http.statusCode == 200 { return (true, nil) }
            if http.statusCode == 401 || http.statusCode == 403 { return (false, "Cookie expired or invalid") }
            return (false, "HTTP \(http.statusCode)")
        } catch {
            return (false, "Network error")
        }
    }

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
        let isAdminKey = key.hasPrefix("sk-admin-")
        let url: URL
        if isAdminKey {
            let now = Int(Date().timeIntervalSince1970)
            let start = now - 86400
            url = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(start)&end_time=\(now)&bucket_width=1d")!
        } else {
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
                    if isAdminKey { return (false, "Need usage scope") }
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
