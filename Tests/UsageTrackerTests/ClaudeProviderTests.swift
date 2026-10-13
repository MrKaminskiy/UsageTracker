import Testing
import Foundation
@testable import UsageTracker

@Suite("ClaudeProvider credential parsing")
struct ClaudeProviderCredentialsTests {

    // The format Claude Code CLI writes to ~/.claude/.credentials.json,
    // including fields we don't model (scopes, rateLimitTier).
    @Test("Decodes credentials.json format with extra fields")
    func decodesCredentialsFile() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "sk-test-access",
            "refreshToken": "sk-test-refresh",
            "expiresAt": 1778187507488,
            "scopes": ["user:profile", "user:inference"],
            "subscriptionType": "max",
            "rateLimitTier": "default_claude_max_5x"
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let creds = try JSONDecoder().decode(ClaudeProvider.Credentials.self, from: data)

        #expect(creds.claudeAiOauth?.accessToken == "sk-test-access")
        #expect(creds.claudeAiOauth?.refreshToken == "sk-test-refresh")
        #expect(creds.claudeAiOauth?.expiresAt == 1778187507488)
        #expect(creds.claudeAiOauth?.subscriptionType == "max")
    }

    @Test("Decodes minimal credentials with only required fields")
    func decodesMinimalCredentials() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "sk-test"
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let creds = try JSONDecoder().decode(ClaudeProvider.Credentials.self, from: data)

        #expect(creds.claudeAiOauth?.accessToken == "sk-test")
        #expect(creds.claudeAiOauth?.refreshToken == nil)
        #expect(creds.claudeAiOauth?.expiresAt == nil)
    }
}

@Suite("ClaudeProvider token expiry (drives keychain cache reuse)")
struct ClaudeProviderNeedsRefreshTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func oauth(expiresInMs offset: Double?) -> ClaudeProvider.Credentials.OAuthData {
        .init(
            accessToken: "sk-test",
            refreshToken: "sk-refresh",
            expiresAt: offset.map { now.timeIntervalSince1970 * 1000 + $0 },
            subscriptionType: nil
        )
    }

    @Test("Token expiring well beyond the buffer does not need refresh")
    func farFutureExpiry() {
        #expect(!ClaudeProvider.needsRefresh(oauth(expiresInMs: 60 * 60 * 1000), now: now))
    }

    @Test("Token inside the 5-minute buffer needs refresh")
    func withinBuffer() {
        #expect(ClaudeProvider.needsRefresh(oauth(expiresInMs: 4 * 60 * 1000), now: now))
    }

    @Test("Expired token needs refresh")
    func expired() {
        #expect(ClaudeProvider.needsRefresh(oauth(expiresInMs: -1000), now: now))
    }

    @Test("Missing expiry or missing oauth needs refresh")
    func missingData() {
        #expect(ClaudeProvider.needsRefresh(oauth(expiresInMs: nil), now: now))
        #expect(ClaudeProvider.needsRefresh(nil, now: now))
    }

    // isExpired gates spending the refresh token, which rotates it and kills the
    // copy Claude Code holds. It must be strictly tighter than needsRefresh.
    @Test("Token inside the cache buffer but not yet expired is not spent on a refresh")
    func withinBufferIsNotExpired() {
        #expect(!ClaudeProvider.isExpired(oauth(expiresInMs: 4 * 60 * 1000), now: now))
    }

    @Test("Expired token, and token inside the 30s grace, count as expired")
    func expiredIsExpired() {
        #expect(ClaudeProvider.isExpired(oauth(expiresInMs: -1000), now: now))
        #expect(ClaudeProvider.isExpired(oauth(expiresInMs: 10 * 1000), now: now))
    }

    @Test("Unknown expiry is not refreshed preemptively; the 401 path handles it")
    func unknownExpiryIsNotExpired() {
        #expect(!ClaudeProvider.isExpired(oauth(expiresInMs: nil), now: now))
        #expect(!ClaudeProvider.isExpired(nil, now: now))
    }
}

// Regression: re-encoding our own Credentials struct into the shared store used to
// drop every key we don't model, breaking Claude Code's session and forcing a
// daily `/login`.
@Suite("ClaudeProvider write-back preserves Claude Code's fields")
struct ClaudeProviderMergeTests {

