// Sources/UsageTracker/Views/Settings/ProviderCatalog.swift
import SwiftUI

/// How a provider is connected with a pasted secret (API key, or Claude's browser cookie).
struct ProviderKeySpec: Sendable {
    /// File in ~/.usagetracker holding `{"api_key": ...}`.
    let fileName: String
    let title: String
    let placeholder: String
    let hint: String
    let linkTitle: String
    let linkURL: URL?
    let validate: @Sendable (String) async -> (Bool, String?)
    /// Normalizes what the user pasted before it is written (Claude keeps only `sessionKey`).
    var canonicalize: @Sendable (String) -> String = { $0 }
}

/// Static description of a provider for the Settings window: sidebar tile, page header, key field.
struct ProviderSettingsInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let icon: String
    let tint: Color
    /// How the provider connects, shown under its name.
    let connection: String
    let dashboardURL: URL?
    let key: ProviderKeySpec?
    var isUntested = false
}

enum ProviderCatalog {
    static let all: [String: ProviderSettingsInfo] = Dictionary(uniqueKeysWithValues: [
        ProviderSettingsInfo(
            id: "claude", name: "Claude", icon: "brain", tint: Color(red: 0.85, green: 0.47, blue: 0.34),
            connection: "Claude Code sign-in or a browser cookie",
            dashboardURL: URL(string: "https://claude.ai/settings/usage"),
            key: ProviderKeySpec(
                fileName: "claude-web", title: "Browser Cookie",
                placeholder: "sessionKey cookie (web-only users)",
                hint: "claude.ai → DevTools → Application → Cookies → sessionKey",
                linkTitle: "Open claude.ai", linkURL: URL(string: "https://claude.ai"),
                validate: validateClaudeCookie,
                canonicalize: { ClaudeWebProvider.extractSessionKey(from: $0) ?? $0 }
            )
        ),
        ProviderSettingsInfo(
            id: "codex", name: "Codex", icon: "terminal.fill", tint: Color(red: 0.20, green: 0.22, blue: 0.26),
            connection: "Signs in through codex login",
            dashboardURL: URL(string: "https://chatgpt.com/"), key: nil
        ),
        ProviderSettingsInfo(
            id: "cursor", name: "Cursor", icon: "cursorarrow.rays", tint: Color(red: 0.23, green: 0.47, blue: 0.95),
            connection: "Signs in through the Cursor app",
            dashboardURL: URL(string: "https://cursor.sh/settings"), key: nil
        ),
        ProviderSettingsInfo(
            id: "openai", name: "OpenAI API", icon: "sparkles", tint: Color(red: 0.06, green: 0.64, blue: 0.50),
            connection: "Uses an API key",
            dashboardURL: URL(string: "https://platform.openai.com/usage"),
            key: ProviderKeySpec(
                fileName: "openai", title: "API Key", placeholder: "sk-admin-… or sk-proj-…",
                hint: "platform.openai.com/api-keys", linkTitle: "Get key",
                linkURL: URL(string: "https://platform.openai.com/api-keys"),
                validate: validateOpenAIKey
            )
        ),
        ProviderSettingsInfo(
            id: "openrouter", name: "OpenRouter", icon: "arrow.trianglehead.branch", tint: Color(red: 0.39, green: 0.40, blue: 0.95),
            connection: "Uses an API key",
            dashboardURL: nil,
            key: ProviderKeySpec(
                fileName: "openrouter", title: "API Key", placeholder: "sk-or-…",
                hint: "openrouter.ai/settings/keys", linkTitle: "Get key",
                linkURL: URL(string: "https://openrouter.ai/settings/keys"),
                validate: validateOpenRouterKey
            )
        ),
        ProviderSettingsInfo(
            id: "elevenlabs", name: "ElevenLabs", icon: "waveform", tint: Color(red: 0.13, green: 0.13, blue: 0.14),
            connection: "Uses an API key",
            dashboardURL: URL(string: "https://elevenlabs.io/app/subscription"),
            key: ProviderKeySpec(
                fileName: "elevenlabs", title: "API Key", placeholder: "API key",
                hint: "elevenlabs.io/app/settings/api-keys", linkTitle: "Get key",
                linkURL: URL(string: "https://elevenlabs.io/app/settings/api-keys"),
                validate: validateElevenLabsKey
            )
        ),
        ProviderSettingsInfo(
            id: "stability", name: "Stability AI", icon: "paintbrush.fill", tint: Color(red: 0.55, green: 0.33, blue: 0.85),
            connection: "Uses an API key",
            dashboardURL: URL(string: "https://platform.stability.ai/account/credits"),
            key: ProviderKeySpec(
                fileName: "stability", title: "API Key", placeholder: "API key",
                hint: "platform.stability.ai/account/keys", linkTitle: "Get key",
                linkURL: URL(string: "https://platform.stability.ai/account/keys"),
                validate: validateStabilityKey
            ),
            isUntested: true
        ),
        ProviderSettingsInfo(
            id: "runway", name: "Runway", icon: "film.fill", tint: Color(red: 0.90, green: 0.30, blue: 0.45),
            connection: "Uses an API key",
            dashboardURL: URL(string: "https://dev.runwayml.com"),
            key: ProviderKeySpec(
                fileName: "runway", title: "API Key", placeholder: "key_…",
                hint: "dev.runwayml.com", linkTitle: "Get key",
                linkURL: URL(string: "https://dev.runwayml.com"),
                validate: validateRunwayKey
            ),
            isUntested: true
        ),
    ].map { ($0.id, $0) })

