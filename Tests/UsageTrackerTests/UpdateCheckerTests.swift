import Foundation
import Testing
@testable import UsageTracker

@MainActor
@Suite("GitHub release feed parsing")
struct UpdateCheckerTests {
    /// Trimmed-down shape of the GitHub `releases/latest` payload.
    func payload(tag: String = "v1.3.1",
                 draft: Bool = false,
                 prerelease: Bool = false,
                 assets: String = #"[{"name": "UsageTracker.dmg", "browser_download_url": "https://example.com/UsageTracker.dmg"}]"#) -> Data {
        Data("""
        {
          "tag_name": "\(tag)",
          "html_url": "https://example.com/releases/\(tag)",
          "draft": \(draft),
          "prerelease": \(prerelease),
          "assets": \(assets)
        }
        """.utf8)
    }

    @Test("Strips the leading v and picks the DMG asset")
    func parsesTagAndAsset() {
        let result = UpdateChecker.parse(payload())
        #expect(result?.version == "1.3.1")
        #expect(result?.url?.absoluteString == "https://example.com/UsageTracker.dmg")
    }

    @Test("Falls back to the release page when no DMG is attached")
    func fallsBackToReleasePage() {
        let result = UpdateChecker.parse(payload(assets: "[]"))
        #expect(result?.url?.absoluteString == "https://example.com/releases/v1.3.1")
    }

    @Test("Ignores drafts and prereleases")
    func ignoresUnpublished() {
        #expect(UpdateChecker.parse(payload(draft: true)) == nil)
        #expect(UpdateChecker.parse(payload(prerelease: true)) == nil)
    }

    @Test("Returns nil on a payload that is not a release")
    func rejectsGarbage() {
        #expect(UpdateChecker.parse(Data(#"{"message": "Not Found"}"#.utf8)) == nil)
    }

    @Test("Newer version sorts above the current one numerically")
    func versionComparison() {
        // .numeric avoids the lexicographic "1.10.0" < "1.9.0" trap.
        #expect("1.10.0".compare("1.9.0", options: .numeric) == .orderedDescending)
        #expect("1.3.1".compare("1.3.1", options: .numeric) == .orderedSame)
    }
}
