# Stabilize and Ship UsageTracker — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize the three core features (Claude utilization bars, cost estimate, provider auto-detection), audit API-key providers, and produce a signed DMG with a full README ready for public release.

**Architecture:** Three parallel workstreams (stabilization, packaging, README) converge before signing. Each task is independently committable. The provider audit is a manual verification step that feeds the Known Limitations section of the README.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Testing framework (`@Test` / `#expect`), `swift build`, `swift test`, `codesign`, `notarytool`, `hdiutil`.

---

## File Map

| File | Change |
|------|--------|
| `Sources/UsageTracker/Models.swift` | Refresh default 10→5; disable runway/stability by default |
| `Tests/UsageTrackerTests/ModelsTests.swift` | Update refresh interval test 10→5 |
| `Sources/UsageTracker/Providers/ClaudeCostEstimator.swift` | Add `projectsDir` parameter to `estimateCurrentMonth` |
| `Tests/UsageTrackerTests/ClaudeCostEstimatorTests.swift` | Add file-level integration tests |
| `CLAUDE.md` | Add provider status table, Definition of Done, known issues, release steps |
| `Makefile` | Add `test` target |
| `README.md` | Full rewrite for public audience |
| `Sources/UsageTracker/App.swift` | Commit existing unstaged changes |
| `Sources/UsageTracker/Providers/ClaudeProvider.swift` | Commit existing unstaged changes |

---

## Task 1: Commit outstanding unstaged changes

**Files:**
- Modify: `Sources/UsageTracker/App.swift`
- Modify: `Sources/UsageTracker/Providers/ClaudeProvider.swift`

- [ ] **Step 1: Review unstaged changes**

```bash
git diff Sources/UsageTracker/App.swift Sources/UsageTracker/Providers/ClaudeProvider.swift
```

Read the diff carefully. If the changes are coherent (e.g., a login flow addition), commit them together. If they are unrelated, split into two commits.

- [ ] **Step 2: Stage and commit**

```bash
git add Sources/UsageTracker/App.swift Sources/UsageTracker/Providers/ClaudeProvider.swift
git commit -m "feat: <describe what the changes do based on the diff>"
```

---

## Task 2: Change default refresh interval from 10 to 5 minutes

**Files:**
- Modify: `Sources/UsageTracker/Models.swift:81`
- Modify: `Tests/UsageTrackerTests/ModelsTests.swift:62-65`

- [ ] **Step 1: Update the default in Models.swift**

In `Sources/UsageTracker/Models.swift`, change line 81:

```swift
// Before
var refreshIntervalMinutes: Int = 10

// After
var refreshIntervalMinutes: Int = 5
```

- [ ] **Step 2: Update the test in ModelsTests.swift**

In `Tests/UsageTrackerTests/ModelsTests.swift`, change lines 62–65:

```swift
// Before
/// Ensures default refresh interval is 10 minutes.
@Test("Default refresh interval is 10 minutes")
func defaultRefreshInterval() {
    let config = AppConfig()
    #expect(config.refreshIntervalMinutes == 10)
}

// After
/// Ensures default refresh interval is 5 minutes.
@Test("Default refresh interval is 5 minutes")
func defaultRefreshInterval() {
    let config = AppConfig()
    #expect(config.refreshIntervalMinutes == 5)
}
```

- [ ] **Step 3: Run tests**

```bash
swift test --filter ModelsTests
```

Expected output: `Test Suite 'ModelsTests' passed`

- [ ] **Step 4: Commit**

```bash
git add Sources/UsageTracker/Models.swift Tests/UsageTrackerTests/ModelsTests.swift
git commit -m "fix: change default refresh interval from 10 to 5 minutes"
```

---

## Task 3: Make ClaudeCostEstimator testable with an injectable projects directory

Currently `estimateCurrentMonth()` hardcodes `~/.claude/projects`. Add an internal overload that accepts a `URL` so tests can point it at a temp directory.