    private let raw: [String: Any] = [
        "claudeAiOauth": [
            "accessToken": "old-access",
            "refreshToken": "old-refresh",
            "expiresAt": 1_778_187_507_488,
            "scopes": ["user:profile", "user:inference"],
            "subscriptionType": "max",
            "rateLimitTier": "default_claude_max_5x"
        ] as [String: Any],
        "someFutureTopLevelKey": "keep me"
    ]

    private func merged() -> [String: Any] {
        ClaudeProvider.merging(
            .init(
                accessToken: "new-access",
                refreshToken: "new-refresh",
                expiresAt: 1_778_200_000_000,
                subscriptionType: "max"
            ),
            into: raw
        )
    }

    @Test("Token fields are replaced")
    func replacesTokens() throws {
        let oauth = try #require(merged()["claudeAiOauth"] as? [String: Any])
        #expect(oauth["accessToken"] as? String == "new-access")
        #expect(oauth["refreshToken"] as? String == "new-refresh")
    }

    @Test("Unmodelled fields survive the round-trip")
    func keepsUnknownFields() throws {
        let result = merged()
        let oauth = try #require(result["claudeAiOauth"] as? [String: Any])
        #expect(oauth["scopes"] as? [String] == ["user:profile", "user:inference"])
        #expect(oauth["rateLimitTier"] as? String == "default_claude_max_5x")
        #expect(result["someFutureTopLevelKey"] as? String == "keep me")
    }

    @Test("expiresAt stays an integer, as Claude Code writes it")
    func expiryStaysInteger() throws {
        let oauth = try #require(merged()["claudeAiOauth"] as? [String: Any])
        #expect(oauth["expiresAt"] as? Int == 1_778_200_000_000)

        let data = try JSONSerialization.data(withJSONObject: merged())
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("1778200000000"))
        #expect(!text.contains("1778200000000.0"))
    }

    // The store is re-read right before writing: Claude Code may have logged in
    // while our refresh request was in flight, and its tokens would then be newer
    // than ours. Overwriting them would cost the user yet another /login.
    @Test("Store still holding the token we spent is safe to overwrite")
    func storeUnchanged() {
        let stored = ClaudeProvider.Credentials.OAuthData(
            accessToken: "old-access", refreshToken: "old-refresh",
            expiresAt: nil, subscriptionType: nil
        )
        #expect(!ClaudeProvider.storeMovedOn(stored, spentRefreshToken: "old-refresh"))
    }

    @Test("Store holding a different token means Claude Code moved on")
    func storeChangedUnderUs() {
        let relogged = ClaudeProvider.Credentials.OAuthData(
            accessToken: "cli-access", refreshToken: "cli-refresh",
            expiresAt: nil, subscriptionType: nil
        )
        #expect(ClaudeProvider.storeMovedOn(relogged, spentRefreshToken: "old-refresh"))
        #expect(ClaudeProvider.storeMovedOn(nil, spentRefreshToken: "old-refresh"))
        #expect(!ClaudeProvider.storeMovedOn(nil, spentRefreshToken: nil))
    }

    @Test("Merged object is JSON-serializable and re-decodes")
    func roundTrips() throws {
        let data = try JSONSerialization.data(withJSONObject: merged())
        let creds = try JSONDecoder().decode(ClaudeProvider.Credentials.self, from: data)
        #expect(creds.claudeAiOauth?.accessToken == "new-access")
        #expect(creds.claudeAiOauth?.expiresAt == 1_778_200_000_000)
    }
}

@Suite("ClaudeProvider extra credits and plan label")
struct ClaudeProviderExtrasTests {

