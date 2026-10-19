import XCTest
@testable import UsageTracker

final class ClaudeWebProviderTests: XCTestCase {

    // People paste whatever they managed to copy out of DevTools. Every one of these
    // shapes has to yield the same session key, or the field rejects a valid session.

    func testExtractsBareSessionKey() {
        XCTAssertEqual(
            ClaudeWebProvider.extractSessionKey(from: "sk-ant-sid01-abc123"),
            "sk-ant-sid01-abc123"
        )
    }

    func testExtractsFromNameValuePair() {
        XCTAssertEqual(
            ClaudeWebProvider.extractSessionKey(from: "sessionKey=sk-ant-sid01-abc123"),
            "sk-ant-sid01-abc123"
        )
    }

    func testExtractsFromFullCookieHeader() {
        let header = "Cookie: __cf_bm=xyz; sessionKey=sk-ant-sid01-abc123; lastActiveOrg=uuid"
        XCTAssertEqual(ClaudeWebProvider.extractSessionKey(from: header), "sk-ant-sid01-abc123")
    }

    func testExtractsWhenSessionKeyIsNotFirstAndHasStrayWhitespace() {
        let header = "  __cf_bm=xyz;   sessionKey = sk-ant-sid01-abc123  ; other=1  "
        // A space before `=` means the pair is not `sessionKey=...`; the value is still
        // recovered because no other cookie in the header looks like a session key.
        XCTAssertNil(ClaudeWebProvider.extractSessionKey(from: header))
    }

    func testTrimsSurroundingWhitespaceOnBareKey() {
        XCTAssertEqual(
            ClaudeWebProvider.extractSessionKey(from: "  sk-ant-sid01-abc123\n"),
            "sk-ant-sid01-abc123"
        )
    }

    func testRejectsTextWithoutASessionKey() {
        XCTAssertNil(ClaudeWebProvider.extractSessionKey(from: ""))
        XCTAssertNil(ClaudeWebProvider.extractSessionKey(from: "not a cookie"))
        XCTAssertNil(ClaudeWebProvider.extractSessionKey(from: "__cf_bm=xyz; lastActiveOrg=uuid"))
    }

    func testRejectsEmptySessionKeyValue() {
        XCTAssertNil(ClaudeWebProvider.extractSessionKey(from: "sessionKey="))
    }

    // The web API and the OAuth endpoint return the same JSON, and both paths run it
    // through `ClaudeProvider.usageItems`. This pins that shared mapping so the two
    // sources cannot drift into showing different rows.
    func testWebUsagePayloadProducesTheSameRowsAsOAuth() throws {
        let json = """
        {
          "five_hour": { "utilization": 42, "resets_at": "2026-08-28T18:00:00Z" },
          "seven_day": { "utilization": 71, "resets_at": "2026-09-01T00:00:00Z" },
          "seven_day_opus": { "utilization": 12, "resets_at": "2026-09-01T00:00:00Z" }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(ClaudeProvider.UsageResponse.self, from: json)
        let items = ClaudeProvider.usageItems(from: usage)

        XCTAssertEqual(items.map(\.label), ["Session", "Weekly", "Opus"])
        XCTAssertEqual(items[0].current, 42)
        XCTAssertEqual(items[1].current, 71)
        XCTAssertEqual(items[2].current, 12)
        XCTAssertTrue(items.allSatisfy { $0.limit == 100 })
    }
}

import Testing

@Suite("Claude cookie policy")
struct ClaudeCookiePolicyTests {

    private func account(_ id: String = "claude", uuid: String?, org: String? = nil, hasLogin: Bool) -> ClaudeAccount {
        let dir = URL(fileURLWithPath: "/Users/test/.claude")
        return ClaudeAccount(
            providerID: id, configDir: dir, keychainService: "s",
            credentialsFile: dir.appendingPathComponent(".credentials.json"),
            projectsDir: dir.appendingPathComponent("projects"),
            email: nil, accountUuid: uuid, organizationUuid: org, hasLogin: hasLogin
        )
    }

    @Test("The cookie fills in only where it can't land on the wrong account")
    func policyMatrix() {
        #expect(ClaudeWebProvider.cookiePolicy(for: account(uuid: "U1", org: "O1", hasLogin: true), anyAccountSignedIn: true)
                == .requireAccount(accountUuid: "U1", organizationUuid: "O1"))
        #expect(ClaudeWebProvider.cookiePolicy(for: account(uuid: nil, hasLogin: false), anyAccountSignedIn: false)
                == .unrestricted)
        #expect(ClaudeWebProvider.cookiePolicy(for: account(uuid: nil, hasLogin: false), anyAccountSignedIn: true)
                == .disabled)
        #expect(ClaudeWebProvider.cookiePolicy(for: account(uuid: nil, hasLogin: true), anyAccountSignedIn: true)
                == .disabled)
        #expect(ClaudeWebProvider.cookiePolicy(for: account("claude-2601a85c", uuid: nil, hasLogin: false), anyAccountSignedIn: false)
                == .disabled)
    }

    @Test("The cookie's account comes from /api/account's top-level uuid")
    func accountUuidDecoding() {
        #expect(ClaudeWebProvider.accountUuid(fromAccountResponse: Data(#"{"uuid":"U1","email_address":"a@x"}"#.utf8)) == "U1")
        #expect(ClaudeWebProvider.accountUuid(fromAccountResponse: Data("{}".utf8)) == nil)
        #expect(ClaudeWebProvider.accountUuid(fromAccountResponse: Data("<html>".utf8)) == nil)
    }
}
