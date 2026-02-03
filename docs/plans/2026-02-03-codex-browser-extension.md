# Codex + Browser Extension Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Codex native provider and browser extension infrastructure for web-only AI services (starting with ChatGPT)

**Architecture:**
- Codex reads credentials from `~/.codex/auth.json` (same pattern as existing providers)
- Browser extension scrapes usage data from web dashboards and sends to native app via localhost HTTP server
- Native app runs a lightweight HTTP server on `localhost:19284` to receive extension data

**Tech Stack:** Swift, SwiftUI, WebKit (for extension), Chrome Extension Manifest V3, JavaScript

---

## Phase 1: Codex Native Provider

### Task 1: Create CodexProvider skeleton

**Files:**
- Create: `Sources/UsageTracker/Providers/CodexProvider.swift`

**Step 1: Create the provider file with basic structure**

```swift
import Foundation

actor CodexProvider {
    private let authPath = NSString(string: "~/.codex/auth.json").expandingTildeInPath
    private let usageURL = URL(string: "https://api.openai.com/v1/usage")!
    private let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    private let settingsURL = URL(string: "https://platform.openai.com/settings/organization/limits")!

    struct AuthFile: Codable {
        var accessToken: String?
        var refreshToken: String?
        var expiresAt: Double?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
        }
    }

    func fetchUsage() async throws -> Provider {
        // Read auth file
        guard let authData = FileManager.default.contents(atPath: authPath),
              let auth = try? JSONDecoder().decode(AuthFile.self, from: authData),
              var accessToken = auth.accessToken else {
            return Provider(
                id: "codex",
                name: "Codex",
                icon: "terminal.fill",
                items: [],
                status: .notConnected(url: settingsURL)
            )
        }

        // TODO: Implement token refresh and usage fetch
        return Provider(
            id: "codex",
            name: "Codex",
            icon: "terminal.fill",
            items: [],
            status: .error("Not implemented")
        )
    }
}
```

**Step 2: Verify file compiles**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build 2>&1 | head -20`
Expected: Build succeeds (provider not wired up yet)

**Step 3: Commit**

```bash
git add Sources/UsageTracker/Providers/CodexProvider.swift
git commit -m "feat: add CodexProvider skeleton"
```

---

### Task 2: Implement Codex token refresh

**Files:**
- Modify: `Sources/UsageTracker/Providers/CodexProvider.swift`

**Step 1: Add refresh token logic**

Add these methods to CodexProvider:

```swift
private func needsRefresh(_ expiresAt: Double?) -> Bool {
    guard let expiresAt = expiresAt else { return true }
    let now = Date().timeIntervalSince1970
    let bufferSeconds: Double = 5 * 60 // 5 minutes
    return now + bufferSeconds >= expiresAt
}

private func refreshTokenRequest(_ refreshToken: String) async throws -> (accessToken: String, expiresAt: Double)? {
    var request = URLRequest(url: refreshURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 15

    let body: [String: String] = [
        "grant_type": "refresh_token",
        "client_id": clientID,
        "refresh_token": refreshToken
    ]
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
        return nil
    }

    struct RefreshResponse: Codable {
        var access_token: String?
        var expires_in: Double?
    }

    let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)

    guard let token = refreshResponse.access_token else { return nil }

    let expiresAt = Date().timeIntervalSince1970 + (refreshResponse.expires_in ?? 3600)
    return (token, expiresAt)
}

private func saveAuth(_ auth: AuthFile) {
    guard let data = try? JSONEncoder().encode(auth) else { return }
    FileManager.default.createFile(atPath: authPath, contents: data)
}
```

**Step 2: Verify build**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build 2>&1 | head -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add Codex token refresh logic"
```

---

### Task 3: Implement Codex usage API call

**Files:**
- Modify: `Sources/UsageTracker/Providers/CodexProvider.swift`

**Step 1: Add usage response structures**