**Files:**
- Modify: `Sources/UsageTracker/Providers/ClaudeCostEstimator.swift:38-88`

- [ ] **Step 1: Write the failing test (verifies the new parameter is needed)**

Add to `Tests/UsageTrackerTests/ClaudeCostEstimatorTests.swift`:

```swift
@Test("estimateCurrentMonth with custom directory returns nil for empty dir")
func emptyProjectsDir() async throws {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let estimator = ClaudeCostEstimator()
    let result = await estimator.estimateCurrentMonth(projectsDir: tmpDir)
    // An empty directory has no JSONL files — should return a zero-cost estimate (not nil,
    // because the directory exists)
    #expect(result != nil)
    #expect(result?.totalCost == 0.0)
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter "emptyProjectsDir"
```

Expected: compile error — `estimateCurrentMonth` has no `projectsDir` parameter.

- [ ] **Step 3: Add the `projectsDir` parameter to ClaudeCostEstimator**

In `Sources/UsageTracker/Providers/ClaudeCostEstimator.swift`, replace the existing `estimateCurrentMonth()` signature and body (lines 38–88) with:

```swift
func estimateCurrentMonth(projectsDir: URL? = nil) async -> CostEstimate? {
    let resolvedDir = projectsDir ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    guard FileManager.default.fileExists(atPath: resolvedDir.path) else {
        return nil
    }

    let calendar = Calendar.current
    let now = Date()
    guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
        return nil
    }

    // Collect all .jsonl files synchronously before entering async context
    let jsonlFiles: [(url: URL, modDate: Date)] = {
        guard let enumerator = FileManager.default.enumerator(
            at: resolvedDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [(URL, Date)] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = resourceValues.contentModificationDate,
                  modDate >= monthStart else { continue }
            result.append((fileURL, modDate))
        }
        return result
    }()

    var totalCost: Double = 0

    for (fileURL, modDate) in jsonlFiles {
        let filePath = fileURL.path

        // Check file cache
        if let cached = fileCache[filePath], cached.modDate == modDate {
            totalCost += cached.cost
            continue
        }

        // Parse the file
        let fileCost = Self.parseFile(at: fileURL, monthStart: monthStart, monthEnd: now)
        fileCache[filePath] = (modDate: modDate, cost: fileCost)
        totalCost += fileCost
    }

    return CostEstimate(totalCost: totalCost, periodStart: monthStart, periodEnd: now)
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter "emptyProjectsDir"
```

Expected: `Test Suite passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageTracker/Providers/ClaudeCostEstimator.swift \
        Tests/UsageTrackerTests/ClaudeCostEstimatorTests.swift
git commit -m "refactor: add projectsDir parameter to estimateCurrentMonth for testability"
```

---

## Task 4: Add JSONL integration tests

**Files:**
- Modify: `Tests/UsageTrackerTests/ClaudeCostEstimatorTests.swift`

- [ ] **Step 1: Write all integration tests**

Append to `Tests/UsageTrackerTests/ClaudeCostEstimatorTests.swift`:

```swift
// MARK: - Integration tests (file-level)

@Test("Aggregates cost across two JSONL files")
func aggregatesMultipleFiles() async throws {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let timestamp = ISO8601DateFormatter().string(from: Date())

    // File 1: 1M opus input tokens → $15
    let line1 = """
    {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    """
    try line1.write(to: tmpDir.appendingPathComponent("proj1.jsonl"), atomically: true, encoding: .utf8)

    // File 2: 1M sonnet output tokens → $15
    let line2 = """
    {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"claude-sonnet-4-6","role":"assistant","usage":{"input_tokens":0,"output_tokens":1000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    """
    try line2.write(to: tmpDir.appendingPathComponent("proj2.jsonl"), atomically: true, encoding: .utf8)

    let estimator = ClaudeCostEstimator()
    let result = await estimator.estimateCurrentMonth(projectsDir: tmpDir)
    #expect(result != nil)
    // $15 + $15 = $30
    #expect(abs((result?.totalCost ?? 0) - 30.0) < 0.01)
}

@Test("Skips lines from previous months")
func skipsOldLines() async throws {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Old timestamp (Jan 2025) — should be filtered out
    let oldLine = """
    {"type":"assistant","timestamp":"2025-01-15T10:00:00.000Z","message":{"model":"claude-opus-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    """
    try oldLine.write(to: tmpDir.appendingPathComponent("old.jsonl"), atomically: true, encoding: .utf8)

    let estimator = ClaudeCostEstimator()
    let result = await estimator.estimateCurrentMonth(projectsDir: tmpDir)
    // File mod date is now (within month), but line timestamp is Jan 2025 — cost should be 0
    #expect(result != nil)
    #expect(result?.totalCost == 0.0)
}

@Test("Handles malformed lines mixed with valid lines")
func handlesMixedLines() async throws {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let timestamp = ISO8601DateFormatter().string(from: Date())
    let content = """
    {bad json here}
    {"type":"human","timestamp":"\(timestamp)","message":{"role":"user","content":"hello"}}
    {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"claude-sonnet-4-6","role":"assistant","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
    """
    // Sonnet 1M input = $3
    try content.write(to: tmpDir.appendingPathComponent("mixed.jsonl"), atomically: true, encoding: .utf8)

    let estimator = ClaudeCostEstimator()
    let result = await estimator.estimateCurrentMonth(projectsDir: tmpDir)
    #expect(result != nil)
    #expect(abs((result?.totalCost ?? 0) - 3.0) < 0.01)
}

@Test("Returns nil when projects directory does not exist")
func nilForMissingDirectory() async {
    let nonexistent = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString)")
    let estimator = ClaudeCostEstimator()
    let result = await estimator.estimateCurrentMonth(projectsDir: nonexistent)
    #expect(result == nil)
}
```

- [ ] **Step 2: Run all tests**

```bash
swift test --filter ClaudeCostEstimatorTests
```

Expected: all tests pass. If `skipsOldLines` fails, check that the test file's modification date is being set correctly by the OS — a newly written file always has mod date = now, which is within the current month, so the file will be included but the line's timestamp will filter it.

- [ ] **Step 3: Commit**

```bash
git add Tests/UsageTrackerTests/ClaudeCostEstimatorTests.swift
git commit -m "test: add JSONL file-level integration tests for ClaudeCostEstimator"
```

---

## Task 5: Disable Runway and Stability by default

**Files:**
- Modify: `Sources/UsageTracker/Models.swift:87-96`

- [ ] **Step 1: Update enabledProviders defaults**

In `Sources/UsageTracker/Models.swift`, change the `enabledProviders` default dictionary:

```swift
// Before
var enabledProviders: [String: Bool] = [
    "claude": true,
    "cursor": true,
    "codex": true,
    "elevenlabs": true,
    "stability": true,
    "runway": true,
    "openai": true,
    "openrouter": true
]

// After
var enabledProviders: [String: Bool] = [
    "claude": true,
    "cursor": true,
    "codex": true,
    "elevenlabs": true,
    "stability": false,   // untested — hidden by default
    "runway": false,      // untested — hidden by default
    "openai": true,
    "openrouter": true
]
```

