# Multiple Claude Accounts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Claude Code account signed in on the Mac, one per config folder (`~/.claude`, `~/.claude-2`, …), gets its own full Claude card, Settings page, and pinnable rows. An idle account keeps showing its last numbers, marked with their age.

**Architecture:** A pure discovery step (`ClaudeAccountDiscovery`) turns config folders into `ClaudeAccount` values. `AppState` keeps one `ClaudeProvider` actor per account, keyed by a provider ID derived from the folder. The default folder keeps the ID `claude`, so existing config keeps working. Stale and reset handling is added to the existing carry-forward and cache paths, scoped to Claude IDs.

**Tech Stack:** Swift 6 tools, SwiftUI/AppKit, macOS 14+, Swift Testing, CryptoKit (system framework; no new dependencies).

**Spec:** `docs/superpowers/specs/2026-10-19-multiple-claude-accounts-design.md`

## Global Constraints

- **Keychain is read-only.** Never write to or refresh any `Claude Code-credentials*` keychain item. Read secrets only with `/usr/bin/security find-generic-password -s <svc> -w`. Check whether an item exists with the same command without `-w`, which reads no secret and never prompts.
- **Keychain service names.**
  - The default folder uses `Claude Code-credentials`.
  - A custom folder uses `Claude Code-credentials-` plus the first 8 lowercase hex characters of SHA-256 of the folder's path string (UTF-8, exactly as given).
  - Test vector: `/Users/test/.claude-2` → `2601a85c`. With a trailing slash, `/Users/test/.claude-2/` → `56a1affc`.
- **Account info file.** The default folder's info is in `~/.claude.json`. A custom folder's is in `<folder>/.claude.json`. Read the fields `oauthAccount.emailAddress`, `oauthAccount.accountUuid`, and `oauthAccount.organizationUuid`.
- **Provider IDs.** The default account's provider ID stays exactly `"claude"`. A custom folder's ID is `"claude-" + <8 hex>`, the same suffix as its keychain service.
- **Where accounts are looked for.** Discovery looks at `~/.claude` (always) plus directories directly in the home folder whose name starts with `.claude` (other than `.claude` itself). Nothing else is searched.
- **Request load.** At most one usage request per account per refresh. The refresh interval is unchanged.
- **Copy, exact text:**
  - Card title with one Claude account: `Claude`. With two or more: `Claude · <name>`.
  - Stale marker: `as of 25m ago`, `as of 9h ago`, `as of 3d ago`.
  - A row whose reset time passed: `reset`.
  - Shared stats with two or more accounts: `Est. API cost, all accounts`, `Last 24 hours on this Mac, all accounts`, `Today, all accounts`.
- **How long readings are kept.** A Claude reading is kept for 30 days (`UsageCache.claudeMaxAge`). Every other provider keeps its 24h `UsageCache.maxAge`.
- **Test rules.**
  - Use Swift Testing (`import Testing`, `@Test`, `#expect`).
  - A suite that calls `AppState` statics is marked `@MainActor`.
  - Static helpers on SwiftUI Views are `nonisolated`.
  - Never stamp fixtures with `Date()`. Use a fixed `now`, like `UsageCacheTests` does.
- **Where the work happens.** Work in a git worktree on the branch `feat/multi-claude-accounts` (see superpowers:using-git-worktrees). Run `make test` before every commit.

## Review Focus

1. **Trailing slash.** A folder exported with a trailing slash (`CLAUDE_CONFIG_DIR=$HOME/.claude-2/`) is still found. Its keychain item is named after the slashed path. Test: Task 1, `trailingSlashVariant`.
2. **Logged-out folder.** If `~/.claude-2` logs out, its card disappears on the next refresh instead of living on as a 30-day stale card. Test: Task 4, `reconcileDropsUndiscovered`.
3. **Folder signed in to a different account.** If `~/.claude` signs in to another account, its old cached numbers never show under the new account. Test: Task 4, `reconcileDropsOtherAccount`.
4. **Same account in two folders.** One account signed in through two folders shows as one card, not two identical ones. Test: Task 1, `dedupesSameAccount`.
5. **Upgrading from 1.5.1.** The existing `config.json` decodes, and its pin on `claude` / `Weekly`, its order, and its toggles survive. The new account is inserted right after `claude`. Test: Task 4, `upgradesConfig151`.

---

### Task 1: Account discovery