```swift
struct UsageResponse: Codable {
    var data: UsageData?

    struct UsageData: Codable {
        var hardLimitUsd: Double?
        var softLimitUsd: Double?
        var totalUsageUsd: Double?
        var dailyUsage: [DailyUsage]?

        enum CodingKeys: String, CodingKey {
            case hardLimitUsd = "hard_limit_usd"
            case softLimitUsd = "soft_limit_usd"
            case totalUsageUsd = "total_usage_usd"
            case dailyUsage = "daily_usage"
        }
    }

    struct DailyUsage: Codable {
        var date: String?
        var usageUsd: Double?

        enum CodingKeys: String, CodingKey {
            case date
            case usageUsd = "usage_usd"
        }
    }
}
```

**Step 2: Update fetchUsage to call API**

Replace the fetchUsage method:

```swift
func fetchUsage() async throws -> Provider {
    // Read auth file
    guard let authData = FileManager.default.contents(atPath: authPath),
          var auth = try? JSONDecoder().decode(AuthFile.self, from: authData),
          var accessToken = auth.accessToken else {
        return Provider(
            id: "codex",
            name: "Codex",
            icon: "terminal.fill",
            items: [],
            status: .notConnected(url: settingsURL)
        )
    }

    // Refresh if needed
    if needsRefresh(auth.expiresAt), let refreshToken = auth.refreshToken {
        if let refreshed = try? await refreshTokenRequest(refreshToken) {
            accessToken = refreshed.accessToken
            auth.accessToken = refreshed.accessToken
            auth.expiresAt = refreshed.expiresAt
            saveAuth(auth)
        }
    }

    // Fetch usage
    var request = URLRequest(url: usageURL)
    request.httpMethod = "GET"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 10

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        return Provider(
            id: "codex",
            name: "Codex",
            icon: "terminal.fill",
            items: [],
            status: .error("Invalid response")
        )
    }

    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
        return Provider(
            id: "codex",
            name: "Codex",
            icon: "terminal.fill",
            items: [],
            status: .error("Token expired. Run `codex login`")
        )
    }

    guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
        return Provider(
            id: "codex",
            name: "Codex",
            icon: "terminal.fill",
            items: [],
            status: .error("HTTP \(httpResponse.statusCode)")
        )
    }

    let usage = try JSONDecoder().decode(UsageResponse.self, from: data)

    var items: [UsageItem] = []

    if let usageData = usage.data,
       let total = usageData.totalUsageUsd,
       let limit = usageData.hardLimitUsd ?? usageData.softLimitUsd,
       limit > 0 {
        let percentage = (total / limit) * 100
        items.append(UsageItem(
            label: "Usage",
            current: percentage,
            limit: 100,
            resetLabel: nil
        ))
    }

    return Provider(
        id: "codex",
        name: "Codex",
        icon: "terminal.fill",
        items: items,
        status: items.isEmpty ? .error("No usage data") : .loaded
    )
}
```

**Step 3: Verify build**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build 2>&1 | head -20`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: implement Codex usage API call"
```

---

### Task 4: Wire up CodexProvider to AppState

**Files:**
- Modify: `Sources/UsageTracker/App.swift`

**Step 1: Add codexProvider instance**

After line 29 (`private let cursorProvider = CursorProvider()`), add:

```swift
private let codexProvider = CodexProvider()
```

**Step 2: Update refresh() to include Codex**

Update the refresh() method to fetch from all three providers:

```swift
func refresh() async {
    isLoading = true
    defer { isLoading = false }

    // Fetch from all providers concurrently
    async let claudeResult = claudeProvider.fetchUsage()
    async let cursorResult = cursorProvider.fetchUsage()
    async let codexResult = codexProvider.fetchUsage()

    let claude = try? await claudeResult
    let cursor = try? await cursorResult
    let codex = try? await codexResult

    var newProviders: [Provider] = []

    if let claude = claude {
        newProviders.append(claude)
    }

    if let cursor = cursor {
        newProviders.append(cursor)
    }

    if let codex = codex {
        newProviders.append(codex)
    }

    providers = newProviders
    lastUpdated = Date()
}
```

