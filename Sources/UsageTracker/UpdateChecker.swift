import Foundation

@MainActor
class UpdateChecker: ObservableObject {
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String?
    @Published var downloadURL: URL?

    /// GitHub Releases API endpoint for the latest published release.
    private let feedURL: URL?

    init(feedURL: String = "https://api.github.com/repos/MrKaminskiy/UsageTracker/releases/latest") {
        self.feedURL = URL(string: feedURL)
    }

    func check() async {
        guard let feedURL else { return }

        var request = URLRequest(url: feedURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("UsageTracker", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            guard let release = Self.parse(data) else { return }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            if release.version.compare(currentVersion, options: .numeric) == .orderedDescending {
                updateAvailable = true
                latestVersion = release.version
                downloadURL = release.url
            }
        } catch {
            // Silently fail — update check is best-effort
        }
    }

    /// Extracts the version and download URL from a GitHub `releases/latest` payload.
    /// Prefers the `.dmg` asset; falls back to the release page.
    static func parse(_ data: Data) -> (version: String, url: URL?)? {
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else { return nil }
        guard !release.draft, !release.prerelease else { return nil }

        // Tags are published as "v1.3.1"; compare on the bare version number.
        var version = release.tagName
        if version.hasPrefix("v") { version.removeFirst() }
        guard !version.isEmpty else { return nil }

        let dmg = release.assets.first { $0.name.hasSuffix(".dmg") }?.browserDownloadURL
        return (version, URL(string: dmg ?? release.htmlURL))
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft, prerelease, assets
        }

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }
    }
}