**Files:**
- Create: `Sources/UsageTracker/Providers/ClaudeAccount.swift`
- Modify: `Sources/UsageTracker/Providers/ClaudeProvider.swift:340-382`. Extract the process, timeout, and pipe-drain logic of `readGenericPassword` into a shared helper so the existence check reuses it.
- Test: `Tests/UsageTrackerTests/ClaudeAccountTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct ClaudeAccount: Equatable, Sendable {
      let providerID: String          // "claude" or "claude-<8hex>"
      let configDir: URL
      let keychainService: String
      let credentialsFile: URL        // configDir/.credentials.json
      let projectsDir: URL            // configDir/projects
      var email: String?
      var accountUuid: String?
      var organizationUuid: String?
      var hasLogin: Bool
      var isDefault: Bool { providerID == "claude" }
      var label: String { email ?? configDir.lastPathComponent }
  }
  enum ClaudeAccountDiscovery {
      static func keychainService(forConfigDir path: String?) -> String   // nil = default folder
      static func providerID(forConfigDir path: String?) -> String
      static func discover(home: URL, fileManager: FileManager = .default,
                           itemExists: (String) -> Bool = { keychainItemExists($0) }) -> [ClaudeAccount]
      static func keychainItemExists(_ service: String,
                                     tool: URL = URL(fileURLWithPath: "/usr/bin/security"),
                                     timeout: TimeInterval = 5) -> Bool
  }
  ```
- **What `discover` returns, in order:**
  - The default account always comes first, with or without a login.
  - Then each custom folder that has a login, sorted by folder name.
  - When two entries share an `accountUuid`, the later one is dropped.
- **What counts as a login:** `itemExists(service)` is true, or `credentialsFile` exists.
- **Trailing slash:** for each custom folder, try the service for `path`, then for `path + "/"`. The first one that exists becomes `keychainService`.

- [ ] **Step 1: Write the failing tests** in `ClaudeAccountTests.swift`. Use a temp `home` made of real folders and files. In the JSON below, `<fixtureJSON>` means `{"oauthAccount":{"emailAddress":E,"accountUuid":U,"organizationUuid":O}}`.

```swift
@Test func defaultService() { #expect(ClaudeAccountDiscovery.keychainService(forConfigDir: nil) == "Claude Code-credentials") }
@Test func customServiceMatchesClaudeCode() {
    #expect(ClaudeAccountDiscovery.keychainService(forConfigDir: "/Users/test/.claude-2") == "Claude Code-credentials-2601a85c")
    #expect(ClaudeAccountDiscovery.providerID(forConfigDir: "/Users/test/.claude-2") == "claude-2601a85c")
    #expect(ClaudeAccountDiscovery.providerID(forConfigDir: nil) == "claude")
}
@Test func findsSignedInFolders() {
    // home: .claude/, .claude.json (a@x, U1, O1), .claude-2/.claude.json (b@x, U2, O2),
    //       .claude-old/ (no login), .claude.json.backup (a file)
    // itemExists: true for the default service and for the service of home/.claude-2
    let accounts = ClaudeAccountDiscovery.discover(home: home, itemExists: exists)
    #expect(accounts.map(\.providerID) == ["claude", ClaudeAccountDiscovery.providerID(forConfigDir: home.appendingPathComponent(".claude-2").path)])
    #expect(accounts.map(\.email) == ["a@x", "b@x"])
    #expect(accounts.map(\.organizationUuid) == ["O1", "O2"])
    #expect(accounts.allSatisfy(\.hasLogin))
}
@Test func defaultAlwaysPresent()      // empty home, itemExists false → one account, providerID "claude", hasLogin false
@Test func credentialsFileIsALogin()   // .claude-3/.credentials.json exists, itemExists false → .claude-3 included, hasLogin true
@Test func trailingSlashVariant()      // itemExists true only for keychainService(forConfigDir: path + "/") → included; account.keychainService == that slashed service
@Test func dedupesSameAccount()        // .claude-2 and .claude-3 both U2 → only .claude-2; default U2 plus .claude-2 U2 → only "claude"
@Test func ignoresLeftoverItems()      // itemExists always true, no custom folders → only "claude"
@Test func labelFallsBackToFolder()    // .claude-4 signed in, no .claude.json → label == ".claude-4"
@Test func existenceCheckUsesExitCode() // fake tool scripts (same helper as ClaudeProviderSecurityToolTests): "exit 0" → true, "exit 44" → false, "sleep 5" with timeout 0.5 → false
```

