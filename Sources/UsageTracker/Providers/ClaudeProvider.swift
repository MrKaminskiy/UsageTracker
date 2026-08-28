import Foundation
import Security

actor ClaudeProvider {
    private let keychainService = "Claude Code-credentials"
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let scopes = "user:profile user:inference user:sessions:claude_code user:mcp_servers"
    static let refreshBufferMs: Double = 5 * 60 * 1000 // 5 minutes
    static let expiryGraceMs: Double = 30 * 1000 // 30 seconds
    private let insightsAnalyzer = ClaudeInsightsAnalyzer()
    // Fallback for people who never installed the CLI and so have no OAuth token to read.
    private let webProvider = ClaudeWebProvider()

    // Credentials cached in memory so the keychain (which can prompt the user
    // for access after Claude Code's /login recreates the item) is only read
    // when there is no cached token or the cached one is near expiry.
    private var cachedCredentials: LoadedCredentials?

    // Tokens that were refreshed but could not be written back to the shared store.
    // Retried on the next fetch: the refresh token they replaced is already dead
    // server-side, so leaving the store unsaved would eventually cost a `/login`.
    private var pendingWriteBack: (credentials: LoadedCredentials, spentRefreshToken: String?)?

    private struct LoadedCredentials {
        var credentials: Credentials
        // The store's original JSON object. Kept so that writing a refreshed
        // token back replaces only the token fields and leaves every key Claude
        // Code owns (scopes, rateLimitTier, …) untouched.
        var raw: [String: Any]
        var source: CredentialSource
    }

    struct Credentials: Codable {
        var claudeAiOauth: OAuthData?

        struct OAuthData: Codable {
            var accessToken: String
            var refreshToken: String?
            var expiresAt: Double?
            var subscriptionType: String?
        }
    }

    struct UsageResponse: Codable {
        var five_hour: UsageData?
        var seven_day: UsageData?
        var seven_day_sonnet: UsageData?
        var seven_day_opus: UsageData?
        var extra_usage: ExtraUsage?

        struct UsageData: Codable {
            var utilization: Double?
            var resets_at: String?
        }

        struct ExtraUsage: Codable {
            var is_enabled: Bool?
            var used_credits: Double?
            var monthly_limit: Double?
        }
    }

    private let settingsURL = URL(string: "https://claude.ai/settings/usage")!

    private enum CredentialSource {
        case keychain
        case file(URL)

        // Writing to the keychain item Claude Code owns is never safe: macOS replaces
        // the item's partition list with the writing app's own partition ID, which
        // evicts `apple-tool:` and makes every `/usr/bin/security` read Claude Code
        // performs pop a keychain password prompt (securityd: "ACL partition mismatch").
        // "Always Allow" restores the entry only until our next write. So the shared
        // keychain is read-only for us; only the plaintext credentials file is writable.
        var isWritable: Bool {
            if case .file = self { return true }
            return false
        }
    }

    func fetchUsage() async throws -> Provider {
        try await fetchUsage(retriesLeft: 2)
    }

    private func fetchUsage(retriesLeft: Int) async throws -> Provider {
        if let pending = pendingWriteBack {
            _ = persist(
                pending.credentials.credentials,
                into: pending.credentials,
                replacing: pending.spentRefreshToken
            )
        }

        guard var loaded = loadCredentials() else {
            // No CLI credentials at all — the case of someone who only uses claude.ai in a
            // browser. Try the pasted session cookie before declaring Claude unavailable.
            if let web = try await webProvider.fetchUsage() { return web }
            return Provider(
                id: "claude",
                name: "Claude",
                icon: "brain",
                items: [],
                status: .notConnected(url: settingsURL)
            )
        }

        // Claude Code refreshes the shared credentials on its own, and refreshing
        // rotates the refresh token — doing it ourselves invalidates whatever copy
        // the CLI still holds. loadCredentials() has already re-read the store for
        // anything near expiry, so only step in once the token is really dead.
        //
        // When the store is read-only (the shared keychain) we cannot refresh at all:
        // refreshing rotates the refresh token server-side, and without a write-back
        // the copy Claude Code still holds would be dead. Re-read instead — Claude Code
        // refreshes on its own and we pick the new token up from the store.
        if Self.isExpired(loaded.credentials.claudeAiOauth) {
            if loaded.source.isWritable {
                let spent = loaded.credentials.claudeAiOauth?.refreshToken
                if let refreshed = await refreshedCredentials(from: loaded.credentials) {
                    loaded = persist(refreshed, into: loaded, replacing: spent)
                }
            } else if let reloaded = loadCredentials(forceReload: true) {
                loaded = reloaded
            }
        }

        guard let oauth = loaded.credentials.claudeAiOauth else {
            return await webFallback(or: Provider(
                id: "claude",
                name: "Claude",
                icon: "brain",
                items: [],
                status: .error("Invalid credentials")
            ))
        }

        // Fetch usage
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(oauth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("UsageTracker", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return await webFallback(or: Provider(
                id: "claude",
                name: "Claude",
                icon: "brain",
                items: [],
                status: .error("Invalid response")
            ))
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            let expiredProvider = Provider(
                id: "claude",
                name: "Claude",
                icon: "brain",
                items: [],
                status: .error("Token expired. Run `claude` to log in again.")
            )
            guard retriesLeft > 0 else { return expiredProvider }

            // The token may have been rotated behind our back (e.g. /login in
            // Claude Code recreates the keychain item) — re-read the store and
            // retry with the new token before attempting our own refresh.
            if let reloaded = loadCredentials(forceReload: true) {
                loaded = reloaded
                if let newOauth = reloaded.credentials.claudeAiOauth,
                   newOauth.accessToken != oauth.accessToken,
                   !Self.isExpired(newOauth) {
                    return try await fetchUsage(retriesLeft: retriesLeft - 1)
                }
            }
            // Fall back to refreshing the token ourselves, then retry — but only for a
            // store we may write back to. Refreshing rotates the refresh token, so doing
            // it against the read-only shared keychain would cost Claude Code a `/login`.
            guard loaded.source.isWritable else { return expiredProvider }
            let spent = loaded.credentials.claudeAiOauth?.refreshToken
            if let refreshed = await refreshedCredentials(from: loaded.credentials) {
                _ = persist(refreshed, into: loaded, replacing: spent)
                return try await fetchUsage(retriesLeft: retriesLeft - 1)
            }
            return expiredProvider
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            // Throw on transient errors (rate limit, server errors) so the caller can
            // preserve the last-known data instead of replacing it with an error state.
            if isTransientHTTPStatus(httpResponse.statusCode) {
                throw URLError(.init(rawValue: httpResponse.statusCode))
            }
            return await webFallback(or: Provider(
                id: "claude",
                name: "Claude",
                icon: "brain",
                items: [],
                status: .error(httpErrorMessage(httpResponse.statusCode))
            ))
        }

        let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
        let items = Self.usageItems(from: usage)

        // 2x detection
        let detector = Claude2xDetector.loadFromDisk()
        let boostStatus = detector.status()

        // Cost estimation + local usage insights (caller controls cost visibility via showCostEstimate)
        let insights = await insightsAnalyzer.analyze()

        return Provider(
            id: "claude",
            name: "Claude",
            icon: "brain",
            items: items,
            status: items.isEmpty ? .error("No usage data") : .loaded,
            boostStatus: boostStatus,
            costEstimate: insights?.monthlyCost,
            planLabel: Self.planLabel(from: oauth.subscriptionType),
            insights: insights
        )
    }

    /// Falls back to the browser cookie when the CLI credentials are present but unusable
    /// (stale, malformed, or rejected). Only a web result with actual rows wins — otherwise
    /// the original CLI error is the more accurate thing to show the user.
    private func webFallback(or failure: Provider) async -> Provider {
        guard let web = try? await webProvider.fetchUsage(), !web.items.isEmpty else { return failure }
        return web
    }

    private func loadCredentials(forceReload: Bool = false) -> LoadedCredentials? {
        if !forceReload, let cached = cachedCredentials,
           !Self.needsRefresh(cached.credentials.claudeAiOauth) {
            return cached
        }
        let loaded = read(from: .keychain) ?? read(from: .file(credentialsFileURL()))
        cachedCredentials = loaded
        return loaded
    }

    private func read(from source: CredentialSource) -> LoadedCredentials? {
        let store: (credentials: Credentials, raw: [String: Any])?
        switch source {
        case .keychain: store = loadFromKeychain()
        case .file(let url): store = loadFromFile(url)
        }
        return store.map { LoadedCredentials(credentials: $0.credentials, raw: $0.raw, source: source) }
    }

    private func decode(_ data: Data) -> (credentials: Credentials, raw: [String: Any])? {
        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        return (credentials, raw)
    }

    private func credentialsFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }

    private func loadFromKeychain() -> (credentials: Credentials, raw: [String: Any])? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return decode(data)
    }

    private func loadFromFile(_ url: URL) -> (credentials: Credentials, raw: [String: Any])? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    // Writes refreshed tokens back into the store Claude Code shares with us,
    // replacing only the token fields inside the original JSON object. Re-encoding
    // our own `Credentials` struct here used to drop every key we don't model
    // (scopes, rateLimitTier, …), which broke the CLI's session and forced a
    // `/login` roughly once a day — once per access-token lifetime.
    //
    // `spentRefreshToken` is the token the refresh consumed. The store is re-read
    // right before writing: if it no longer holds that token, Claude Code logged in
    // or refreshed while our request was in flight, and its credentials are newer
    // than ours — adopt them instead of clobbering them with our stale snapshot.
    //
    // The check and the write are not atomic — SecItem offers no compare-and-swap,
    // and no lock is shared with the CLI — so a write started in the microseconds
    // between them can still be lost. That residual window is accepted: skipping
    // the write entirely would leave the store holding a refresh token the server
    // has already rotated away, which is the very failure this guards against.
    private func persist(
        _ credentials: Credentials,
        into loaded: LoadedCredentials,
        replacing spentRefreshToken: String?
    ) -> LoadedCredentials {
        guard let oauth = credentials.claudeAiOauth else { return loaded }

        var base = loaded
        if let current = read(from: loaded.source) {
            guard !Self.storeMovedOn(current.credentials.claudeAiOauth, spentRefreshToken: spentRefreshToken) else {
                cachedCredentials = current
                pendingWriteBack = nil
                Log.info("Claude: credential store changed while refreshing; keeping Claude Code's newer tokens")
                return current
            }
            base = current
        }

        var updated = base
        updated.credentials = credentials
        updated.raw = Self.merging(oauth, into: base.raw)

        cachedCredentials = updated
        // A refresh rotates the refresh token, so the copy left in the store is
        // already dead: a failed write has to be retried, not forgotten.
        pendingWriteBack = write(updated) ? nil : (updated, spentRefreshToken)
        return updated
    }

    // True when the shared store no longer holds the refresh token our refresh
    // consumed: Claude Code logged in or refreshed in the meantime, so what is in
    // the store is newer than what we are holding and must not be overwritten.
    static func storeMovedOn(_ stored: Credentials.OAuthData?, spentRefreshToken: String?) -> Bool {
        stored?.refreshToken != spentRefreshToken
    }

    // Replaces only the token fields of a store's JSON object; every other key,
    // at both levels, is carried over untouched.
    static func merging(_ oauth: Credentials.OAuthData, into raw: [String: Any]) -> [String: Any] {
        var raw = raw
        var oauthObject = raw["claudeAiOauth"] as? [String: Any] ?? [:]
        oauthObject["accessToken"] = oauth.accessToken
        if let refreshToken = oauth.refreshToken {
            oauthObject["refreshToken"] = refreshToken
        }
        if let expiresAt = oauth.expiresAt {
            // Claude Code writes epoch milliseconds as an integer; keep it that way.
            oauthObject["expiresAt"] = expiresAt == expiresAt.rounded() ? Int(expiresAt) : expiresAt
        }
        raw["claudeAiOauth"] = oauthObject
        return raw
    }

    private func write(_ loaded: LoadedCredentials) -> Bool {
        guard JSONSerialization.isValidJSONObject(loaded.raw),
              let data = try? JSONSerialization.data(withJSONObject: loaded.raw) else {
            Log.error("Claude: could not serialize refreshed credentials; keeping them in memory only")
            return false
        }

        switch loaded.source {
        case .keychain:
            // Unreachable: `isWritable` keeps every refresh path away from the keychain.
            // Kept as a hard stop so no future path can clobber the item's partition list
            // and put Claude Code back to a password prompt on every credential read.
            Log.error("Claude: refusing to write the shared keychain item; keeping tokens in memory only")
            return true
        case .file(let url):
            do {
                try data.write(to: url, options: [.atomic])
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: url.path
                )
                return true
            } catch {
                Log.error("Claude: could not write \(url.path) (\(error.localizedDescription)); will retry, Claude Code may need `/login`")
                return false
            }
        }
    }

    // Whether the in-memory cache may still be used, or the shared store has to be
    // re-read. Deliberately eager (5-minute buffer): re-reading is cheap and picks
    // up a token Claude Code refreshed on its own.
    static func needsRefresh(_ oauth: Credentials.OAuthData?, now: Date = Date()) -> Bool {
        guard let oauth = oauth, let expiresAt = oauth.expiresAt else { return true }
        return now.timeIntervalSince1970 * 1000 + refreshBufferMs >= expiresAt
    }

    // Whether *we* should spend the refresh token. Kept as tight as possible
    // (hard expiry + 30s of slack) because refreshing rotates the token and
    // invalidates the copy Claude Code holds. An unknown expiry is treated as
    // valid: the 401 path refreshes if the token really is dead.
    static func isExpired(_ oauth: Credentials.OAuthData?, now: Date = Date()) -> Bool {
        guard let oauth = oauth, let expiresAt = oauth.expiresAt else { return false }
        return now.timeIntervalSince1970 * 1000 + expiryGraceMs >= expiresAt
    }

    private func refreshedCredentials(from credentials: Credentials) async -> Credentials? {
        var updated = credentials
        guard (try? await refreshToken(credentials: &updated)) != nil else { return nil }
        return updated
    }

    private func refreshToken(credentials: inout Credentials) async throws -> String? {
        guard let refreshToken = credentials.claudeAiOauth?.refreshToken else { return nil }

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "scope": scopes
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            return nil
        }

        struct RefreshResponse: Codable {
            var access_token: String
            var refresh_token: String?
            var expires_in: Int?
        }

        let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)

        credentials.claudeAiOauth?.accessToken = refreshResponse.access_token
        if let newRefresh = refreshResponse.refresh_token {
            credentials.claudeAiOauth?.refreshToken = newRefresh
        }
        if let expiresIn = refreshResponse.expires_in {
            credentials.claudeAiOauth?.expiresAt = Date().timeIntervalSince1970 * 1000 + Double(expiresIn * 1000)
        }

        return refreshResponse.access_token
    }

    /// Builds the usage rows shown for Claude. Shared by both auth paths: the OAuth
    /// token endpoint and the cookie-authed claude.ai web API return the same JSON
    /// shape, so the two must never drift into showing different rows.
    static func usageItems(from usage: UsageResponse) -> [UsageItem] {
        var items: [UsageItem] = []

        if let fiveHour = usage.five_hour, let utilization = fiveHour.utilization {
            let resetDate = Self.parseResetDate(fiveHour.resets_at)
            items.append(UsageItem(
                label: "Session",
                current: utilization,
                limit: 100,
                resetLabel: relativeResetLabel(resetDate),
                resetsAt: resetDate
            ))
        }

        if let sevenDay = usage.seven_day, let utilization = sevenDay.utilization {
            let resetDate = Self.parseResetDate(sevenDay.resets_at)
            items.append(UsageItem(
                label: "Weekly",
                current: utilization,
                limit: 100,
                resetLabel: relativeResetLabel(resetDate),
                resetsAt: resetDate
            ))
        }

        if let sonnet = usage.seven_day_sonnet, let utilization = sonnet.utilization {
            let resetDate = Self.parseResetDate(sonnet.resets_at)
            items.append(UsageItem(
                label: "Sonnet",
                current: utilization,
                limit: 100,
                resetLabel: relativeResetLabel(resetDate),
                resetsAt: resetDate
            ))
        }

        if let opus = usage.seven_day_opus, let utilization = opus.utilization {
            let resetDate = Self.parseResetDate(opus.resets_at)
            items.append(UsageItem(
                label: "Opus",
                current: utilization,
                limit: 100,
                resetLabel: relativeResetLabel(resetDate),
                resetsAt: resetDate
            ))
        }

        if let extraItem = Self.extraCreditsItem(from: usage.extra_usage) {
            items.append(extraItem)
        }
        return items
    }

    static func extraCreditsItem(from extra: UsageResponse.ExtraUsage?) -> UsageItem? {
        guard let extra, extra.is_enabled == true,
              let limitMinor = extra.monthly_limit, limitMinor > 0 else { return nil }
        // The API reports credits in minor units (verified live: 1610/5000 =
        // €16.10 of €50.00) and exposes no currency, so no symbol is shown.
        // Amounts ride in the trailing detail slot (resetLabel) so the row
        // keeps the standard bar + percentage layout.
        let used = (extra.used_credits ?? 0) / 100
        let limit = limitMinor / 100
        return UsageItem(
            label: "Extra credits",
            current: used,
            limit: limit,
            resetLabel: "\(formatCredits(used))/\(formatCredits(limit))",
            kind: .extraUsage
        )
    }

    static func formatCredits(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }

    static func formatDollars(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "$%.0f", value)
            : String(format: "$%.2f", value)
    }

    static func planLabel(from subscriptionType: String?) -> String? {
        guard let type = subscriptionType, !type.isEmpty else { return nil }
        switch type.lowercased() {
        case "max": return "Max"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return type.capitalized
        }
    }

    static func parseResetDate(_ isoString: String?) -> Date? {
        guard let isoString = isoString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString)
    }

}
