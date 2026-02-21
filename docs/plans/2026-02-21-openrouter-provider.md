# OpenRouter Provider Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add OpenRouter usage tracking showing monthly/daily credit spending via the `/api/v1/key` endpoint.

**Architecture:** New `OpenRouterProvider` actor following the existing API-key-based provider pattern (same as OpenAI/ElevenLabs). Reads key from `~/.usagetracker/openrouter.json`, calls `GET https://openrouter.ai/api/v1/key`, displays monthly and daily spend.

**Tech Stack:** Swift, SwiftUI, URLSession

---

### Task 1: Create OpenRouterProvider actor

**Files:**
- Create: `Sources/UsageTracker/Providers/OpenRouterProvider.swift`

**Step 1: Create the provider file**

```swift
import Foundation

actor OpenRouterProvider {
    private let keyInfoURL = URL(string: "https://openrouter.ai/api/v1/key")!
    private let settingsURL = URL(string: "https://openrouter.ai/settings/keys")!

    private var apiKey: String? {
        let configPath = NSString(string: "~/.usagetracker/openrouter.json").expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: configPath),
              let config = try? JSONDecoder().decode(APIKeyConfig.self, from: data) else {
            return nil
        }
        return config.apiKey
    }

    struct APIKeyConfig: Codable {
        var apiKey: String?

        enum CodingKeys: String, CodingKey {
            case apiKey = "api_key"
        }
    }

    struct KeyResponse: Codable {
        var data: KeyData

        struct KeyData: Codable {
            var usage: Double?
            var usageDaily: Double?
            var usageWeekly: Double?
            var usageMonthly: Double?
            var limit: Double?
            var limitRemaining: Double?
            var isFreeTier: Bool?

            enum CodingKeys: String, CodingKey {
                case usage
                case usageDaily = "usage_daily"
                case usageWeekly = "usage_weekly"
                case usageMonthly = "usage_monthly"
                case limit
                case limitRemaining = "limit_remaining"
                case isFreeTier = "is_free_tier"
            }
        }
    }

    func fetchUsage() async throws -> Provider {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            return Provider(
                id: "openrouter",
                name: "OpenRouter",
                icon: "arrow.trianglehead.branch",
                items: [],
                status: .notConnected(url: settingsURL)
            )
        }

        var request = URLRequest(url: keyInfoURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return Provider(id: "openrouter", name: "OpenRouter", icon: "arrow.trianglehead.branch", items: [], status: .error("Invalid response"))
        }

        if httpResponse.statusCode == 401 {
            return Provider(id: "openrouter", name: "OpenRouter", icon: "arrow.trianglehead.branch", items: [], status: .error("Invalid key"))
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            return Provider(id: "openrouter", name: "OpenRouter", icon: "arrow.trianglehead.branch", items: [], status: .error("HTTP \(httpResponse.statusCode)"))
        }

        let keyInfo = try JSONDecoder().decode(KeyResponse.self, from: data)
        let monthlyUsage = keyInfo.data.usageMonthly ?? 0
        let dailyUsage = keyInfo.data.usageDaily ?? 0
        let limit = keyInfo.data.limit

        var items: [UsageItem] = []

        if let limit = limit, limit > 0 {
            // Has credit limit — show bar
            let percentage = (monthlyUsage / limit) * 100
            items.append(UsageItem(
                label: "Monthly Spend",
                current: percentage,
                limit: 100,
                resetLabel: String(format: "$%.2f / $%.2f", monthlyUsage, limit)
            ))
        } else {
            // No limit — just show dollar amount
            items.append(UsageItem(
                label: "Monthly Spend",
                current: 0,
                limit: 0,
                resetLabel: String(format: "$%.2f", monthlyUsage)
            ))
        }

        items.append(UsageItem(
            label: "Daily Spend",
            current: 0,
            limit: 0,
            resetLabel: String(format: "$%.2f today", dailyUsage)
        ))

        return Provider(id: "openrouter", name: "OpenRouter", icon: "arrow.trianglehead.branch", items: items, status: .loaded)
    }
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build 2>&1 | tail -5`
Expected: Build succeeds (new file is picked up by SPM automatically)