- [ ] **Step 2: Run them and check they fail.** Run `swift test --filter ClaudeAccountTests`. Expected: a compile failure, "cannot find 'ClaudeAccountDiscovery'".
- [ ] **Step 3: Implement `ClaudeAccount.swift`.**
  - Hash with `CryptoKit.SHA256` on `Data(path.utf8)`; take the hex prefix of length 8.
  - Treat a directory entry as a candidate only if it is a directory, resolving symlinks for that check.
  - Read `oauthAccount` with `JSONSerialization`. A missing or unreadable file gives nil fields, not a throw.
  - `keychainItemExists` runs `find-generic-password -s <svc>` with no `-w`, through the helper you extract from `readGenericPassword`. It returns `true` only when the exit status is 0, and `false` when it times out.
- [ ] **Step 4: Run the tests and check they pass.** Run `swift test --filter ClaudeAccountTests` (expected: PASS), then `make test` (expected: all pass; the existing `ClaudeProviderSecurityToolTests` must still pass).
- [ ] **Step 5: Commit.** `git commit -m "feat(claude): discover signed-in Claude Code config folders"`

---

### Task 2: Stale Claude readings survive and show "reset"

**Files:**
- Modify: `Sources/UsageTracker/Models.swift`, `Sources/UsageTracker/UsageCache.swift`, and `Sources/UsageTracker/App.swift`, where `carriedForward` lives (around line 452).
- Test: `Tests/UsageTrackerTests/UsageCacheTests.swift`, `Tests/UsageTrackerTests/ModelsTests.swift`

**Interfaces:**
- Produces:
  - `func isClaudeProviderID(_ id: String) -> Bool`, a global in `Models.swift`. True for `"claude"` and for IDs with the prefix `"claude-"`.
  - Changes to `Provider`:
    - `name` becomes `var`.
    - New `var accountLabel: String? = nil`.
    - New `var accountUuid: String? = nil`.
  - `UsageItem.markedReset() -> UsageItem`. Keeps the label, limit, `resetsAt`, `pinKey`, and `kind`. Sets `current: 0` and `resetLabel: "reset"`.
  - `AppConfig.claudeAccountNames: [String: String]? = nil`.
  - `UsageCache.CachedProvider` gains `accountLabel: String?` and `accountUuid: String?`. Both are optional, so cache files written by 1.5.1 still decode.
  - `UsageCache.claudeMaxAge: TimeInterval = 30 * 24 * 60 * 60`.
  - `UsageCache.maxAge(forProviderID:) -> TimeInterval`. Returns `claudeMaxAge` for Claude IDs and `maxAge` otherwise.
- **The rule:** this applies in `UsageCache.restore`, `UsageCache.merging` (housekeeping), and `AppState.carriedForward`.
  - Each provider ages out at `maxAge(forProviderID:)`.
  - For a Claude ID, an item whose `resetsAt <= now` becomes `item.markedReset()` instead of being dropped.
  - Non-Claude behavior is unchanged.
  - `accountLabel` and `accountUuid` survive the save/restore round trip and carry-forward.

- [ ] **Step 1: Write the failing tests.** Reuse the fixed `now` and the `provider(id:fetchedAt:items:)` helper already in `UsageCacheTests`.

```swift
@Test func claudePastResetRestoresAsReset() {
    // claude, fetched now-2h, item Weekly current 40 / limit 100, resetsAt now-1h
    let item = try #require(UsageCache.restore(snapshot, now: now)?.providers.first?.items.first)
    #expect(item.percentage == 0); #expect(item.resetLabel == "reset")
}
@Test func extraAccountIDIsTreatedAsClaude()  // same as above with id "claude-2601a85c"
@Test func otherProviderPastResetStillDropped() // id "codex", same item → restore returns nil
@Test func claudeKeptThreeDays()              // claude fetched now-3d, resetsAt now+2d → restored; codex fetched now-25h → gone
@Test func claudeRetiredAfterThirtyDays()     // claude fetched now-31d → restore returns nil
@Test func decodes151Cache()                  // literal JSON with no accountLabel/accountUuid keys decodes; restored accountUuid == nil
@Test func accountFieldsRoundTrip()           // merging(...) a provider with accountLabel "b@x", accountUuid "U2" → restore → same values
@MainActor @Test func carriedForwardMarksClaudeReset() // AppState.carriedForward on a claude provider fetched now-30h, item resetsAt now-1h → kept, resetLabel "reset"
@MainActor @Test func markedResetIsStable()   // carrying an already-reset item again leaves it at 0% / "reset"
// ModelsTests
@Test func claudeIDs() { #expect(isClaudeProviderID("claude")); #expect(isClaudeProviderID("claude-2601a85c")); #expect(!isClaudeProviderID("codex")); #expect(!isClaudeProviderID("claudette")) }
@Test func decodes151Config()                 // config.json literal without claudeAccountNames decodes; claudeAccountNames == nil
```