    // API reports credits in minor units (cents): verified live 2026-07-08 —
    // raw used=1610 limit=5000 corresponds to €16.10 of €50.00 on claude.ai.
    // No currency is exposed, so the amounts render without a symbol; they go
    // in the trailing detail slot (resetLabel) so the row keeps the normal
    // bar + percentage layout.
    @Test("Extra credits item converts minor units; amounts in trailing detail slot")
    func extraCreditsMapping() {
        let extra = ClaudeProvider.UsageResponse.ExtraUsage(is_enabled: true, used_credits: 1610, monthly_limit: 5000)
        let item = ClaudeProvider.extraCreditsItem(from: extra)
        #expect(item != nil)
        #expect(item?.label == "Extra credits")
        #expect(item?.kind == .extraUsage)
        #expect(item?.resetLabel == "16.10/50")
        #expect(abs((item?.percentage ?? 0) - 32.2) < 0.01)
    }

    @Test("Extra credits hidden when disabled, missing, or zero limit")
    func extraCreditsHidden() {
        #expect(ClaudeProvider.extraCreditsItem(from: nil) == nil)
        #expect(ClaudeProvider.extraCreditsItem(from: .init(is_enabled: false, used_credits: 5, monthly_limit: 50)) == nil)
        #expect(ClaudeProvider.extraCreditsItem(from: .init(is_enabled: true, used_credits: 5, monthly_limit: 0)) == nil)
        #expect(ClaudeProvider.extraCreditsItem(from: .init(is_enabled: true, used_credits: 5, monthly_limit: nil)) == nil)
    }

    @Test("Whole credit amounts drop decimals")
    func extraCreditsWhole() {
        let extra = ClaudeProvider.UsageResponse.ExtraUsage(is_enabled: true, used_credits: 1200, monthly_limit: 5000)
        #expect(ClaudeProvider.extraCreditsItem(from: extra)?.resetLabel == "12/50")
    }

    @Test("Plan label mapping")
    func planLabels() {
        #expect(ClaudeProvider.planLabel(from: "max") == "Max")
        #expect(ClaudeProvider.planLabel(from: "pro") == "Pro")
        #expect(ClaudeProvider.planLabel(from: "enterprise") == "Enterprise")
        #expect(ClaudeProvider.planLabel(from: "some_new_tier") == "Some_new_tier".capitalized)
        #expect(ClaudeProvider.planLabel(from: nil) == nil)
        #expect(ClaudeProvider.planLabel(from: "") == nil)
    }
}

// Field shapes follow the zod schema Claude Code 2.1.296 applies to /api/oauth/usage.
@Suite("ClaudeProvider server meter rows and credit buckets")
struct ClaudeProviderLimitsTests {

    private func items(_ json: String) throws -> [UsageItem] {
        let data = try #require(json.data(using: .utf8))
        let usage = try JSONDecoder().decode(ClaudeProvider.UsageResponse.self, from: data)
        return ClaudeProvider.usageItems(from: usage)
    }

    @Test("Per-model weekly rows from limits[] become their own rows")
    func modelScopedRows() throws {
        let rows = try items("""
        {
          "five_hour": { "utilization": 12, "resets_at": "2026-10-13T16:30:00Z" },
          "seven_day": { "utilization": 30, "resets_at": "2026-10-18T21:00:00Z" },
          "seven_day_sonnet": null,
          "seven_day_opus": null,
          "limits": [
            { "kind": "session", "group": "session", "percent": 12, "resets_at": "2026-10-13T16:30:00Z",
              "severity": "normal", "is_active": true, "scope": null },
            { "kind": "weekly_all", "group": "weekly", "percent": 30, "resets_at": "2026-10-18T21:00:00Z",
              "severity": "normal", "is_active": false, "scope": null },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 64, "resets_at": "2026-10-18T21:00:00Z",
              "severity": "warning", "is_active": false, "scope": { "model": { "display_name": "Fable" } } }
          ]
        }
        """)
        #expect(rows.map(\.label) == ["Session", "Weekly", "Fable"])
        #expect(rows[2].current == 64)
        #expect(rows[2].resetsAt != nil)
    }

    @Test("A limits[] row for a model the legacy fields already cover is not shown twice")
    func legacyModelRowWins() throws {
        let rows = try items("""
        {
          "seven_day_sonnet": { "utilization": 5, "resets_at": null },
          "limits": [
            { "kind": "weekly_scoped", "percent": 5, "resets_at": null, "scope": { "model": { "display_name": "Sonnet" } } }
          ]
        }
        """)
        #expect(rows.map(\.label) == ["Sonnet"])
    }

