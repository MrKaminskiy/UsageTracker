import CryptoKit
import Foundation

/// One Claude Code login on this Mac: a config folder and the account signed in through it.
///
/// Claude Code keeps one login per config folder. `~/.claude` is the default; running it with
/// `CLAUDE_CONFIG_DIR=~/.claude-2` gives a second, fully separate login, so two subscriptions
/// can stay signed in at once and each gets its own card.
struct ClaudeAccount: Equatable, Sendable {
    /// `"claude"` for the default folder, so configs written before multi-account support
    /// keep their pin, order and toggles; `"claude-<8hex>"` for any other folder.
    let providerID: String
    let configDir: URL
    let keychainService: String
    /// Newer CLI versions keep credentials in this file instead of the keychain.
    let credentialsFile: URL
    let projectsDir: URL
    var email: String?
    var accountUuid: String?
    var organizationUuid: String?
    var hasLogin: Bool

    var isDefault: Bool { providerID == "claude" }
    var label: String { email ?? configDir.lastPathComponent }
}

enum ClaudeAccountDiscovery {
    private static let baseService = "Claude Code-credentials"

    /// Claude Code's keychain item for a config folder. A custom `CLAUDE_CONFIG_DIR` gets the
    /// first 8 hex characters of the SHA-256 of its path, NFC-normalized but otherwise hashed
    /// exactly as given — so a trailing slash names a different item. `nil` is the default
    /// folder.
    static func keychainService(forConfigDir path: String?) -> String {
        guard let path else { return baseService }
        return "\(baseService)-\(pathHash(path))"
    }

    static func providerID(forConfigDir path: String?) -> String {
        guard let path else { return "claude" }
        return "claude-\(pathHash(path))"
    }

    private static func pathHash(_ path: String) -> String {
        SHA256.hash(data: Data(path.precomposedStringWithCanonicalMapping.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(8)
            .description
    }

    /// The default account first — always, signed in or not, since it also carries the
    /// claude.ai cookie path — then every other `~/.claude*` folder that has a login, by name.
    /// Folder-first, so keychain items left behind by deleted folders never become accounts.
    /// When one account is signed in through two folders, the later folder is dropped.
    static func discover(
        home: URL,
        fileManager: FileManager = .default,
        itemExists: (String) -> Bool = { keychainItemExists($0) }
    ) -> [ClaudeAccount] {
        let defaultDir = home.appendingPathComponent(".claude")
        var accounts = [account(
            providerID: "claude",
            configDir: defaultDir,
            keychainService: baseService,
            infoFile: home.appendingPathComponent(".claude.json"),
            hasKeychainItem: itemExists(baseService),
            fileManager: fileManager
        )]

        let names = (try? fileManager.contentsOfDirectory(atPath: home.path)) ?? []
        for name in names.sorted() where name.hasPrefix(".claude") && name != ".claude" {
            let dir = home.appendingPathComponent(name)
            guard isDirectory(dir, fileManager: fileManager) else { continue }
            // The item is named after the path as the user exported it, which we can't see;
            // the bare path is the common case, a trailing slash the likely variant.
            let candidates = [dir.path, dir.path + "/"].map { keychainService(forConfigDir: $0) }
            let found = candidates.first(where: itemExists)
            let account = account(
                providerID: providerID(forConfigDir: dir.path),
                configDir: dir,
                keychainService: found ?? candidates[0],
                infoFile: dir.appendingPathComponent(".claude.json"),
                hasKeychainItem: found != nil,
                fileManager: fileManager
            )
            guard account.hasLogin else { continue }
            // Only a signed-in entry claims its account: `.claude.json` can keep naming the
            // account after a logout.
            if let uuid = account.accountUuid,
               accounts.contains(where: { $0.hasLogin && $0.accountUuid == uuid }) { continue }
            accounts.append(account)
        }
        return accounts
    }

    private static func account(
        providerID: String,
        configDir: URL,
        keychainService: String,
        infoFile: URL,
        hasKeychainItem: Bool,
        fileManager: FileManager
    ) -> ClaudeAccount {
        let credentialsFile = configDir.appendingPathComponent(".credentials.json")
        let info = oauthAccount(in: infoFile)
        return ClaudeAccount(
            providerID: providerID,
            configDir: configDir,
            keychainService: keychainService,
            credentialsFile: credentialsFile,
            projectsDir: configDir.appendingPathComponent("projects"),
            email: info?["emailAddress"] as? String,
            accountUuid: info?["accountUuid"] as? String,
            organizationUuid: info?["organizationUuid"] as? String,
            hasLogin: hasKeychainItem || fileManager.fileExists(atPath: credentialsFile.path)
        )
    }

    /// Claude Code's `oauthAccount` object, or nil when the file is missing or unreadable.
    private static func oauthAccount(in file: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: file),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return root["oauthAccount"] as? [String: Any]
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        // fileExists follows symlinks, so a symlinked config folder counts.
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Whether a reading kept from earlier still belongs on its card: the card's folder is still
    /// signed in, to the same account the reading was taken from. Unknown uuids pass, since an
    /// older cache entry or a folder without `.claude.json` can't say. Non-Claude IDs always pass.
    static func isCurrent(providerID: String, accountUuid: String?, accounts: [ClaudeAccount]) -> Bool {
        guard isClaudeProviderID(providerID) else { return true }
        guard let account = accounts.first(where: { $0.providerID == providerID }) else { return false }
        if let stored = accountUuid, let current = account.accountUuid, stored != current { return false }
        return true
    }

    /// Whether the keychain holds an item for `service`. Runs `security` without `-w`: that
    /// reads only the item's attributes, never its secret, so it can't prompt.
    static func keychainItemExists(
        _ service: String,
        tool: URL = URL(fileURLWithPath: "/usr/bin/security"),
        timeout: TimeInterval = 5
    ) -> Bool {
        ClaudeProvider.runTool(tool, arguments: ["find-generic-password", "-s", service], timeout: timeout)?.status == 0
    }
}