- [ ] **Step 2: Run them and check they fail.** Run `swift test --filter "UsageCache|Models"`. Expected: a compile failure on `markedReset` and `isClaudeProviderID`.
- [ ] **Step 3: Implement the interfaces above.** In `carriedForward`, an item made reset keeps `resetLabel: "reset"`. Don't recompute it from `relativeResetLabel`, which returns nil for a past date.
- [ ] **Step 4: Run the tests and check they pass.** Run `make test`. Expected: all pass, including the existing `UsageCache` and carry-forward tests.
- [ ] **Step 5: Commit.** `git commit -m "feat(cache): keep idle Claude readings up to 30 days, show elapsed windows as reset"`

---

### Task 3: One `ClaudeProvider` per account, cookie bound to its account

**Files:**
- Modify: `Sources/UsageTracker/Providers/ClaudeProvider.swift`, `Sources/UsageTracker/Providers/ClaudeWebProvider.swift`
- Modify: `Sources/UsageTracker/Providers/ClaudeInsightsAnalyzer.swift:241-274`
- Test: `Tests/UsageTrackerTests/ClaudeWebProviderTests.swift`, `Tests/UsageTrackerTests/ClaudeProviderTests.swift`, `Tests/UsageTrackerTests/ClaudeInsightsAnalyzerTests.swift`

**Interfaces:**
- Consumes: `ClaudeAccount` (Task 1); `Provider.accountLabel` and `Provider.accountUuid` (Task 2).
- Produces:
  ```swift
  // ClaudeWebProvider
  enum CookiePolicy: Equatable, Sendable {
      case unrestricted                                         // no CLI login anywhere: today's behavior
      case requireAccount(accountUuid: String, organizationUuid: String?)
      case disabled
  }
  static func cookiePolicy(for account: ClaudeAccount, anyAccountSignedIn: Bool) -> CookiePolicy
  static func accountUuid(fromAccountResponse data: Data) -> String?   // GET https://claude.ai/api/account → top-level "uuid"
  func fetchUsage(providerID: String, policy: CookiePolicy) async throws -> Provider?
  // ClaudeProvider
  init(account: ClaudeAccount)
  struct FetchOptions: Sendable { var includeInsights: Bool; var insightsProjectsDirs: [URL]; var cookiePolicy: ClaudeWebProvider.CookiePolicy }
  func fetchUsage(_ options: FetchOptions) async throws -> Provider
  struct LoginExpired: Error { let fallback: Provider }
  static func expiredMessage(for account: ClaudeAccount) -> String
  // ClaudeInsightsAnalyzer
  func analyze(projectsDir: URL? = nil, additionalProjectsDirs: [URL] = [], now: Date = Date(), activeRecency: TimeInterval = activeRecencyWindow) async -> ClaudeInsights?
  ```
- **How `cookiePolicy` decides, first match wins:**
  1. The account has a login and a non-nil `accountUuid` → `.requireAccount(accountUuid, organizationUuid)`.
  2. The account is the default one, has no login, and `!anyAccountSignedIn` → `.unrestricted`.
  3. Anything else → `.disabled`.
- **How `fetchUsage(providerID:policy:)` behaves:**
  - `.disabled` → returns nil.
  - `.requireAccount` → fetches `/api/account` first. If the request fails, or the uuid differs, or it's missing → returns nil. Otherwise it fetches only `/organizations/<organizationUuid>/usage` when it has one, and loops over orgs as today when it doesn't.
  - Every returned `Provider` uses `providerID`.
- **What changes in `ClaudeProvider`:** it uses `account.keychainService` and `account.credentialsFile`. Every `Provider` it builds has `id: account.providerID`, `name: "Claude"`, `accountLabel: account.label`, and `accountUuid: account.accountUuid`.
  - **Insights:** it runs insights only when `options.includeInsights`, passing `account.projectsDir` plus `insightsProjectsDirs`.
  - **Login expired:** in the 401/403 branch, wherever today's code returns `webFallback(or: expiredProvider)` after the retry options run out, it throws `LoginExpired(fallback: expiredProvider)` when the cookie path gives nothing.
  - **Other errors:** they keep today's behavior.
  - **No credentials:** the web provider is tried only under `.unrestricted`.
  - **Refresh/write paths:** the keychain stays read-only for every account. `CredentialSource.isWritable` is unchanged.