    @Test("Surface-scoped and unscoped rows are left to the dedicated fields")
    func onlyModelScopedRows() throws {
        let rows = try items("""
        {
          "limits": [
            { "kind": "weekly_scoped", "percent": 40, "resets_at": null, "scope": { "surface": { "display_name": "Cowork" } } },
            { "kind": "session", "percent": 10, "resets_at": null }
          ]
        }
        """)
        #expect(rows.isEmpty)
    }

    @Test("A malformed limits[] row does not fail the whole response")
    func malformedRowTolerated() throws {
        let rows = try items("""
        {
          "five_hour": { "utilization": 7, "resets_at": null },
          "limits": [
            { "kind": "weekly_scoped", "percent": "lots", "scope": { "model": "Fable" } },
            { "kind": "weekly_scoped", "percent": 20, "resets_at": null, "scope": { "model": { "display_name": "Fable" } } }
          ]
        }
        """)
        #expect(rows.map(\.label) == ["Session", "Fable"])
    }

    @Test("Null, non-object, or non-array limits never fail the response")
    func lossyLimits() throws {
        let nullAndJunk = try items("""
        { "five_hour": { "utilization": 7, "resets_at": null },
          "limits": [null, 42, "x", { "kind": "weekly_scoped", "percent": 20, "resets_at": null,
                                      "scope": { "model": { "display_name": "Fable" } } }] }
        """)
        #expect(nullAndJunk.map(\.label) == ["Session", "Fable"])

        let notAnArray = try items("""
        { "five_hour": { "utilization": 7, "resets_at": null }, "limits": { "kind": "weekly_scoped" } }
        """)
        #expect(notAnArray.map(\.label) == ["Session"])
    }

    @Test("Legacy model rows absorb versioned names; surfaces disambiguate rows")
    func dedupeAndSurfaces() throws {
        let rows = try items("""
        { "seven_day_sonnet": { "utilization": 5, "resets_at": null },
          "limits": [
            { "kind": "weekly_scoped", "percent": 5, "scope": { "model": { "display_name": "Claude Sonnet 4.5" } } },
            { "kind": "weekly_scoped", "percent": 30, "scope": { "model": { "display_name": "Fable" } } },
            { "kind": "weekly_scoped", "percent": 60, "scope": { "model": { "display_name": "Fable" },
                                                                 "surface": { "display_name": "Cowork" } } }
          ] }
        """)
        #expect(rows.map(\.label) == ["Sonnet", "Fable", "Fable · Cowork"])
    }

    @Test("Claude Code and Cowork credit bucket")
    func coworkCredit() throws {
        let rows = try items("""
        { "cinder_cove": { "utilization": 25, "resets_at": "2026-11-01T00:00:00Z" } }
        """)
        #expect(rows.map(\.label) == ["Code & Cowork"])
        #expect(rows[0].current == 25)
    }

    @Test("Dollar credit uses the server label and shows dollars")
    func dollarCredit() throws {
        let labelled = try items("""
        { "wattle_ember": { "utilization": 40, "resets_at": null, "label": "Team budget",
                            "limit_dollars": 50, "used_dollars": 20, "remaining_dollars": 30 } }
        """)
        #expect(labelled.map(\.label) == ["Team budget"])
        #expect(labelled[0].resetLabel == "$20/$50")
        #expect(labelled[0].kind == .extraUsage)

        let unlabelled = try items("""
        { "wattle_ember": { "utilization": 40, "resets_at": null } }
        """)
        #expect(unlabelled.map(\.label) == ["Credit"])
    }

    @Test("Extra credits show the currency when the response names one")
    func extraCreditsCurrency() throws {
        let rows = try items("""
        { "extra_usage": { "is_enabled": true, "monthly_limit": 5000, "used_credits": 1610,
                           "utilization": 32.2, "currency": "EUR", "disabled_reason": null } }
        """)
        #expect(rows.first?.resetLabel == "€16.10/€50")
        // Zero-decimal currencies have no minor unit; Claude Code doesn't divide them.
        let yen = try items("""
        { "extra_usage": { "is_enabled": true, "monthly_limit": 5000, "used_credits": 1610, "currency": "JPY" } }
        """)
        #expect(yen.first?.resetLabel == "¥1610/¥5000")
        #expect(ClaudeProvider.currencySymbol(for: "usd") == "$")
        #expect(ClaudeProvider.currencySymbol(for: nil) == nil)
        #expect(ClaudeProvider.currencySymbol(for: "euro") == nil)
    }