**Step 3: Build and run**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build && swift run`
Expected: App launches, Codex shows "Not connected" (unless user has ~/.codex/auth.json)

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: wire up CodexProvider to AppState"
```

---

## Phase 2: Browser Extension Infrastructure

### Task 5: Create ExtensionServer for receiving extension data

**Files:**
- Create: `Sources/UsageTracker/ExtensionServer.swift`

**Step 1: Create the HTTP server**

```swift
import Foundation
import Network

actor ExtensionServer {
    private var listener: NWListener?
    private let port: UInt16 = 19284
    private var receivedData: [String: ExtensionData] = [:]

    struct ExtensionData: Codable {
        let providerId: String
        let items: [ExtensionUsageItem]
        let timestamp: Double

        struct ExtensionUsageItem: Codable {
            let label: String
            let current: Double
            let limit: Double
            let resetLabel: String?
        }
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

        listener?.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func getData(for providerId: String) -> ExtensionData? {
        let data = receivedData[providerId]
        // Only return if less than 5 minutes old
        if let data = data, Date().timeIntervalSince1970 - data.timestamp < 300 {
            return data
        }
        return nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let data = data, error == nil else {
                connection.cancel()
                return
            }

            Task {
                await self?.processRequest(data: data, connection: connection)
            }
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        // Parse HTTP request to extract JSON body
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: 400, body: "Invalid request")
            return
        }

        // Find JSON body after headers
        if let bodyStart = requestString.range(of: "\r\n\r\n") {
            let bodyString = String(requestString[bodyStart.upperBound...])
            if let bodyData = bodyString.data(using: .utf8),
               let extensionData = try? JSONDecoder().decode(ExtensionData.self, from: bodyData) {
                receivedData[extensionData.providerId] = extensionData
                sendResponse(connection: connection, status: 200, body: "{\"ok\":true}")
                return
            }
        }

        sendResponse(connection: connection, status: 400, body: "{\"error\":\"Invalid JSON\"}")
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText = status == 200 ? "OK" : "Bad Request"
        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
```

**Step 2: Verify build**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build 2>&1 | head -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/UsageTracker/ExtensionServer.swift
git commit -m "feat: add ExtensionServer for browser extension communication"
```

---

### Task 6: Create ExtensionProvider base for extension-based providers

**Files:**
- Create: `Sources/UsageTracker/Providers/ExtensionProvider.swift`

**Step 1: Create the provider**

```swift
import Foundation

actor ExtensionProvider {
    private let server: ExtensionServer
    private let providerId: String
    private let providerName: String
    private let providerIcon: String
    private let dashboardURL: URL

    init(server: ExtensionServer, id: String, name: String, icon: String, dashboardURL: URL) {
        self.server = server
        self.providerId = id
        self.providerName = name
        self.providerIcon = icon
        self.dashboardURL = dashboardURL
    }

    func fetchUsage() async -> Provider {
        guard let data = await server.getData(for: providerId) else {
            return Provider(
                id: providerId,
                name: providerName,
                icon: providerIcon,
                items: [],
                status: .notConnected(url: dashboardURL)
            )
        }

        let items = data.items.map { item in
            UsageItem(
                label: item.label,
                current: item.current,
                limit: item.limit,
                resetLabel: item.resetLabel
            )
        }

        return Provider(
            id: providerId,
            name: providerName,
            icon: providerIcon,
            items: items,
            status: items.isEmpty ? .error("No usage data") : .loaded
        )
    }
}
```

**Step 2: Verify build**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build 2>&1 | head -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/UsageTracker/Providers/ExtensionProvider.swift
git commit -m "feat: add ExtensionProvider for browser extension-based providers"
```

---

### Task 7: Integrate ExtensionServer into AppState