- **What `expiredMessage` says:**
  - Default account: ``Token expired. Run `claude` to log in again.``
  - Custom folder: ``Token expired. Run `CLAUDE_CONFIG_DIR=<path> claude` to log in again.``, where `<path>` is the folder path run through `abbreviatingWithTildeInPath`.
- **Duplicate transcript folders:** `analyze` dedupes `[projectsDir] + additionalProjectsDirs` by `resolvingSymlinksInPath().path` and walks each one. A symlinked `~/.claude-2/projects` is counted once.

- [ ] **Step 1: Check the account endpoint.** It decides how the cookie is matched. Run the snippet below. It prints only `match`, `mismatch`, `missing`, or an HTTP status, never the cookie or account data:

```bash
python3 -I - <<'EOF'
import json, os, urllib.request
cookie = json.load(open(os.path.expanduser("~/.usagetracker/claude-web.json")))
key = cookie.get("cookie") or cookie.get("api_key")
want = json.load(open(os.path.expanduser("~/.claude.json")))["oauthAccount"]["accountUuid"]
req = urllib.request.Request("https://claude.ai/api/account", headers={"Cookie": "sessionKey=" + key, "Accept": "application/json"})
try:
    got = json.load(urllib.request.urlopen(req, timeout=15)).get("uuid")
    print("missing" if got is None else ("match" if got == want else "mismatch"))
except Exception as e:
    print("http:", getattr(e, "code", type(e).__name__))
EOF
```

  - **`match` or `mismatch`:** `uuid` is the right field. A mismatch only means the cookie belongs to a different account.
  - **`missing`:** find the account uuid field in the response's keys (print the keys only) and adapt `accountUuid(fromAccountResponse:)`.
  - **An HTTP error such as a Cloudflare 403:** curl-style clients are blocked. Keep `uuid` and leave the check to the end-to-end step in Task 7.
  - **Record the outcome** in the commit message.
- [ ] **Step 2: Write the failing tests.**

```swift
@Test func policyMatrix() {
    // signed in + uuid U1/O1             → .requireAccount(accountUuid: "U1", organizationUuid: "O1")
    // default, no login, nobody signed in → .unrestricted
    // default, no login, another signed in → .disabled
    // signed in, uuid nil                 → .disabled
}
@Test func accountUuidDecoding() {
    #expect(ClaudeWebProvider.accountUuid(fromAccountResponse: Data(#"{"uuid":"U1","email_address":"a@x"}"#.utf8)) == "U1")
    #expect(ClaudeWebProvider.accountUuid(fromAccountResponse: Data("{}".utf8)) == nil)
    #expect(ClaudeWebProvider.accountUuid(fromAccountResponse: Data("<html>".utf8)) == nil)
}
@Test func expiredMessages() {
    // default account → "Token expired. Run `claude` to log in again."
    // /Users/test/.claude-2 → "Token expired. Run `CLAUDE_CONFIG_DIR=/Users/test/.claude-2 claude` to log in again."
}
@Test func symlinkedProjectsCountedOnce() async {
    // dir A with one transcript; dir B = symlink to A; analyze(projectsDir: A, additionalProjectsDirs: [B])
    // monthlyCost equals analyze(projectsDir: A) alone
}
```

- [ ] **Step 3: Run them and check they fail.** Run `swift test --filter "ClaudeWeb|ClaudeProvider|ClaudeInsightsAnalyzer"`. Expected: a compile failure on `cookiePolicy`, `expiredMessage`, and `additionalProjectsDirs`.
- [ ] **Step 4: Implement the interfaces above.**
  - `AppState`, which still constructs `ClaudeProvider()`, will stop compiling here. Give it a temporary build fix: `ClaudeProvider(account: ClaudeAccountDiscovery.discover(home: FileManager.default.homeDirectoryForCurrentUser)[0])`, called with `FetchOptions(includeInsights: true, insightsProjectsDirs: [], cookiePolicy: .unrestricted)`, and catch `LoginExpired` as `e.fallback`. Task 4 replaces it.
- [ ] **Step 5: Run the tests and check they pass.** Run `make test`. Expected: all pass.
- [ ] **Step 6: Commit.** `git commit -m "feat(claude): per-account provider; cookie only fills in for its own account"`

---

### Task 4: AppState runs every account

