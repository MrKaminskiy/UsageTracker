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

    private let pluginEngine = PluginEngine()
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

        let plugins = loadPlugins()

        await withTaskGroup(of: (String, Result<[UsageItem], Error>).self) { group in
            for (id, js, _) in plugins {
                group.addTask {
                    do {
                        let items = try await self.pluginEngine.runProbe(js: js)
                        return (id, .success(items))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }

            var results: [String: Result<[UsageItem], Error>] = [:]
            for await (id, result) in group {
                results[id] = result
            }

            providers = plugins.map { id, _, metadata in
                switch results[id] {
                case .success(let items)?:
                    return Provider(
                        id: id,
                        name: metadata.name,
                        icon: metadata.icon,
                        items: items,
                        status: .loaded
                    )
                case .failure(let error)?:
                    return Provider(
                        id: id,
                        name: metadata.name,
                        icon: metadata.icon,
                        items: [],
                        status: .error(error.localizedDescription)
                    )
                case nil:
                    return Provider(
                        id: id,
                        name: metadata.name,
                        icon: metadata.icon,
                        items: [],
                        status: .error("Unknown error")
                    )
                }
            }
        }

        lastUpdated = Date()
    }

    private func loadPlugins() -> [(String, String, PluginMetadata)] {
        let pluginsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker/plugins")

        let bundledDir = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/DefaultPlugins")

        var plugins: [(String, String, PluginMetadata)] = []

        for dir in [pluginsDir, bundledDir] {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ) else { continue }

            for file in files where file.pathExtension == "js" {
                let id = file.deletingPathExtension().lastPathComponent

                if plugins.contains(where: { $0.0 == id }) { continue }

                guard let js = try? String(contentsOf: file, encoding: .utf8) else { continue }

                do {
                    let metadata = try pluginEngine.parseMetadata(from: js, id: id)
                    plugins.append((id, js, metadata))
                } catch {
                    print("Failed to parse plugin \(id): \(error)")
                }
            }
        }

        return plugins
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