    // MARK: - Key persistence

    private static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".usagetracker")
    }

    static func loadKey(_ fileName: String) -> String? {
        let path = configDir.appendingPathComponent("\(fileName).json")
        guard let data = try? Data(contentsOf: path),
              let config = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return config["api_key"]
    }

    @discardableResult
    static func saveKey(_ fileName: String, _ key: String) -> Bool {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let path = configDir.appendingPathComponent("\(fileName).json")
        guard let data = try? JSONEncoder().encode(["api_key": key]),
              (try? data.write(to: path)) != nil else { return false }
        // These files hold live credentials (a claude.ai session cookie grants full
        // account access) and the default umask leaves them 0644, readable by every
        // local user. Restrict them to their owner.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        return true
    }

    // MARK: - Validators

    /// Confirms a pasted claude.ai session cookie by asking for the account's organizations,
    /// the same call `ClaudeWebProvider` makes first, so a pass here means usage will load.
    static func validateClaudeCookie(_ raw: String) async -> (Bool, String?) {
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

    static func validateElevenLabsKey(_ key: String) async -> (Bool, String?) {
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user")!)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        return await checkStatus(request)
    }

    static func validateStabilityKey(_ key: String) async -> (Bool, String?) {
        var request = URLRequest(url: URL(string: "https://api.stability.ai/v1/user/account")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return await checkStatus(request)
    }

    static func validateRunwayKey(_ key: String) async -> (Bool, String?) {
        if key.hasPrefix("key_") && key.count > 10 {
            return (true, nil)
        }
        return (false, "Key should start with 'key_'")
    }

    static func validateOpenRouterKey(_ key: String) async -> (Bool, String?) {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/key")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return await checkStatus(request)
    }

    static func validateOpenAIKey(_ key: String) async -> (Bool, String?) {
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
        return await checkStatus(request, forbidden: isAdminKey ? "Need usage scope" : "Missing permissions")
    }

    /// 200 → valid, 401 → invalid key, anything else → the status code.
    private static func checkStatus(_ request: URLRequest, forbidden: String? = nil) async -> (Bool, String?) {
        var request = request
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return (false, "Invalid response") }
            if http.statusCode == 200 { return (true, nil) }
            if http.statusCode == 401 { return (false, "Invalid API key") }
            if http.statusCode == 403, let forbidden { return (false, forbidden) }
            return (false, "HTTP \(http.statusCode)")
        } catch {
            return (false, "Connection failed")
        }
    }
}
