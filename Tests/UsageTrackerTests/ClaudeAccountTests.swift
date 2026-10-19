import Foundation
import Testing
@testable import UsageTracker

@Suite("Claude account naming")
struct ClaudeAccountNamingTests {

    @Test("The default config folder uses Claude Code's unsuffixed keychain item")
    func defaultService() {
        #expect(ClaudeAccountDiscovery.keychainService(forConfigDir: nil) == "Claude Code-credentials")
    }

    // Claude Code names a custom CLAUDE_CONFIG_DIR's item after the first 8 hex chars of the
    // SHA-256 of the folder path, hashed exactly as given.
    @Test("A custom folder's item and provider ID carry Claude Code's path hash")
    func customServiceMatchesClaudeCode() {
        #expect(ClaudeAccountDiscovery.keychainService(forConfigDir: "/Users/test/.claude-2") == "Claude Code-credentials-2601a85c")
        #expect(ClaudeAccountDiscovery.keychainService(forConfigDir: "/Users/test/.claude-2/") == "Claude Code-credentials-56a1affc")
        #expect(ClaudeAccountDiscovery.providerID(forConfigDir: "/Users/test/.claude-2") == "claude-2601a85c")
        #expect(ClaudeAccountDiscovery.providerID(forConfigDir: nil) == "claude")
    }

    // Claude Code normalizes the folder path to NFC before hashing; a path the file system hands
    // back decomposed must still name the same item.
    @Test("Paths are NFC-normalized before hashing, as Claude Code does")
    func normalizesToNFC() {
        let decomposed = "/Users/test/.claude-a\u{0308}"
        #expect(ClaudeAccountDiscovery.keychainService(forConfigDir: decomposed) == "Claude Code-credentials-865e5484")
    }
}

@Suite("Claude account discovery")
struct ClaudeAccountDiscoveryTests {

    /// A throwaway home folder. Callers remove it with `defer`.
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func folder(_ name: String, in home: URL) throws -> URL {
        let url = home.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeAccount(to url: URL, email: String, uuid: String, org: String? = nil) throws {
        var account: [String: String] = ["emailAddress": email, "accountUuid": uuid]
        account["organizationUuid"] = org
        let data = try JSONSerialization.data(withJSONObject: ["oauthAccount": account])
        try data.write(to: url)
    }

    private func service(_ url: URL) -> String {
        ClaudeAccountDiscovery.keychainService(forConfigDir: url.path)
    }

    @Test("Finds the default folder and every signed-in .claude* folder")
    func findsSignedInFolders() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try folder(".claude", in: home)
        try writeAccount(to: home.appendingPathComponent(".claude.json"), email: "a@x", uuid: "U1", org: "O1")
        let second = try folder(".claude-2", in: home)
        try writeAccount(to: second.appendingPathComponent(".claude.json"), email: "b@x", uuid: "U2", org: "O2")
        _ = try folder(".claude-old", in: home)
        try Data("{}".utf8).write(to: home.appendingPathComponent(".claude.json.backup"))

        let signedIn: Set<String> = ["Claude Code-credentials", service(second)]
        let accounts = ClaudeAccountDiscovery.discover(home: home, itemExists: { signedIn.contains($0) })

        #expect(accounts.map(\.providerID) == ["claude", ClaudeAccountDiscovery.providerID(forConfigDir: second.path)])
        #expect(accounts.map(\.email) == ["a@x", "b@x"])
        #expect(accounts.map(\.accountUuid) == ["U1", "U2"])
        #expect(accounts.map(\.organizationUuid) == ["O1", "O2"])
        #expect(accounts.allSatisfy { $0.hasLogin })
        #expect(accounts[1].keychainService == service(second))
        #expect(accounts[1].credentialsFile == second.appendingPathComponent(".credentials.json"))
        #expect(accounts[1].projectsDir == second.appendingPathComponent("projects"))
    }

    @Test("The default account is always listed, even signed out")
    func defaultAlwaysPresent() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let accounts = ClaudeAccountDiscovery.discover(home: home, itemExists: { _ in false })

