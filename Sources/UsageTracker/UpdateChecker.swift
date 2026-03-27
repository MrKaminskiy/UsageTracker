import Foundation

@MainActor
class UpdateChecker: ObservableObject {
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String?
    @Published var downloadURL: URL?

    /// URL to a JSON file with {"version": "x.y.z", "url": "https://..."}
    private let feedURL: URL?

    init(feedURL: String = "https://usagetracker.app/version.json") {
        self.feedURL = URL(string: feedURL)
    }

    func check() async {
        guard let feedURL else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            guard let info = try? JSONDecoder().decode(VersionInfo.self, from: data) else { return }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            if info.version.compare(currentVersion, options: .numeric) == .orderedDescending {
                updateAvailable = true
                latestVersion = info.version
                downloadURL = URL(string: info.url)
            }
        } catch {
            // Silently fail — update check is best-effort
        }
    }

    private struct VersionInfo: Decodable {
        let version: String
        let url: String
    }
}
