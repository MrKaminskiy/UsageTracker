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
    private let codexProvider = CodexProvider()
    private let elevenLabsProvider = ElevenLabsProvider()
    private var refreshTimer: Timer?

    var maxPercentage: Double {
        providers.map(\.maxPercentage).max() ?? 0
    }

    init() {
        loadConfig()
        setupRefreshTimer()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        // Fetch from all providers concurrently
        async let claudeResult = claudeProvider.fetchUsage()
        async let cursorResult = cursorProvider.fetchUsage()
        async let codexResult = codexProvider.fetchUsage()
        async let elevenLabsResult = elevenLabsProvider.fetchUsage()

        let claude = try? await claudeResult
        let cursor = try? await cursorResult
        let codex = try? await codexResult
        let elevenLabs = try? await elevenLabsResult

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

        if let elevenLabs = elevenLabs {
            newProviders.append(elevenLabs)
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