**Files:**
- Modify: `Sources/UsageTracker/App.swift`

**Step 1: Add server and ChatGPT provider**

After the codexProvider line, add:

```swift
private let extensionServer = ExtensionServer()
private var chatgptProvider: ExtensionProvider?
```

**Step 2: Update init() to start server**

Replace the init() method:

```swift
init() {
    loadConfig()
    setupRefreshTimer()
    setupExtensionServer()
}

private func setupExtensionServer() {
    chatgptProvider = ExtensionProvider(
        server: extensionServer,
        id: "chatgpt",
        name: "ChatGPT",
        icon: "bubble.left.fill",
        dashboardURL: URL(string: "https://chatgpt.com/")!
    )

    Task {
        try? await extensionServer.start()
    }
}
```

**Step 3: Update refresh() to include ChatGPT**

```swift
func refresh() async {
    isLoading = true
    defer { isLoading = false }

    // Fetch from all providers concurrently
    async let claudeResult = claudeProvider.fetchUsage()
    async let cursorResult = cursorProvider.fetchUsage()
    async let codexResult = codexProvider.fetchUsage()

    let claude = try? await claudeResult
    let cursor = try? await cursorResult
    let codex = try? await codexResult
    let chatgpt = await chatgptProvider?.fetchUsage()

    var newProviders: [Provider] = []

    if let claude = claude {
        newProviders.append(claude)
    }

    if let cursor = cursor {
        newProviders.append(cursor)
    }

    if let codex = codex {
        newProviders.append(codex)
    }

    if let chatgpt = chatgpt {
        newProviders.append(chatgpt)
    }

    providers = newProviders
    lastUpdated = Date()
}
```

**Step 4: Build and run**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build && swift run`
Expected: App launches with ChatGPT showing "Not connected"

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: integrate ExtensionServer and ChatGPT provider into AppState"
```

---

## Phase 3: Chrome Extension

### Task 8: Create Chrome extension manifest and structure

**Files:**
- Create: `Extension/manifest.json`
- Create: `Extension/background.js`
- Create: `Extension/content.js`
- Create: `Extension/popup.html`
- Create: `Extension/popup.js`

**Step 1: Create Extension directory**

```bash
mkdir -p Extension
```

**Step 2: Create manifest.json**

```json
{
  "manifest_version": 3,
  "name": "UsageTracker Connector",
  "version": "1.0.0",
  "description": "Sends AI service usage data to UsageTracker menu bar app",
  "permissions": [
    "storage",
    "activeTab"
  ],
  "host_permissions": [
    "https://chatgpt.com/*",
    "http://localhost:19284/*"
  ],
  "background": {
    "service_worker": "background.js"
  },
  "content_scripts": [
    {
      "matches": ["https://chatgpt.com/*"],
      "js": ["content.js"],
      "run_at": "document_idle"
    }
  ],
  "action": {
    "default_popup": "popup.html",
    "default_title": "UsageTracker"
  },
  "icons": {
    "16": "icons/icon16.png",
    "48": "icons/icon48.png",
    "128": "icons/icon128.png"
  }
}
```

**Step 3: Create background.js**

```javascript
// Background service worker for UsageTracker extension

const SERVER_URL = 'http://localhost:19284';

// Send usage data to native app
async function sendToApp(data) {
  try {
    const response = await fetch(SERVER_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    return response.ok;
  } catch (error) {
    console.error('UsageTracker: Failed to send data', error);
    return false;
  }
}

// Listen for messages from content scripts
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'USAGE_DATA') {
    sendToApp(message.data).then(success => {
      sendResponse({ success });
    });
    return true; // Keep channel open for async response
  }
});

// Check server connection periodically
async function checkConnection() {
  try {
    const response = await fetch(SERVER_URL, { method: 'OPTIONS' });
    await chrome.storage.local.set({ connected: response.ok });
  } catch {
    await chrome.storage.local.set({ connected: false });
  }
}

// Check connection every 30 seconds
setInterval(checkConnection, 30000);
checkConnection();
```