**Files:**
- Modify: `Sources/UsageTracker/App.swift` (the `claudeProvider` property, the `refresh()` Claude fetch and results table, `init` after the cache restore, plus the new statics below)
- Test: `Tests/UsageTrackerTests/ClaudeAccountsStateTests.swift`, a new `@MainActor` suite

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces (statics on `AppState`):
  ```swift
  static func addingClaudeAccounts(_ ids: [String], to config: AppConfig) -> AppConfig
  static func claudeDisplayName(label: String?, override: String?, providerID: String, claudeCardCount: Int) -> String
  static func staleLabel(fetchedAt: Date?, refreshIntervalMinutes: Int, now: Date) -> String?
  static func resolveClaudeResult(_ result: Result<Provider, Error>, previous: Provider?) -> Provider?
  static func reconcileClaude(_ providers: [Provider], accounts: [ClaudeAccount]) -> [Provider]
  var claudeAccountCount: Int { get }            // providers.filter { isClaudeProviderID($0.id) }.count
  func renameClaudeAccount(_ providerID: String, to name: String)
  func staleLabel(for provider: Provider) -> String?
  ```
- **The rules:**
  - **`addingClaudeAccounts`:** inserts each missing ID right after the last Claude ID already in `providerOrder` and sets `enabledProviders[id] = true`. IDs already present, and every other field, are left alone. Calling it twice changes nothing.
  - **`claudeDisplayName`:**
    - `claudeCardCount < 2` → `"Claude"`.
    - Otherwise `"Claude · "` plus the first that applies: the trimmed non-empty `override`, then `label`, then `providerID`.
  - **`staleLabel`:**
    - The threshold is `max(15, 2 * refreshIntervalMinutes)` minutes. Under it, or with `fetchedAt == nil` → nil.
    - Under 60 minutes → `as of {m}m ago`. Under 48 hours → `as of {h}h ago`. Otherwise `as of {d}d ago`.
  - **`resolveClaudeResult`:**
    - `.success(p)` → `p`.
    - `LoginExpired` → nil when `previous` has items (so the reading carries forward), otherwise `e.fallback`.
    - Any other error → nil (transient, as today).
  - **`reconcileClaude`:** drops a Claude-ID provider whose ID isn't in `accounts`. It also drops one whose `accountUuid` and the account's `accountUuid` are both non-nil and differ. Everything else passes through.
- **`refresh()` flow:**
  1. Run `ClaudeAccountDiscovery.discover` off the main actor (it spawns `security`).
  2. Keep `[String: (account: ClaudeAccount, provider: ClaudeProvider)]`, rebuilding an entry when its account value changed.
  3. Fetch every account concurrently, alongside the other providers. `includeInsights` is true for the first account with `hasLogin`, or for `claude` when none has one. Pass every account's `projectsDir` and `cookiePolicy(for:anyAccountSignedIn:)`.
  4. Feed the results through `resolveClaudeResult`.
  5. Apply `reconcileClaude` after carry-forward.
  6. Apply `addingClaudeAccounts`, saving config only when it changed.
  7. Apply display names, setting `provider.name` for Claude IDs from `config.claudeAccountNames`. Do this also right after the cache restore in `init`, and in `renameClaudeAccount`.
