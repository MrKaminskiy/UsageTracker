import SwiftUI
import Combine

@main
struct UsageTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(appState: appDelegate.appState)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusBarController: StatusBarController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("UsageTracker started")
        statusBarController = StatusBarController()
        statusBarController.setup(with: MenuBarView(appState: appState), appState: appState)
        statusBarController.updateIcon(percentage: appState.maxPercentage, isLoading: appState.isLoading)
        statusBarController.onClearCache = { [weak self] in
            self?.appState.clearCache()
        }

        // Observe changes to update icon
        appState.$providers
            .combineLatest(appState.$isLoading, appState.$config)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, isLoading, _ in
                guard let self = self else { return }
                self.statusBarController.updateIcon(percentage: self.appState.maxPercentage, isLoading: isLoading)
            }
            .store(in: &cancellables)

        // Initial refresh
        Task {
            await appState.refresh()
        }

        // Show onboarding on first launch
        if !appState.config.hasCompletedOnboarding {
            statusBarController.showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("UsageTracker stopping")
        statusBarController.cleanup()
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
    private let stabilityProvider = StabilityProvider()
    private let runwayProvider = RunwayProvider()
    private let openAIProvider = OpenAIProvider()
    private var refreshTimer: Timer?

    var maxPercentage: Double {
        // If there's a pinned item, use its percentage
        if let pinned = config.pinnedItem,
           let provider = visibleProviders.first(where: { $0.id == pinned.providerId }),
           let item = provider.items.first(where: { $0.label == pinned.itemLabel }) {
            return item.percentage
        }
        // Otherwise use the max across all visible providers
        return visibleProviders.map(\.maxPercentage).max() ?? 0
    }

    var pinnedItem: PinnedItem? {
        config.pinnedItem
    }

    func togglePin(providerId: String, itemLabel: String) {
        if let current = config.pinnedItem,
           current.providerId == providerId && current.itemLabel == itemLabel {
            // Unpin if already pinned
            config.pinnedItem = nil
        } else {
            // Pin this item
            config.pinnedItem = PinnedItem(providerId: providerId, itemLabel: itemLabel)
        }
        saveConfig()
    }

    func isPinned(providerId: String, itemLabel: String) -> Bool {
        guard let pinned = config.pinnedItem else { return false }
        return pinned.providerId == providerId && pinned.itemLabel == itemLabel
    }

    init() {
        loadConfig()
        setupRefreshTimer()
    }

    func refresh() async {
        Log.info("Refreshing providers...")
        isLoading = true
        defer { isLoading = false }

        // Fetch from all providers concurrently
        async let claudeResult = claudeProvider.fetchUsage()
        async let cursorResult = cursorProvider.fetchUsage()
        async let codexResult = codexProvider.fetchUsage()
        async let elevenLabsResult = elevenLabsProvider.fetchUsage()
        async let stabilityResult = stabilityProvider.fetchUsage()
        async let runwayResult = runwayProvider.fetchUsage()
        async let openAIResult = openAIProvider.fetchUsage()

        let claude = try? await claudeResult
        let cursor = try? await cursorResult
        let codex = try? await codexResult
        let elevenLabs = try? await elevenLabsResult
        let stability = try? await stabilityResult
        let runway = try? await runwayResult
        let openAI = try? await openAIResult

        var newProviders: [Provider] = []

        let results: [(String, Provider?)] = [
            ("Claude", claude), ("Cursor", cursor), ("Codex", codex),
            ("ElevenLabs", elevenLabs), ("Stability", stability),
            ("Runway", runway), ("OpenAI", openAI)
        ]

        for (name, provider) in results {
            if let provider = provider {
                newProviders.append(provider)
                switch provider.status {
                case .loaded:
                    let items = provider.items.map { "\($0.label): \(Int($0.percentage))%" }.joined(separator: ", ")
                    Log.info("  \(name): \(items)")
                case .notConnected:
                    Log.info("  \(name): not connected")
                case .error(let msg):
                    Log.error("  \(name): \(msg)")
                case .loading:
                    break
                }
            }
        }

        providers = newProviders
        Log.info("Refresh complete — \(newProviders.count) providers loaded")
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
        Log.info("Refresh timer set to \(config.refreshIntervalMinutes)min")
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

    func updateHideNotConnected(_ hide: Bool) {
        config.hideNotConnected = hide
        saveConfig()
    }

    func updateProviderEnabled(_ id: String, enabled: Bool) {
        config.enabledProviders[id] = enabled
        saveConfig()
    }

    func updateProviderOrder(_ order: [String]) {
        config.providerOrder = order
        saveConfig()
    }

    func completeOnboarding() {
        config.hasCompletedOnboarding = true
        saveConfig()
    }

    var visibleProviders: [Provider] {
        let filtered = providers.filter { provider in
            // Check if provider is enabled in settings
            guard config.isProviderEnabled(provider.id) else { return false }

            // Check if we should hide not-connected providers
            if config.hideNotConnected {
                if case .notConnected = provider.status {
                    return false
                }
            }

            return true
        }

        // Sort by configured order
        return filtered.sorted { a, b in
            let indexA = config.providerOrder.firstIndex(of: a.id) ?? Int.max
            let indexB = config.providerOrder.firstIndex(of: b.id) ?? Int.max
            return indexA < indexB
        }
    }

    func clearCache() {
        Log.info("Clearing cache...")
        // Clear URL cache
        URLCache.shared.removeAllCachedResponses()

        // Clear any stored cookies for API endpoints
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }

        // Reset providers to trigger fresh fetch
        providers = []
        lastUpdated = nil

        // Refresh
        Task {
            await refresh()
        }
    }
}