**Step 4: Create content.js**

```javascript
// Content script for ChatGPT usage extraction

(function() {
  'use strict';

  const PROVIDER_ID = 'chatgpt';

  // Extract usage data from ChatGPT settings page
  function extractUsageData() {
    // ChatGPT shows usage in settings > subscription
    // This selector may need updating as ChatGPT changes their UI
    const usageElements = document.querySelectorAll('[data-testid="usage-bar"], .usage-indicator');

    if (usageElements.length === 0) {
      // Try alternative: look for text containing usage info
      const allText = document.body.innerText;
      const usageMatch = allText.match(/(\d+)\s*\/\s*(\d+)\s*(messages|requests)/i);

      if (usageMatch) {
        return {
          providerId: PROVIDER_ID,
          items: [{
            label: usageMatch[3] || 'Requests',
            current: parseFloat(usageMatch[1]),
            limit: parseFloat(usageMatch[2]),
            resetLabel: null
          }],
          timestamp: Date.now() / 1000
        };
      }
      return null;
    }

    const items = [];
    usageElements.forEach(el => {
      const label = el.getAttribute('aria-label') || 'Usage';
      const value = el.getAttribute('aria-valuenow') || '0';
      const max = el.getAttribute('aria-valuemax') || '100';

      items.push({
        label: label,
        current: parseFloat(value),
        limit: parseFloat(max),
        resetLabel: null
      });
    });

    return {
      providerId: PROVIDER_ID,
      items: items,
      timestamp: Date.now() / 1000
    };
  }

  // Send data to background script
  function sendUsageData() {
    const data = extractUsageData();
    if (data && data.items.length > 0) {
      chrome.runtime.sendMessage({ type: 'USAGE_DATA', data: data });
    }
  }

  // Run extraction when page is ready and periodically
  if (document.readyState === 'complete') {
    sendUsageData();
  } else {
    window.addEventListener('load', sendUsageData);
  }

  // Re-extract every 60 seconds while page is open
  setInterval(sendUsageData, 60000);

  // Also extract when user navigates within the SPA
  let lastUrl = location.href;
  new MutationObserver(() => {
    if (location.href !== lastUrl) {
      lastUrl = location.href;
      setTimeout(sendUsageData, 1000); // Wait for content to load
    }
  }).observe(document.body, { subtree: true, childList: true });
})();
```

