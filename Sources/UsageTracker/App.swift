import SwiftUI
import Combine

@main
struct UsageTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
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
    /// Enabled providers that failed transiently this refresh (rate-limited/offline) with no
    /// data to fall back on. Drives an honest empty state instead of a misleading "sign in".
    @Published var transientFailureCount: Int = 0

    let updateChecker = UpdateChecker()

    private let claudeProvider = ClaudeProvider()
    private let cursorProvider = CursorProvider()
    private let codexProvider = CodexProvider()
    private let elevenLabsProvider = ElevenLabsProvider()
    private let stabilityProvider = StabilityProvider()
    private let runwayProvider = RunwayProvider()
    private let openAIProvider = OpenAIProvider()
    private let openRouterProvider = OpenRouterProvider()
    private var refreshTimer: Timer?

    private let contextAlertNotifier = ContextAlertNotifier()
    private var contextAlertState = ContextAlert.State()
    private var contextAlertInFlight = false
    // The alert reads transcripts locally and must not depend on the Claude API call succeeding
    // (rate limit, offline, expired/missing OAuth), so it uses its own analyzer, not the provider's.
    private let contextAlertAnalyzer = ClaudeInsightsAnalyzer()

    var maxPercentage: Double {
        // If there's a pinned item, use its percentage
        if let pinned = config.pinnedItem,
           let provider = popoverProviders.first(where: { $0.id == pinned.providerId }),
           let item = provider.items.first(where: { $0.stablePinKey == pinned.itemLabel }) {
            return item.percentage
        }
        // Otherwise use the max across all visible providers
        return popoverProviders.map(\.maxPercentage).max() ?? 0
    }

    var pinnedItem: PinnedItem? {
        guard let pinned = config.pinnedItem,
              popoverProviders.contains(where: { provider in
                  provider.id == pinned.providerId
                      && provider.items.contains(where: { $0.stablePinKey == pinned.itemLabel })
              }) else { return nil }
        return pinned
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
        // Show the last known reading immediately. The first refresh is a network round-trip
        // away at best, and the Claude usage endpoint rate-limits hard enough that it can be
        // minutes — an empty popover for that whole stretch reads as "broken", not "loading".
        if let cached = UsageCache.load() {
            providers = cached.providers
            lastUpdated = cached.savedAt
            Log.info("Restored \(cached.providers.count) providers from cache (saved \(cached.savedAt))")
        }
        setupRefreshTimer()
        // Install the notification delegate + request permission at launch (not lazily on the
        // first crossing), so foreground alerts show and the grant resolves before any post.
        if config.isContextAlertEnabled {
            contextAlertNotifier.configureIfNeeded()
        }
    }

    func refresh() async {
        Log.info("Refreshing providers...")
        isLoading = true
        defer { isLoading = false }

        // The context alert reads transcripts locally; run it concurrently so it never waits on
        // (or is blocked by a timeout of) the provider API calls below.
        async let contextAlert: Void = evaluateContextAlert()

        // Fetch from all providers concurrently
        async let claudeResult = claudeProvider.fetchUsage()
        async let cursorResult = cursorProvider.fetchUsage()
        async let codexResult = codexProvider.fetchUsage()
        async let elevenLabsResult = elevenLabsProvider.fetchUsage()
        async let stabilityResult = stabilityProvider.fetchUsage()
        async let runwayResult = runwayProvider.fetchUsage()
        async let openAIResult = openAIProvider.fetchUsage()
        async let openRouterResult = openRouterProvider.fetchUsage()

        let claude = try? await claudeResult
        let cursor = try? await cursorResult
        let codex = try? await codexResult
        let elevenLabs = try? await elevenLabsResult
        let stability = try? await stabilityResult
        let runway = try? await runwayResult
        let openAI = try? await openAIResult
        let openRouter = try? await openRouterResult

        var newProviders: [Provider] = []

        let results: [(name: String, id: String, provider: Provider?)] = [
            ("Claude", "claude", claude), ("Cursor", "cursor", cursor), ("Codex", "codex", codex),
            ("ElevenLabs", "elevenlabs", elevenLabs), ("Stability", "stability", stability),
            ("Runway", "runway", runway), ("OpenAI", "openai", openAI), ("OpenRouter", "openrouter", openRouter)
        ]

        let refreshedAt = Date()
        for (name, _, provider) in results {
            if var provider = provider {
                provider.fetchedAt = refreshedAt
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
            } else {
                Log.error("  \(name): fetch failed (transient) — keeping last-known data")
            }
        }

        // Preserve last-known data for providers that failed to fetch, minus anything that has
        // aged out of being worth showing.
        newProviders.append(contentsOf: Self.carriedForward(
            providers,
            excluding: Set(newProviders.map(\.id)),
            now: refreshedAt
        ))

        // Distinguish "rate-limited / unreachable" from "not signed in": a provider that threw
        // (nil result) with no data to fall back on is a transient failure, whereas a
        // .notConnected status means genuinely signed out.
        transientFailureCount = Self.transientFailures(
            results: results.map { ($0.id, $0.provider) },
            finalProviders: newProviders,
            enabled: config.enabledProviders
        )

        // Strip cost estimates if disabled in settings
        if !config.showCostEstimate {
            newProviders = newProviders.map { provider in
                var p = provider
                p.costEstimate = nil
                return p
            }
        }

        providers = newProviders
        Log.info("Refresh complete — \(newProviders.count) providers loaded")
        // The footer sits under the usage rows, so it has to mean "these numbers are current".
        // A provider answering `.notConnected` or `.error` is a fresh answer but not a fresh
        // reading; stamping on those would print "Updated now" over rows that are hours old.
        let freshIDs = Set(results.compactMap { $0.provider != nil ? $0.id : nil })
        let gotUsage = results.contains { result in
            guard let provider = result.provider, case .loaded = provider.status else { return false }
            return !provider.items.isEmpty
        }
        if gotUsage {
            lastUpdated = refreshedAt
        }
        // Persisted after the cost-estimate strip above, so a snapshot never carries a figure
        // the user has chosen not to see. Only providers that actually answered this cycle are
        // rewritten; the rest keep the reading — and the age — they already had on disk.
        UsageCache.save(newProviders, freshlyFetched: freshIDs)
        await contextAlert
        await updateChecker.check()
    }

    /// Fire a macOS notification when the active Claude chat's context crosses the configured
    /// threshold. Runs its own local transcript analysis (a free file read, no API cost) so it
    /// works even when the Claude API call failed. The de-duplication state is committed only
    /// when the notification is actually delivered, so a dropped/denied alert isn't lost.
    private func evaluateContextAlert() async {
        guard config.isContextAlertEnabled else { return }
        // Serialize: overlapping refreshes (the timer and a popover-triggered refresh) must not
        // both read the same uncommitted state across the analyze/deliver awaits and post
        // duplicate alerts. Set synchronously before the first await, so this is atomic on the
        // main actor; a second evaluation bails until this one finishes.
        guard !contextAlertInFlight else { return }
        contextAlertInFlight = true
        defer { contextAlertInFlight = false }

        // Widen the "active chat" recency window to at least the refresh interval (+ buffer), so a
        // chat that crosses the threshold just after one refresh and then goes idle isn't judged
        // stale — and its crossing silently missed — by the next refresh at long intervals.
        let recency = max(ClaudeInsightsAnalyzer.activeRecencyWindow,
                          TimeInterval(config.refreshIntervalMinutes * 60) + 5 * 60)
        guard let insights = await contextAlertAnalyzer.analyze(activeRecency: recency) else { return }
        // The setting may have been turned off while analysis was suspended.
        guard config.isContextAlertEnabled else { return }

        let (fire, newState) = ContextAlert.evaluate(
            currentContext: insights.activeContextTokens,
            sessionId: insights.activeSessionId,
            threshold: config.contextAlertThreshold,
            state: contextAlertState
        )
        guard fire else {
            contextAlertState = newState  // re-arm / no-op transitions always commit; they don't post
            return
        }
        Log.info("Context alert: active chat at ~\((insights.activeContextTokens ?? 0) / 1000)k ≥ \(config.contextAlertThreshold / 1000)k")
        let delivered = await contextAlertNotifier.notifyContextExceeded(
            contextTokens: insights.activeContextTokens ?? 0,
            title: insights.activeSessionTitle,
            threshold: config.contextAlertThreshold
        )
        if delivered {
            contextAlertState = newState  // commit de-dup only once the alert actually reached the user
        } else {
            Log.info("Context alert not delivered — leaving armed to retry next refresh")
        }
    }

    func loadConfig() {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker/config.json")

        if let data = try? Data(contentsOf: configURL),
           var loaded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            // Add any new providers missing from saved config
            let knownProviders = AppConfig().providerOrder
            for id in knownProviders where !loaded.providerOrder.contains(id) {
                loaded.providerOrder.append(id)
                if loaded.enabledProviders[id] == nil {
                    loaded.enabledProviders[id] = true
                }
            }
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

    func updateShowCostEstimate(_ show: Bool) {
        config.showCostEstimate = show
        saveConfig()
    }

    func updateShowExtraUsageInPopover(_ show: Bool) {
        config.showExtraUsageInPopover = show
        saveConfig()
    }

    func updateContextAlertEnabled(_ enabled: Bool) {
        config.contextAlertEnabled = enabled
        saveConfig()
        if enabled {
            contextAlertState = ContextAlert.State()  // re-arm: an already-large chat can alert again
            contextAlertNotifier.configureIfNeeded()
        }
    }

    func updateContextAlertThresholdK(_ thousands: Int) {
        config.contextAlertThresholdK = thousands
        saveConfig()
        // Re-arm every session against the new threshold. Otherwise a chat that already alerted
        // at the old (lower) threshold keeps its session id in the de-dup set, and if it crosses
        // the new (higher) threshold before any refresh observes it below, the alert is suppressed.
        contextAlertState = ContextAlert.State()
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

    /// Last-known providers worth carrying into this refresh's results.
    ///
    /// A provider that failed keeps showing its previous reading rather than blanking, but not
    /// indefinitely: once it passes `UsageCache.maxAge` it is retired, and any item whose reset
    /// window has since elapsed is dropped instead of being left on screen as fact. Surviving
    /// countdowns are recomputed so a carried-forward row doesn't freeze at the time it was
    /// fetched. A reading with no `fetchedAt` predates that field and is kept as before.
    static func carriedForward(_ existing: [Provider],
                               excluding fresh: Set<String>,
                               now: Date = Date()) -> [Provider] {
        existing.compactMap { provider in
            guard !fresh.contains(provider.id) else { return nil }
            if let fetchedAt = provider.fetchedAt,
               now.timeIntervalSince(fetchedAt) > UsageCache.maxAge { return nil }

            // Same calendar-day rule the disk restore applies: a figure scoped to a period it
            // can't express as a deadline ("$1.20 today") must not outlive that period just
            // because the app happened to stay open across midnight.
            let sameDay = provider.fetchedAt.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? true

            var carried = provider
            carried.items = provider.items.compactMap { item in
                if let resetsAt = item.resetsAt, resetsAt <= now { return nil }
                guard item.resetsAt != nil else { return sameDay ? item : nil }
                return UsageItem(
                    label: item.label,
                    current: item.current,
                    limit: item.limit,
                    resetLabel: relativeResetLabel(item.resetsAt, now: now),
                    resetsAt: item.resetsAt,
                    pinKey: item.pinKey,
                    kind: item.kind
                )
            }
            // Everything it had to say has expired; an empty row is worse than no row.
            guard !carried.items.isEmpty else { return nil }
            return carried
        }
    }

    /// Count of enabled providers that failed transiently this refresh (threw — e.g. rate-limit
    /// or network error) and have no cached data to fall back on. A `.notConnected` status is a
    /// non-throwing result and is NOT counted, so genuine "signed out" stays distinct.
    static func transientFailures(results: [(id: String, provider: Provider?)],
                                  finalProviders: [Provider],
                                  enabled: [String: Bool]) -> Int {
        results.reduce(0) { acc, r in
            let threw = r.provider == nil
            let isEnabled = enabled[r.id] == true
            let hasData = finalProviders.contains { $0.id == r.id && !$0.items.isEmpty }
            return acc + (threw && isEnabled && !hasData ? 1 : 0)
        }
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

    /// Providers and usage items shown in the main menu-bar popover. Detail views continue to
    /// use the unfiltered provider data so account information remains available there.
    var popoverProviders: [Provider] {
        guard !config.shouldShowExtraUsageInPopover else { return visibleProviders }
        return visibleProviders.map { provider in
            var filtered = provider
            filtered.items.removeAll { $0.kind == .extraUsage }
            return filtered
        }
    }

    func clearCache() {
        Log.info("Clearing cache...")
        // Clear URL cache
        URLCache.shared.removeAllCachedResponses()

        // Drop the persisted usage snapshot too, so "Clear Cache" really does leave the app
        // with nothing to show until the next refresh.
        UsageCache.clear()

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
