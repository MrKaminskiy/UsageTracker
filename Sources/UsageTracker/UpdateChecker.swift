import Foundation

@MainActor
class UpdateChecker: ObservableObject {
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String?
    @Published var downloadURL: URL?
    @Published private(set) var isChecking = false
    /// When the feed last answered, so About says "up to date" only after a real check.
    @Published private(set) var checkedAt: Date?
    /// The last check got no usable answer (offline, rate-limited, unreadable feed).
    @Published private(set) var lastCheckFailed = false

    /// GitHub Releases API endpoint for the latest published release.
    private let feedURL: URL?

    init(feedURL: String = "https://api.github.com/repos/MrKaminskiy/UsageTracker/releases/latest") {
        self.feedURL = URL(string: feedURL)
    }

    func check() async {
        guard let feedURL, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: feedURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("UsageTracker", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let release = Self.parse(data) else {
                lastCheckFailed = true
                return
            }
            checkedAt = Date()
            lastCheckFailed = false

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            if release.version.compare(currentVersion, options: .numeric) == .orderedDescending {
                updateAvailable = true
                latestVersion = release.version
                downloadURL = release.url
            }
        } catch {
            // Best-effort: only About surfaces this, and only as a status line.
            lastCheckFailed = true
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
