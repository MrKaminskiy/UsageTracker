import SwiftUI

@main
struct UsageTrackerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            Text("Loading...") // Placeholder - MenuBarView will be added later
        } label: {
            Image(systemName: "chart.bar.fill") // Placeholder - MenuBarIcon will be added later
        }
        .menuBarExtraStyle(.window)

        Settings {
            Text("Settings") // Placeholder - SettingsView will be added later
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var providers: [Provider] = []
    @Published var isLoading: Bool = false
    @Published var config: AppConfig = AppConfig()
    @Published var lastUpdated: Date?

    var maxPercentage: Double {
        providers.map(\.maxPercentage).max() ?? 0
    }

    private var refreshTimer: Timer?

    init() {
        loadConfig()
        setupRefreshTimer()
    }

    func refresh() async {
        isLoading = true
        // Plugin loading will be added later
        isLoading = false
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