**Step 3: Commit**

```bash
git add Sources/UsageTracker/Providers/OpenRouterProvider.swift
git commit -m "feat: add OpenRouterProvider actor"
```

---

### Task 2: Register provider in AppState

**Files:**
- Modify: `Sources/UsageTracker/App.swift:64-70` (add instance)
- Modify: `Sources/UsageTracker/App.swift:115-131` (add to refresh)
- Modify: `Sources/UsageTracker/App.swift:134-138` (add to results)

**Step 1: Add instance variable**

After line 70 (`private let openAIProvider = OpenAIProvider()`), add:

```swift
private let openRouterProvider = OpenRouterProvider()
```

**Step 2: Add async let in refresh()**

After line 122 (`async let openAIResult = openAIProvider.fetchUsage()`), add:

```swift
async let openRouterResult = openRouterProvider.fetchUsage()
```

**Step 3: Add try? await**

After line 130 (`let openAI = try? await openAIResult`), add:

```swift
let openRouter = try? await openRouterResult
```

**Step 4: Add to results tuple**

Change the results array (line 134-138) to include OpenRouter. Add after the `("OpenAI", openAI)` entry:

```swift
("OpenRouter", openRouter)
```

**Step 5: Build and verify**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add Sources/UsageTracker/App.swift
git commit -m "feat: register OpenRouter provider in AppState"
```

---

### Task 3: Add to default config

**Files:**
- Modify: `Sources/UsageTracker/Models.swift:73-90`

**Step 1: Add to enabledProviders default**

Add `"openrouter": true` to the `enabledProviders` dictionary (after `"openai": true` on line 80).

**Step 2: Add to providerOrder default**

Add `"openrouter"` to the `providerOrder` array (after `"openai"` on line 89).

**Step 3: Build and verify**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Sources/UsageTracker/Models.swift
git commit -m "feat: add OpenRouter to default config"
```

---

### Task 4: Add to Settings UI

**Files:**
- Modify: `Sources/UsageTracker/Views/SettingsView.swift`

**Step 1: Add state variables**

After line 18 (`@State private var openAISaved: Bool = false`), add:

```swift
@State private var openRouterKey: String = ""
@State private var openRouterSaved: Bool = false
```

**Step 2: Add provider definition to allProviders**

Add after the `"openai"` entry (after line 111, before the closing `]`):

```swift
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
),
```

**Step 3: Add key loading in loadAllKeys()**

After line 217 (`openAISaved = !openAIKey.isEmpty`), add:

```swift
openRouterKey = loadKey("openrouter") ?? ""
openRouterSaved = !openRouterKey.isEmpty
```

**Step 4: Add to saveKey switch**

After `case "openai": openAISaved = true` (line 245), add:

```swift
case "openrouter": openRouterSaved = true
```

**Step 5: Add validation function**

After `validateOpenAIKey` function (after line 340), add:

```swift
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
```

**Step 6: Add to HelpView**

In the "API Key Services" section of `HelpView` (after the Runway HelpRow around line 651), add:

```swift
HelpRow(
    icon: "arrow.trianglehead.branch",
    iconColor: .cyan,
    title: "OpenRouter",
    description: "Add API key from openrouter.ai/settings/keys"
)
```

**Step 7: Build and verify**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 8: Commit**

```bash
git add Sources/UsageTracker/Views/SettingsView.swift
git commit -m "feat: add OpenRouter to Settings UI with key validation"
```

---

### Task 5: Final build and smoke test

**Step 1: Clean build**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build 2>&1 | tail -10`
Expected: Build succeeds with no warnings

**Step 2: Run the app**

Run: `.build/debug/UsageTracker`
Expected: App launches, OpenRouter appears in Settings as a toggleable provider with API key input