- **`renameClaudeAccount`:** stores the trimmed name, or removes the entry when it's blank, then saves.

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func upgradesConfig151() throws {
    // decode the 1.5.1 literal: providerOrder default, pinnedItem {"providerId":"claude","itemLabel":"Weekly"}
    let out = AppState.addingClaudeAccounts(["claude", "claude-2601a85c"], to: config)
    #expect(out.providerOrder.prefix(3) == ["claude", "claude-2601a85c", "cursor"])
    #expect(out.enabledProviders["claude-2601a85c"] == true)
    #expect(out.pinnedItem == PinnedItem(providerId: "claude", itemLabel: "Weekly"))
    #expect(AppState.addingClaudeAccounts(["claude", "claude-2601a85c"], to: out).providerOrder == out.providerOrder)
}
@Test func insertsAfterMovedClaude()   // order [cursor, codex, claude, …] → new id lands right after claude; enabled["claude"] == false stays false
@Test func displayNames() {
    #expect(AppState.claudeDisplayName(label: "a@x", override: nil, providerID: "claude", claudeCardCount: 1) == "Claude")
    #expect(AppState.claudeDisplayName(label: "a@x", override: nil, providerID: "claude", claudeCardCount: 2) == "Claude · a@x")
    #expect(AppState.claudeDisplayName(label: "a@x", override: "Work", providerID: "claude", claudeCardCount: 2) == "Claude · Work")
    #expect(AppState.claudeDisplayName(label: "a@x", override: "  ", providerID: "claude", claudeCardCount: 2) == "Claude · a@x")
    #expect(AppState.claudeDisplayName(label: nil, override: nil, providerID: "claude-2601a85c", claudeCardCount: 2) == "Claude · claude-2601a85c")
}
@Test func staleLabels() {
    // interval 5: fetched now-10m → nil; now-20m → "as of 20m ago"; now-9h → "as of 9h ago"; now-3d → "as of 3d ago"; nil → nil
    // interval 30: now-40m → nil
}
@Test func resolveResults()           // success → provider; LoginExpired + previous with items → nil; + previous without items → fallback; + no previous → fallback; URLError → nil
@Test func reconcileDropsUndiscovered() // carried "claude-aaaa1111" with accounts [claude] → removed; "codex" untouched
@Test func reconcileDropsOtherAccount() // carried "claude" accountUuid U1, account uuid U9 → removed; U1 vs U1 → kept; carried nil uuid → kept
```

- [ ] **Step 2: Run them and check they fail.** Run `swift test --filter ClaudeAccountsState`. Expected: a compile failure on `addingClaudeAccounts`.
- [ ] **Step 3: Implement the statics and the `refresh()` flow above.** Remove the Task 3 build fix.
- [ ] **Step 4: Run the tests and check they pass.** Run `make test`. Expected: all pass.
- [ ] **Step 5: Smoke test.** Run `make run`, open the popover, then `make logs`. Expected: one `Claude` line, no keychain prompt, and the card titled plain `Claude`, since there's one account until `~/.claude-2` exists. Then `make stop`.
- [ ] **Step 6: Commit.** `git commit -m "feat(app): track every discovered Claude account"`

---

### Task 5: Popover: per-account cards, drill-in, stale marker

**Files:**
- Modify: `Sources/UsageTracker/Views/ProviderRow.swift` (header around line 115, cost row at line 60)
- Modify: `Sources/UsageTracker/Views/MenuBarView.swift` (the `Screen` enum at line 81, `detailAction` at line 208, `providerList`)
- Modify: `Sources/UsageTracker/Views/ClaudeDetailView.swift` (the provider lookup at line 42, the header at line 92, reset text at lines 129–135, headers at lines 150 and 304)
- Test: `Tests/UsageTrackerTests/ClaudeDetailViewTests.swift`

**Interfaces:**
- Consumes: `AppState.staleLabel(for:)`, `claudeAccountCount`, `isClaudeProviderID` (Tasks 2 and 4).
- Produces:
  - **`ProviderRow`:** gains `var staleLabel: String? = nil`, shown after the name in the header at 10pt, `.tertiary`. Its `.help` is "Numbers from the last successful check. They update on the next successful refresh." It also gains `var costLabel: String = "Est. API cost this month"`.
  - **`MenuBarView`:** `Screen.claudeDetail(String)` holds the provider ID. `detailAction` opens it for any `isClaudeProviderID` ID.
  - **`ClaudeDetailView`:** `init(appState:providerID:onBack:)`. The header shows `provider?.name ?? "Claude"`.
  - **`ClaudeDetailFormat.resetText(for item: UsageItem, now: Date = Date(), calendar: Calendar = .current) -> String?`** returns `absoluteResetLabel` when `resetsAt > now`, and `item.resetLabel` otherwise. It's `nonisolated` if it ends up on a View.
  - **Shared-stats copy:** with `claudeAccountCount >= 2`, use the shared-stats copy from Global Constraints. Otherwise keep today's text.

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func resetTextFuture()   // resetsAt now+2h, fixed now and calendar → == ClaudeDetailFormat.absoluteResetLabel(for: resetsAt, now: now, calendar: cal)
@Test func resetTextElapsed()  // UsageItem(...).markedReset() with resetsAt now-1h → "reset"
@Test func resetTextNoDate()   // resetLabel "$12.40/$50", resetsAt nil → "$12.40/$50"
```

- [ ] **Step 2: Run them and check they fail.** Run `swift test --filter ClaudeDetail`. Expected: a compile failure on `resetText`.
- [ ] **Step 3: Implement the interfaces above.** `MenuBarView` passes `staleLabel: appState.staleLabel(for: provider)` and the `costLabel` to each `ProviderRow`.
- [ ] **Step 4: Run the tests and check they pass.** Run `make test`. Expected: all pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(popover): a card and drill-in per Claude account, stale marker"`

---

### Task 6: Settings: one page per account, name field

