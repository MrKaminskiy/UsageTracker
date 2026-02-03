import SwiftUI

@main
struct UsageTrackerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            MenuBarIcon(percentage: appState.maxPercentage, isLoading: appState.isLoading)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var providers: [Provider] = []
    @Published var isLoading: Bool = false
    @Published var config: AppConfig = AppConfig()
    @Published var lastUpdated: Date?

    private let claudeProvider = ClaudeProvider()
    private let cursorProvider = CursorProvider()
    private let extensionServer = ExtensionServer()
    private var chatgptProvider: ExtensionProvider?
    private var refreshTimer: Timer?

    var maxPercentage: Double {
        providers.map(\.maxPercentage).max() ?? 0
    }

    init() {
        loadConfig()
        setupRefreshTimer()
        setupExtensionServer()
    }

    private func setupExtensionServer() {
        chatgptProvider = ExtensionProvider(
            server: extensionServer,
            id: "chatgpt",
            name: "ChatGPT / Codex",
            icon: "bubble.left.fill",
            dashboardURL: URL(string: "https://chatgpt.com/")!
        )

        Task {
            try? await extensionServer.start()
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        // Fetch from all providers concurrently
        async let claudeResult = claudeProvider.fetchUsage()
        async let cursorResult = cursorProvider.fetchUsage()

        let claude = try? await claudeResult
        let cursor = try? await cursorResult
        let chatgpt = await chatgptProvider?.fetchUsage()

        var newProviders: [Provider] = []

        if let claude = claude {
            newProviders.append(claude)
        }

        if let cursor = cursor {
            newProviders.append(cursor)
        }

        if let chatgpt = chatgpt {
            newProviders.append(chatgpt)
        }

        providers = newProviders
        lastUpdated = Date()
    }

    func loadConfig() {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker/config.json")

        if let data = try? Data(contentsOf: configURL),
           let loaded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = loaded
        }
    }

    func saveConfig() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker")

        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let configURL = configDir.appendingPathComponent("config.json")
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL)
        }
    }

    private func setupRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(config.refreshIntervalMinutes * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func updateRefreshInterval(_ minutes: Int) {
        config.refreshIntervalMinutes = minutes
        saveConfig()
        setupRefreshTimer()
    }
}
