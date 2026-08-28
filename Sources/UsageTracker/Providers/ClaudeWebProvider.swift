import Foundation

/// Claude usage for people who never installed the CLI.
///
/// `ClaudeProvider` reads the OAuth token Claude Code leaves behind, so it only works for
/// CLI users. Someone who uses claude.ai in a browser has no such token — for them the app
/// showed nothing at all. This path authenticates with the `sessionKey` cookie from a
/// claude.ai browser session instead, and calls claude.ai's own web API.
///
/// The web API returns the same JSON shape as the OAuth usage endpoint (`five_hour`,
/// `seven_day`, `seven_day_sonnet`, `seven_day_opus`, `extra_usage`), so the response decodes
/// into `ClaudeProvider.UsageResponse` and the rows are built by the same shared builder.
/// The two paths must keep showing identical rows.
actor ClaudeWebProvider {
    private let baseURL = "https://claude.ai/api"
    private let settingsURL = URL(string: "https://claude.ai/settings/usage")!
    private let configPath = NSString(string: "~/.usagetracker/claude-web.json").expandingTildeInPath


    /// The session cookie, or nil when the user has not pasted one.
    ///
    /// Accepts whatever the user copied: a whole `Cookie:` request header, a
    /// `sessionKey=...; other=...` cookie string, or the bare `sk-ant-...` value.
    func sessionKey() -> String? {
        guard let data = FileManager.default.contents(atPath: configPath),
              let stored = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        // Settings writes this through the shared key-file helper, which names the field
        // `api_key`; `cookie` is accepted too for a hand-written file.
        guard let raw = stored["cookie"] ?? stored["api_key"] else { return nil }
        return Self.extractSessionKey(from: raw)
    }

    static func extractSessionKey(from raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("cookie:") {
            value = String(value.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespaces)
        }
        // A pasted header can carry many cookies; only sessionKey matters.
        for pair in value.split(separator: ";") {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("sessionKey=") {
                let key = String(trimmed.dropFirst("sessionKey=".count)).trimmingCharacters(in: .whitespaces)
                return key.isEmpty ? nil : key
            }
        }
        // Bare value, pasted without the cookie name.
        return value.hasPrefix("sk-ant-") ? value : nil
    }

    /// Fetches usage via the browser session.
    ///
    /// Returns nil when no cookie is configured, so the caller can fall back to its own
    /// "not connected" state rather than reporting a failure the user did not cause.
    func fetchUsage() async throws -> Provider? {
        guard let key = sessionKey() else { return nil }

        let organizationIDs: [String]
        do {
            organizationIDs = try await fetchOrganizationIDs(key: key)
        } catch let error as ExpiredSession {
            _ = error
            return expired()
        }
        guard !organizationIDs.isEmpty else {
            return Provider(
                id: "claude", name: "Claude", icon: "brain",
                items: [], status: .error("No organizations")
            )
        }

        // An account can belong to several organizations and only one of them carries the
        // subscription. Rather than guessing from org metadata, take the first that reports
        // an actual usage window.
        for orgID in organizationIDs {
            let usage: ClaudeProvider.UsageResponse
            do {
                usage = try await fetchUsage(orgID: orgID, key: key)
            } catch let error as ExpiredSession {
                _ = error
                return expired()
            }
            let items = ClaudeProvider.usageItems(from: usage)
            if !items.isEmpty {
                return Provider(
                    id: "claude", name: "Claude", icon: "brain",
                    items: items,
                    status: .loaded,
                    boostStatus: Claude2xDetector.loadFromDisk().status()
                )
            }
        }

        return Provider(
            id: "claude", name: "Claude", icon: "brain",
            items: [], status: .error("No usage data")
        )
    }

    // MARK: - Requests

    /// Thrown when claude.ai rejects the cookie, so callers can surface "paste a fresh one"
    /// instead of a generic HTTP error.
    private struct ExpiredSession: Error {}

    private func expired() -> Provider {
        Provider(
            id: "claude", name: "Claude", icon: "brain",
            items: [], status: .error("Session expired — paste a new cookie")
        )
    }

    private func request(_ path: String, key: String) -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("sessionKey=\(key)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 || http.statusCode == 403 { throw ExpiredSession() }
        // Transient failures throw so `refresh()` keeps the last-known reading rather than
        // replacing a good row with an error.
        if isTransientHTTPStatus(http.statusCode) {
            throw URLError(.init(rawValue: http.statusCode))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.init(rawValue: http.statusCode))
        }
        return data
    }

    private struct Organization: Codable {
        var uuid: String
    }

    private func fetchOrganizationIDs(key: String) async throws -> [String] {
        let data = try await data(for: request("/organizations", key: key))
        return (try JSONDecoder().decode([Organization].self, from: data)).map(\.uuid)
    }

    private func fetchUsage(orgID: String, key: String) async throws -> ClaudeProvider.UsageResponse {
        let data = try await data(for: request("/organizations/\(orgID)/usage", key: key))
        return try JSONDecoder().decode(ClaudeProvider.UsageResponse.self, from: data)
    }
}