        #expect(accounts.count == 1)
        #expect(accounts.first?.providerID == "claude")
        #expect(accounts.first?.isDefault == true)
        #expect(accounts.first?.hasLogin == false)
    }

    @Test("A .credentials.json file counts as a login when the folder names its account")
    func credentialsFileIsALogin() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let third = try folder(".claude-3", in: home)
        try Data("{}".utf8).write(to: third.appendingPathComponent(".credentials.json"))
        try writeAccount(to: third.appendingPathComponent(".claude.json"), email: "c@x", uuid: "U3")

        let accounts = ClaudeAccountDiscovery.discover(home: home, itemExists: { _ in false })

        #expect(accounts.map(\.providerID) == ["claude", ClaudeAccountDiscovery.providerID(forConfigDir: third.path)])
        #expect(accounts.last?.hasLogin == true)
    }

    // `cp -R ~/.claude ~/.claude-backup` copies the token file but not `~/.claude.json`, which
    // lives outside the folder. Treating it as an account would poll one account twice and,
    // worse, refresh the copied token — rotating the refresh token the live login still holds.
    @Test("A copied folder with only a token file isn't an account")
    func credentialsFileWithoutAccountIgnored() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let backup = try folder(".claude-backup", in: home)
        try Data("{}".utf8).write(to: backup.appendingPathComponent(".credentials.json"))

        let accounts = ClaudeAccountDiscovery.discover(home: home, itemExists: { _ in false })

        #expect(accounts.map(\.providerID) == ["claude"])
    }

    @Test("A folder exported with a trailing slash is found under the slashed item name")
    func trailingSlashVariant() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let second = try folder(".claude-2", in: home)
        let slashed = ClaudeAccountDiscovery.keychainService(forConfigDir: second.path + "/")

        let accounts = ClaudeAccountDiscovery.discover(home: home, itemExists: { $0 == slashed })

        #expect(accounts.count == 2)
        #expect(accounts.last?.keychainService == slashed)
        #expect(accounts.last?.hasLogin == true)
    }

    @Test("One account signed in through two folders is listed once")
    func dedupesSameAccount() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let second = try folder(".claude-2", in: home)
        let third = try folder(".claude-3", in: home)
        try writeAccount(to: second.appendingPathComponent(".claude.json"), email: "b@x", uuid: "U2")
        try writeAccount(to: third.appendingPathComponent(".claude.json"), email: "b@x", uuid: "U2")

        let customOnly = ClaudeAccountDiscovery.discover(
            home: home, itemExists: { $0 != "Claude Code-credentials" }
        )
        #expect(customOnly.map(\.providerID) == ["claude", ClaudeAccountDiscovery.providerID(forConfigDir: second.path)])

        _ = try folder(".claude", in: home)
        try writeAccount(to: home.appendingPathComponent(".claude.json"), email: "b@x", uuid: "U2")
        let withDefault = ClaudeAccountDiscovery.discover(home: home, itemExists: { _ in true })
        #expect(withDefault.map(\.providerID) == ["claude"])
    }

    // After a logout `~/.claude.json` can still name the account; that must not hide the same
    // account signed in through another folder.
    @Test("A signed-out default doesn't hide the same account signed in elsewhere")
    func signedOutDefaultDoesNotDedupe() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeAccount(to: home.appendingPathComponent(".claude.json"), email: "b@x", uuid: "U2")
        let second = try folder(".claude-2", in: home)
        try writeAccount(to: second.appendingPathComponent(".claude.json"), email: "b@x", uuid: "U2")

        let accounts = ClaudeAccountDiscovery.discover(home: home, itemExists: { $0 == service(second) })

        #expect(accounts.map(\.providerID) == ["claude", ClaudeAccountDiscovery.providerID(forConfigDir: second.path)])
    }

    @Test("Leftover keychain items with no folder are not accounts")
    func ignoresLeftoverItems() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let accounts = ClaudeAccountDiscovery.discover(home: home, itemExists: { _ in true })

        #expect(accounts.map(\.providerID) == ["claude"])
    }

    @Test("Without an email the label falls back to the folder name")
    func labelFallsBackToFolder() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let fourth = try folder(".claude-4", in: home)

        let accounts = ClaudeAccountDiscovery.discover(home: home, itemExists: { $0 == service(fourth) })

        #expect(accounts.last?.label == ".claude-4")
        #expect(accounts.last?.email == nil)
    }
}

@Suite("Claude keychain item existence check")
struct ClaudeKeychainExistenceTests {

    private func tool(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-security-\(UUID().uuidString).sh")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    @Test("Exit status decides: 0 exists, non-zero doesn't, a hung tool doesn't")
    func existenceCheckUsesExitCode() throws {
        let found = try tool("exit 0")
        let missing = try tool("echo 'could not be found' >&2; exit 44")
        let hung = try tool("sleep 5")
        defer { [found, missing, hung].forEach { try? FileManager.default.removeItem(at: $0) } }

        #expect(ClaudeAccountDiscovery.keychainItemExists("x", tool: found))
        #expect(!ClaudeAccountDiscovery.keychainItemExists("x", tool: missing))
        #expect(!ClaudeAccountDiscovery.keychainItemExists("x", tool: hung, timeout: 0.5))
    }
}

@Suite("Claude reading ownership")
struct ClaudeReadingOwnershipTests {

    private func account(_ id: String, uuid: String?) -> ClaudeAccount {
        let dir = URL(fileURLWithPath: "/Users/test/\(id)")
        return ClaudeAccount(
            providerID: id, configDir: dir, keychainService: "s",
            credentialsFile: dir.appendingPathComponent(".credentials.json"),
            projectsDir: dir.appendingPathComponent("projects"),
            email: nil, accountUuid: uuid, organizationUuid: nil, hasLogin: true
        )
    }

    @Test("A reading for a folder that's no longer signed in isn't current")
    func isCurrentDropsUndiscovered() {
        let accounts = [account("claude", uuid: "U1")]
        #expect(!ClaudeAccountDiscovery.isCurrent(providerID: "claude-aaaa1111", accountUuid: nil, accounts: accounts))
        #expect(ClaudeAccountDiscovery.isCurrent(providerID: "codex", accountUuid: nil, accounts: accounts))
        #expect(ClaudeAccountDiscovery.isCurrent(providerID: "claude", accountUuid: nil, accounts: accounts))
    }

    @Test("A reading from a different account than the folder now holds isn't current")
    func isCurrentDropsOtherAccount() {
        let accounts = [account("claude", uuid: "U9")]
        #expect(!ClaudeAccountDiscovery.isCurrent(providerID: "claude", accountUuid: "U1", accounts: accounts))
        #expect(ClaudeAccountDiscovery.isCurrent(providerID: "claude", accountUuid: "U1", accounts: [account("claude", uuid: "U1")]))
        #expect(ClaudeAccountDiscovery.isCurrent(providerID: "claude", accountUuid: nil, accounts: accounts))
    }
}