**Step 5: Create popup.html**

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body {
      width: 200px;
      padding: 12px;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      font-size: 13px;
    }
    .status {
      display: flex;
      align-items: center;
      gap: 8px;
      margin-bottom: 12px;
    }
    .dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
    }
    .dot.connected { background: #34c759; }
    .dot.disconnected { background: #ff3b30; }
    .info {
      color: #666;
      font-size: 11px;
    }
  </style>
</head>
<body>
  <div class="status">
    <span class="dot" id="statusDot"></span>
    <span id="statusText">Checking...</span>
  </div>
  <p class="info">
    This extension sends usage data from AI services to the UsageTracker menu bar app.
  </p>
  <script src="popup.js"></script>
</body>
</html>
```

**Step 6: Create popup.js**

```javascript
// Popup script for UsageTracker extension

async function updateStatus() {
  const { connected } = await chrome.storage.local.get('connected');
  const dot = document.getElementById('statusDot');
  const text = document.getElementById('statusText');

  if (connected) {
    dot.className = 'dot connected';
    text.textContent = 'Connected to UsageTracker';
  } else {
    dot.className = 'dot disconnected';
    text.textContent = 'UsageTracker not running';
  }
}

updateStatus();
```

**Step 7: Create placeholder icons**

```bash
mkdir -p Extension/icons
# Create simple placeholder icons (user can replace with proper icons later)
```

**Step 8: Commit**

```bash
git add Extension/
git commit -m "feat: add Chrome extension for browser-based usage tracking"
```

---

### Task 9: Add extension installation instructions

**Files:**
- Create: `Extension/README.md`

**Step 1: Create README**

```markdown
# UsageTracker Browser Extension

This extension sends usage data from web-based AI services to the UsageTracker menu bar app.

## Supported Services

- ChatGPT (chatgpt.com)
- More coming soon...

## Installation

### Chrome / Brave / Edge

1. Open `chrome://extensions/` (or `brave://extensions/`, `edge://extensions/`)
2. Enable "Developer mode" (toggle in top right)
3. Click "Load unpacked"
4. Select the `Extension` folder from this project

### Firefox (coming soon)

Firefox support requires a different manifest format.

## How It Works

1. The extension runs content scripts on supported AI service websites
2. It extracts usage information from the page
3. Data is sent to `localhost:19284` where UsageTracker listens
4. The menu bar app displays the aggregated usage

## Privacy

- All data stays on your machine
- No data is sent to any external servers
- The extension only reads from pages you visit

## Troubleshooting

**"UsageTracker not running"**
- Make sure the UsageTracker app is running
- Check that port 19284 is not blocked by firewall

**Usage not updating**
- Visit the service's usage/settings page to trigger extraction
- Some services only show usage in specific sections
```

**Step 2: Commit**

```bash
git add Extension/README.md
git commit -m "docs: add extension installation instructions"
```

---

### Task 10: Test end-to-end integration

**Files:**
- None (testing only)

**Step 1: Build and run the app**

Run: `cd /Users/nk/Documents/Projects/UsageTracker && swift build && swift run`
Expected: App starts, shows Claude, Cursor, Codex, ChatGPT providers

**Step 2: Verify server is listening**

Run: `curl -X OPTIONS http://localhost:19284 2>&1`
Expected: HTTP response (or connection error if app not running)

**Step 3: Test sending mock data**

Run:
```bash
curl -X POST http://localhost:19284 \
  -H "Content-Type: application/json" \
  -d '{"providerId":"chatgpt","items":[{"label":"Messages","current":50,"limit":100,"resetLabel":"3h"}],"timestamp":1234567890}'
```
Expected: `{"ok":true}`

**Step 4: Verify app shows ChatGPT data**

After curl command, app should show ChatGPT with 50% usage

**Step 5: Load extension in Chrome**

1. Open `chrome://extensions/`
2. Enable Developer mode
3. Load unpacked > select Extension folder
4. Verify extension appears with green dot when app is running

**Step 6: Commit any fixes**

```bash
git add -A
git commit -m "fix: end-to-end integration fixes"
```

---

## Summary

After completing all tasks, you will have:

1. **CodexProvider** - Native provider reading from `~/.codex/auth.json`
2. **ExtensionServer** - HTTP server on localhost:19284 receiving browser data
3. **ExtensionProvider** - Generic provider for extension-sourced data
4. **Chrome Extension** - Manifest V3 extension with ChatGPT content script

### Adding More Extension-Based Providers

To add a new service (e.g., Midjourney):

1. Add a content script in `Extension/` for the service's domain
2. Update `manifest.json` host_permissions and content_scripts
3. Add new `ExtensionProvider` instance in `AppState.setupExtensionServer()`

### File Structure After Implementation

```
UsageTracker/
├── Sources/UsageTracker/
│   ├── App.swift (updated)
│   ├── Models.swift
│   ├── ExtensionServer.swift (new)
│   └── Providers/
│       ├── ClaudeProvider.swift
│       ├── CursorProvider.swift
│       ├── CodexProvider.swift (new)
│       └── ExtensionProvider.swift (new)
├── Extension/
│   ├── manifest.json
│   ├── background.js
│   ├── content.js
│   ├── popup.html
│   ├── popup.js
│   ├── icons/
│   └── README.md
└── docs/plans/
    └── 2026-02-03-codex-browser-extension.md
```