- [ ] **Step 2: Run tests**

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageTracker/Models.swift
git commit -m "feat: disable Runway and Stability providers by default (untested)"
```

---

## Task 6: Provider audit (manual verification)

This task has no code changes. It produces notes that feed into Task 8 (README Known Limitations).

**Providers to verify: OpenAI, ElevenLabs, OpenRouter**

- [ ] **Step 1: Test OpenAI with admin key (`sk-admin-*`)**

1. Create `~/.usagetracker/openai.json` with content: `{"api_key": "sk-admin-YOUR-KEY"}`
2. Build and run: `swift build && .build/debug/UsageTracker`
3. Open the menu bar popover
4. Expected: OpenAI row shows "Spend: $X.XX this month"
5. Note actual behavior: ___________

- [ ] **Step 2: Test OpenAI with project key (`sk-proj-*`)**

1. Replace key in `~/.usagetracker/openai.json` with a project key
2. Restart app
3. Expected: OpenAI row shows "Requests: N today" and "Tokens: X.XK today"
4. Note actual behavior: ___________

- [ ] **Step 3: Test ElevenLabs**

1. Create `~/.usagetracker/elevenlabs.json` with content: `{"api_key": "YOUR-KEY"}`
2. Restart app
3. Expected: ElevenLabs row shows "Characters: X%" with reset time
4. Note actual behavior: ___________

- [ ] **Step 4: Test OpenRouter**

1. Create `~/.usagetracker/openrouter.json` with content: `{"api_key": "sk-or-YOUR-KEY"}`
2. Restart app
3. Expected: OpenRouter shows credits used % or monthly/daily spend
4. Note actual behavior: ___________

- [ ] **Step 5: Record findings**

Update `CLAUDE.md` (Task 7) with observed behavior and any bugs found. Fix bugs before proceeding to Task 8.

---

## Task 7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add provider status table, Known Issues, and Release Process sections**

Append the following to `CLAUDE.md` (after the existing content):

```markdown
## Provider Status

| Provider | Auth | What it shows | Status |
|----------|------|---------------|--------|
| Claude | OAuth (keychain, auto) | Session %, Weekly %, Sonnet %, Opus %, cost estimate | Tested |
| Cursor | Local DB (auto) | Usage % | Tested |
| Codex | `~/.codex/auth.json` (auto) | Usage % | Tested |
| OpenAI | API key (`sk-admin-*` or `sk-proj-*`) | Admin: monthly spend; Project: daily requests + tokens | Tested |
| ElevenLabs | API key | Character quota % with reset time | Tested |
| OpenRouter | API key | Credits used % or monthly/daily spend | Tested |
| Runway | API key | Credit balance | **Untested — hidden by default** |
| Stability | API key | Credit balance | **Untested — hidden by default** |

## Definition of Done (pre-public release)

- [ ] `swift test` passes with all new integration tests
- [ ] Session % and Weekly % display correctly for a logged-in Claude account
- [ ] Cost estimate shows for current month (requires `~/.claude/projects/` with .jsonl files)
- [ ] Cursor and Codex auto-detect on a machine where they're installed
- [ ] OpenAI, ElevenLabs, OpenRouter: verified working with real keys
- [ ] Runway and Stability are hidden by default
- [ ] Default refresh interval is 5 minutes
- [ ] `make release` completes without errors from a clean build
- [ ] App signed and notarized (DMG produced)
- [ ] README complete with all sections

## Known Issues

- **Keychain password prompt**: The app reads Claude Code CLI's keychain credentials (`"Claude Code-credentials"`). macOS may prompt for permission. Clicking "Always Allow" persists for the life of the signed app identity. Fixed permanently by code signing (users never see it again after first launch).
- **Runway / Stability**: Providers are implemented but untested. Hidden by default. Enable in Settings at your own risk.

## Releasing

Required env vars (set in your shell or `.env` before running `make release`):

```bash
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export TEAM_ID="YOURTEAMID"
export APPLE_ID="you@example.com"
export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # App-specific password from appleid.apple.com
```

Release steps:
1. `make test` — all tests must pass
2. `make release` — builds, signs, notarizes, produces `build/UsageTracker.dmg`
3. `git tag vX.Y.Z && git push --tags`
4. Create GitHub Release, attach `build/UsageTracker.dmg`
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with provider status, definition of done, release steps"
```

---

## Task 8: Add `test` target to Makefile

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add test target**

In `Makefile`, change line 1 from:

```makefile
.PHONY: run stop restart logs status build clean release
```

to:

```makefile
.PHONY: run stop restart logs status build test clean release
```

Then add a `test` target after `build`:

```makefile
test:
	swift test