    // Verbatim claude.ai /usage response captured 2026-10-13 (Max plan). Pins the live
    // shape: microsecond timestamps, codename buckets, limits[], and the product breakdown.
    @Test("Live 2026-10-13 response: rows and this week's usage by product")
    func liveResponse() throws {
        let json = """
        {
         "five_hour": {
          "utilization": 33.0,
          "resets_at": "2026-10-13T16:30:00.837398+00:00",
          "limit_dollars": null,
          "used_dollars": null,
          "remaining_dollars": null,
          "locked_reason": null
         },
         "seven_day": {
          "utilization": 32.0,
          "resets_at": "2026-10-18T21:00:00.837425+00:00",
          "limit_dollars": null,
          "used_dollars": null,
          "remaining_dollars": null,
          "locked_reason": null
         },
         "seven_day_oauth_apps": null,
         "seven_day_opus": null,
         "seven_day_sonnet": null,
         "seven_day_cowork": null,
         "seven_day_omelette": null,
         "tangelo": null,
         "iguana_necktie": {
          "utilization": 1.8519148000000003,
          "resets_at": "2026-11-05T07:59:00+00:00",
          "limit_dollars": 250,
          "used_dollars": 4.629787,
          "remaining_dollars": 245.370213,
          "locked_reason": null
         },
         "omelette_promotional": null,
         "nimbus_quill": null,
         "cinder_cove": null,
         "copper_kite": null,
         "brass_thimble": null,
         "harbor_lantern": null,
         "wattle_ember": null,
         "amber_ladder": null,
         "amber_cistern": null,
         "juniper_tide": null,
         "cedar_ember": null,
         "amber_gauge": null,
         "extra_usage": {
          "is_enabled": false,
          "monthly_limit": null,
          "used_credits": null,
          "utilization": null,
          "currency": null,
          "decimal_places": null,
          "disabled_reason": null,
          "user_disabled": true,
          "spend_limit_reached": false,
          "credits_ever_enabled": true,
          "daily": null,
          "weekly": null
         },
         "limits": [
          {
           "kind": "session",
           "group": "session",
           "percent": 33,
           "severity": "normal",
           "resets_at": "2026-10-13T16:30:00.837398+00:00",
           "scope": null,
           "is_active": true
          },
          {
           "kind": "weekly_all",
           "group": "weekly",
           "percent": 32,
           "severity": "normal",
           "resets_at": "2026-10-18T21:00:00.837425+00:00",
           "scope": null,
           "is_active": false
          },
          {
           "kind": "weekly_scoped",
           "group": "weekly",
           "percent": 0,
           "severity": "normal",
           "resets_at": "2026-10-18T21:00:00+00:00",
           "scope": {
            "model": {
             "id": null,
             "display_name": "Fable"
            },
            "surface": null
           },
           "is_active": false
          }
         ],
         "spend": {
          "used": {
           "amount_minor": 0,
           "currency": "USD",
           "exponent": 2
          },
          "limit": null,
          "percent": 0,
          "severity": "normal",
          "enabled": false,
          "disabled_reason": null,
          "cap": null,
          "balance": null,
          "auto_reload": null,
          "disclaimer": "Usage credits cover you when you hit your plan limits. [Learn more](https://support.claude.com/articles/12429409)",
          "can_purchase_credits": true,
          "can_toggle": true
         },
         "member_dashboard_available": false,
         "seven_day_breakdown": {
          "as_of": "2026-10-13T14:06:05.902290+00:00",
          "window_started_at": "2026-10-11T21:00:00.837425+00:00",
          "rows": [
           {
            "key": "claude_code",
            "display_name": "Claude Code",
            "percent": 76
           },
           {
            "key": "chat",
            "display_name": "Chats",
            "percent": 4
           },
           {
            "key": "cowork",
            "display_name": "Cowork",
            "percent": 20
           },
           {
            "key": "other",
            "display_name": "Other",
            "percent": 0
           }
          ]
         },
         "weekly_scoped_shares": [
          {
           "limit_index": 2,
           "used_percent_of_weekly": 0,
           "allowance_percent_of_weekly": 50
          }
         ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let usage = try JSONDecoder().decode(ClaudeProvider.UsageResponse.self, from: data)
        let rows = ClaudeProvider.usageItems(from: usage)
        #expect(rows.map(\.label) == ["Session", "Weekly", "Fable"])
        #expect(rows.map(\.current) == [33, 32, 0])
        #expect(rows.allSatisfy { $0.resetsAt != nil })

        let shares = ClaudeProvider.productShares(from: usage)
        #expect(shares.map(\.name) == ["Claude Code", "Chats", "Cowork", "Other"])
        #expect(shares.map(\.share) == [76, 4, 20, 0])
    }
}

// The keychain is read through /usr/bin/security (see ClaudeProvider.loadFromKeychain);
// these drive that reader with stand-in tools instead of the real keychain.
@Suite("ClaudeProvider keychain read via the security tool")
struct ClaudeProviderSecurityToolTests {

    private func tool(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-security-\(UUID().uuidString).sh")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    @Test("Returns the password without the trailing newline")
    func readsPassword() throws {
        let url = try tool(#"printf '{"claudeAiOauth":{"accessToken":"t"}}\n'"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try #require(ClaudeProvider.readGenericPassword(service: "x", tool: url))
        #expect(String(decoding: data, as: UTF8.self) == #"{"claudeAiOauth":{"accessToken":"t"}}"#)
    }

    @Test("A missing item (non-zero exit) reads as nil")
    func missingItem() throws {
        let url = try tool("echo 'could not be found' >&2; exit 44")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ClaudeProvider.readGenericPassword(service: "x", tool: url) == nil)
    }

    @Test("A tool stuck on a dialog is abandoned at the timeout")
    func timesOut() throws {
        let url = try tool("sleep 30")
        defer { try? FileManager.default.removeItem(at: url) }
        let start = Date()
        #expect(ClaudeProvider.readGenericPassword(service: "x", tool: url, timeout: 0.5) == nil)
        // Generous bound: parallel test load slows process spawns; a hang would take 30s.
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test("Output larger than the pipe buffer is read in full")
    func largeOutput() throws {
        let url = try tool("head -c 200000 /dev/zero | tr '\\\\0' 'a'")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try #require(ClaudeProvider.readGenericPassword(service: "x", tool: url))
        #expect(data.count == 200_000)
    }

    // Captured from a real `security -w` (throwaway keychain): {"k":"café"}
    @Test("Hex output for non-printable passwords is decoded back to JSON")
    func hexOutput() throws {
        let url = try tool("printf '7b226b223a22636166c3a9227d\\n'")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try #require(ClaudeProvider.readGenericPassword(service: "x", tool: url))
        #expect(String(decoding: data, as: UTF8.self) == #"{"k":"café"}"#)
        // Plain JSON passes through untouched.
        #expect(ClaudeProvider.hexDecodedIfNeeded(Data(#"{"a":1}"#.utf8)) == Data(#"{"a":1}"#.utf8))
    }

    @Test("A tool that ignores SIGTERM is killed, not waited on")
    func ignoresTerm() throws {
        let url = try tool("trap '' TERM; sleep 20")
        defer { try? FileManager.default.removeItem(at: url) }
        let start = Date()
        #expect(ClaudeProvider.readGenericPassword(service: "x", tool: url, timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test("A child holding stdout open past the tool's exit doesn't stall the read")
    func lingeringChild() throws {
        let url = try tool("(sleep 20) & printf ok")
        defer { try? FileManager.default.removeItem(at: url) }
        let start = Date()
        _ = ClaudeProvider.readGenericPassword(service: "x", tool: url)
        #expect(Date().timeIntervalSince(start) < 10)
    }
}