**Files:**
- Modify: `Sources/UsageTracker/Views/Settings/ProviderCatalog.swift`
- Modify: `Sources/UsageTracker/Views/Settings/SettingsContent.swift` (every `ProviderCatalog.all[...]` lookup: lines 20, 26, 74, 97, 109)
- Modify: `Sources/UsageTracker/Views/Settings/SettingsDesign.swift:80,90,103`
- Modify: `Sources/UsageTracker/Views/Settings/Pages/ProviderPage.swift` (a new Name section; lines 129 and 164)
- Test: `Tests/UsageTrackerTests/SettingsViewModelTests.swift`

**Interfaces:**
- Consumes: `isClaudeProviderID`, `AppState.claudeAccountCount`, `renameClaudeAccount`, `config.claudeAccountNames` (Tasks 2 and 4).
- Produces: `ProviderCatalog.info(for id: String, liveName: String? = nil) -> ProviderSettingsInfo?`.
  - **Claude IDs:** a copy of the `claude` entry with this `id`, with `name` set to `liveName ?? "Claude"`. Only `"claude"` keeps the cookie `key`; extra accounts get `key: nil` and `connection: "Claude Code sign-in"`.
  - **Any other ID:** the static entry, so unknown IDs give nil.
- **Sidebar and pages:**
  - The sidebar lists an extra Claude ID only while it's in `appState.providers`.
  - `ProviderPage` shows a "Name" text field on Claude pages when `claudeAccountCount >= 2`. Its placeholder is the account's `accountLabel`, and it commits through `renameClaudeAccount` on submit or on focus loss.
  - For an extra account, the signed-out message is ``Run `CLAUDE_CONFIG_DIR=<path> claude` to sign in.``, using the same path form as `expiredMessage`. If the path isn't at hand, use "Sign in to Claude Code with this account's config folder."

- [ ] **Step 1: Write the failing tests** in a new `@Suite("ProviderCatalog info")` in `SettingsViewModelTests.swift`.

```swift
@Test func extraClaudeInfo() throws {
    let info = try #require(ProviderCatalog.info(for: "claude-2601a85c", liveName: "Claude · b@x"))
    #expect(info.id == "claude-2601a85c"); #expect(info.name == "Claude · b@x"); #expect(info.key == nil); #expect(info.icon == "brain")
}
@Test func defaultClaudeKeepsCookie()  // info(for: "claude")?.key?.fileName == "claude-web"
@Test func unknownIDIsNil()            // info(for: "nope") == nil; info(for: "codex")?.name == "Codex"
```

- [ ] **Step 2: Run them and check they fail.** Run `swift test --filter "ProviderCatalog info"`. Expected: a compile failure on `info(for:liveName:)`.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run the tests and check they pass.** Run `make test`. Expected: all pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(settings): a page and name field per Claude account"`

---

### Task 7: Docs and end-to-end check

**Files:**
- Modify: `README.md`. Add a short "Two Claude accounts" section covering the separate-folder setup (the `mkdir`, the symlink loop, the `claude2` alias, then `/login`) and what the app shows.
- Modify: `CLAUDE.md`. Update the ClaudeProvider line in Architecture and the Claude row in Provider Status. Add a Known Issues note: Claude account IDs and keychain names come from SHA-256 of the folder path, and a trailing slash changes them.

- [ ] **Step 1: Write the docs.** Commit with `git commit -m "docs: multiple Claude accounts"`.
- [ ] **Step 2: Run the full suite.** Run `make test`. Expected: all pass. Paste the summary line.
- [ ] **Step 3: Hand off to the user**, because this step needs their login. Ask them to run setup steps 1–4 from the brainstorm: `mkdir ~/.claude-2`, the symlink loop, the alias, then `claude2` → `/login` with the second account.
- [ ] **Step 4: Run the end-to-end checks:** `make run`, then open the popover.
  - Two cards appear, `Claude · <email1>` and `Claude · <email2>`.
  - The keychain item exists, and it's named the way Task 1 computes it: `security find-generic-password -s "Claude Code-credentials-$(printf %s "$HOME/.claude-2" | shasum -a 256 | cut -c1-8)" >/dev/null && echo found`
  - No keychain prompt appears, and `/usr/bin/log show --last 10m --style compact --predicate 'process == "securityd" AND eventMessage CONTAINS "partition mismatch"'` shows nothing new.
  - Pin `Weekly` on the second card, and the menu bar ring shows its percentage.
  - Run `make stop && make run`, and both cards restore with their numbers.
  - If Task 3 Step 1 couldn't check `/api/account`, confirm in `make logs` that no Claude card shows another account's numbers.
- [ ] **Step 5: Commit any fixes.** Then use superpowers:finishing-a-development-branch.