```

- [ ] **Step 2: Verify it works**

```bash
make test
```

Expected: all Swift tests pass and exit 0.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "chore: add test target to Makefile"
```

---

## Task 9: Rewrite README.md

**Files:**
- Modify: `README.md`

Complete this task **after Task 6 (provider audit)** so Known Limitations is accurate.

- [ ] **Step 1: Rewrite README.md**

Replace the entire contents of `README.md` with:

````markdown
# UsageTracker

See your Claude Code usage limits in your macOS menu bar, live.

<!-- TODO: Replace with a real screenshot or GIF (record with Kap or Gifox, 5–10 seconds) -->
![UsageTracker menu bar screenshot](docs/screenshot.png)

## Install

1. Download `UsageTracker.dmg` from [Releases](../../releases)
2. Open the DMG and drag UsageTracker to Applications
3. First launch: macOS may block an unsigned build — run this once in Terminal:
   ```bash
   xattr -cr ~/Applications/UsageTracker.app
   ```
   (Signed builds from GitHub Releases don't need this step.)
4. Launch UsageTracker from Applications

**Requirements:** macOS 13+, [Claude Code](https://claude.ai/code) installed and logged in

## What it shows

UsageTracker reads your usage data locally — no accounts, no telemetry.

| Provider | What's shown | How to connect |
|----------|-------------|----------------|
| **Claude** | Session %, Weekly %, Sonnet %, Opus %, monthly cost estimate | Auto-detected (uses Claude Code login) |
| **Cursor** | Usage % | Auto-detected |
| **Codex** | Usage % | Auto-detected via `~/.codex/auth.json` |
| **OpenAI** | Monthly spend (admin key) or daily requests + tokens (project key) | Add key in Settings |
| **ElevenLabs** | Character quota % | Add key in Settings |
| **OpenRouter** | Credit balance or monthly spend | Add key in Settings |

## Usage

- **Left-click** the menu bar icon — open usage popover
- **Right-click** the menu bar icon — Settings, Refresh, Quit
- The icon color reflects your highest current usage (green → orange → red)
- Pin any metric to the menu bar via the dot indicator in the popover

## Settings

Settings live in `~/.usagetracker/`:
- `config.json` — refresh interval, provider order, visibility
- `openai.json`, `elevenlabs.json`, `openrouter.json` — API keys

## Build from source

```bash
git clone https://github.com/YOUR_USERNAME/UsageTracker
cd UsageTracker
make build
.build/debug/UsageTracker
```

To run tests:
```bash
make test
```

## Known limitations

- **Password prompt on first launch**: UsageTracker reads Claude Code's stored login from your macOS Keychain. Click "Always Allow" once and you won't be asked again.
- **Runway and Stability**: Providers are implemented but not yet verified. They are hidden by default. You can enable them in Settings.
- **Cost estimate**: Reads `~/.claude/projects/*.jsonl` files. Accurate for Claude Code usage; does not include API usage outside Claude Code.
- **macOS 13+ required**: The app uses SwiftUI features not available on earlier versions.
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for public release"
```

---

## Task 10: Final verification

- [ ] **Step 1: Run full test suite**

```bash
make test
```

Expected: all tests pass.

- [ ] **Step 2: Build and run the app**

```bash
make build
.build/debug/UsageTracker
```

Verify:
- Claude row shows Session %, Weekly % (or "not connected" if not logged in)
- Cost estimate appears if `~/.claude/projects/` contains `.jsonl` files from this month
- Refresh fires after ~5 minutes
- Runway and Stability are absent from the popover (unless manually enabled)

- [ ] **Step 3: Run release build**

```bash
make release
```

Expected: `build/UsageTracker.dmg` produced, signed, and notarized.

- [ ] **Step 4: Test the DMG**

Mount the DMG, drag to Applications, launch. Verify no Gatekeeper warning (signed build). Verify "Always Allow" on keychain prompt sticks across restarts.
