import Testing
import Foundation
@testable import UsageTracker

@Suite("CodexProvider presentation helpers")
struct CodexProviderTests {
    @Test("Labels known usage windows")
    func windowLabels() {
        let fiveHours = CodexProvider.UsageResponse.Window(usedPercent: 1, limitWindowSeconds: 18_000, resetAfterSeconds: nil, resetAt: nil)
        let week = CodexProvider.UsageResponse.Window(usedPercent: 1, limitWindowSeconds: 604_800, resetAfterSeconds: nil, resetAt: nil)
        #expect(CodexProvider.windowLabel(fiveHours, fallback: "Session") == "5h")
        #expect(CodexProvider.windowLabel(week, fallback: "Weekly") == "Weekly")
    }

    @Test("Formats plan names")
    func planLabels() {
        #expect(CodexProvider.planLabel(from: "chatgpt_plus") == "Chatgpt Plus")
        #expect(CodexProvider.planLabel(from: nil) == nil)
    }

    // Live wham/usage shape from 2026-10-13 (Plus plan), identifiers replaced.
    private static let liveResponse = """
    {
      "user_id": "user-test", "account_id": "acct-test", "email": "test@example.com",
      "plan_type": "plus",
      "rate_limit": {
        "allowed": true, "limit_reached": false,
        "primary_window": { "used_percent": 21, "limit_window_seconds": 18000, "reset_after_seconds": 9925, "reset_at": 1791907239 },
        "secondary_window": { "used_percent": 3, "limit_window_seconds": 604800, "reset_after_seconds": 596725, "reset_at": 1792494039 }
      },
      "code_review_rate_limit": null,
      "additional_rate_limits": null,
      "model_usage": { "gpt-6-astra": { "available": true, "available_at": null, "credits_would_enable": false } },
      "credits": { "has_credits": false, "unlimited": false, "overage_limit_reached": false, "balance": "0",
                   "approx_local_messages": [0, 0], "approx_cloud_messages": [0, 0] },
      "spend_control": { "reached": false, "individual_limit": null },
      "rate_limit_reached_type": null,
      "promo": null,
      "rate_limit_reset_credits": { "available_count": 3, "applicable_available_count": 0 }
    }
    """

    @Test("Decodes today's live response; no-credit accounts show no balance")
    func decodesLiveResponse() throws {
        let usage = try JSONDecoder().decode(CodexProvider.UsageResponse.self, from: Data(Self.liveResponse.utf8))
        #expect(usage.rateLimit?.primaryWindow?.usedPercent == 21)
        #expect(usage.additionalRateLimits == nil)
        #expect(CodexProvider.creditBalance(usage.credits) == nil)
    }

    @Test("Credit balance reflects has_credits and unlimited")
    func creditBalance() {
        #expect(CodexProvider.creditBalance(.init(hasCredits: true, unlimited: false, balance: "12.5")) == "12.5")
        #expect(CodexProvider.creditBalance(.init(hasCredits: true, unlimited: true, balance: "0")) == "Unlimited")
        #expect(CodexProvider.creditBalance(.init(hasCredits: nil, unlimited: nil, balance: "4")) == "4")
        #expect(CodexProvider.creditBalance(nil) == nil)
    }

    @Test("Separately metered limits become their own rows with stable pin keys")
    func additionalLimits() throws {
        let json = """
        [{ "limit_name": "GPT-5.3-Codex-Spark", "metered_feature": "codex_bengalfox",
           "rate_limit": { "allowed": true, "limit_reached": false,
             "primary_window": { "used_percent": 40, "limit_window_seconds": 18000, "reset_after_seconds": 600, "reset_at": 1791907239 },
             "secondary_window": { "used_percent": 9, "limit_window_seconds": 604800, "reset_after_seconds": 86400, "reset_at": 1792494039 } } },
         { "limit_name": null, "metered_feature": null, "rate_limit": null }]
        """
        let limits = try JSONDecoder().decode([CodexProvider.UsageResponse.AdditionalRateLimit].self, from: Data(json.utf8))
        let items = CodexProvider.additionalLimitItems(limits)
        #expect(items.map(\.label) == ["GPT-5.3-Codex-Spark 5h", "GPT-5.3-Codex-Spark Weekly"])
        #expect(items.map(\.stablePinKey) == ["codex_bengalfox.Session", "codex_bengalfox.Weekly"])
        #expect(items[0].current == 40)
        #expect(items[0].resetLabel == "10m")
    }

    @Test("Windows are named by length, so a Pro plan's lone weekly window isn't called a session")
    func windowLabelsByLength() {
        func label(_ seconds: Int, _ fallback: String = "Session") -> String {
            CodexProvider.windowLabel(.init(usedPercent: 1, limitWindowSeconds: seconds, resetAfterSeconds: nil, resetAt: nil), fallback: fallback)
        }
        #expect(label(604_800) == "Weekly")
        #expect(label(86_400) == "Daily")
        #expect(label(2_592_000) == "Monthly")
        #expect(label(31_536_000) == "Annual")
        #expect(label(3 * 86_400) == "Session")
    }

    @Test("Workspace monthly credit cap reads string amounts")
    func spendControl() throws {
        let json = """
        { "reached": false, "individual_limit": { "source": "workspace", "limit": "500", "used": "125.5",
          "remaining": "374.5", "used_percent": 25.1, "remaining_percent": 74.9,
          "reset_after_seconds": 7200, "reset_at": 1792494039 } }
        """
        let control = try JSONDecoder().decode(CodexProvider.UsageResponse.SpendControl.self, from: Data(json.utf8))
        let item = try #require(CodexProvider.spendControlItem(control))
        #expect(item.label == "Monthly credits")
        #expect(item.current == 25.1)
        #expect(item.resetLabel == "125.50/500")
        // Amounts own the trailing slot; a reset date would make cache restores overwrite them.
        #expect(item.resetsAt == nil)

        let remainingOnly = CodexProvider.UsageResponse.SpendControl(individualLimit: .init(limit: 400, remaining: 300, remainingPercent: 75))
        #expect(CodexProvider.spendControlItem(remainingOnly)?.current == 25)
        #expect(CodexProvider.spendControlItem(remainingOnly)?.resetLabel == "100/400")

        let noPercent = CodexProvider.UsageResponse.SpendControl(individualLimit: .init(limit: 200, used: 50))
        #expect(CodexProvider.spendControlItem(noPercent)?.current == 25)
        #expect(CodexProvider.spendControlItem(.init(individualLimit: nil)) == nil)
    }

    @Test("A spend cap in an unexpected shape doesn't break the response")
    func spendControlLenient() throws {
        let json = """
        { "plan_type": "business",
          "rate_limit": { "primary_window": { "used_percent": 5, "limit_window_seconds": 18000 } },
          "spend_control": { "reached": true, "individual_limit": { "limit": [1], "used_percent": "nan",
                                                                     "reset_after_seconds": "1e30" } },
          "additional_rate_limits": [null, 7, { "limit_name": "Spark", "rate_limit": { "primary_window": { "used_percent": 1 } } }],
          "rate_limit_reset_credits": { "available_count": "3" } }
        """
        let usage = try JSONDecoder().decode(CodexProvider.UsageResponse.self, from: Data(json.utf8))
        #expect(usage.rateLimit?.primaryWindow?.usedPercent == 5)
        #expect(CodexProvider.spendControlItem(usage.spendControl) == nil)
        #expect(usage.spendControl?.individualLimit?.resetAfterSeconds == nil)
        #expect(usage.additionalRateLimits?.elements.map(\.limitName) == ["Spark"])
        #expect(usage.rateLimitResetCredits?.availableCount == nil)

        let notAnObject = try JSONDecoder().decode(CodexProvider.UsageResponse.self,
                                                   from: Data(#"{ "spend_control": { "individual_limit": "none" } }"#.utf8))
        #expect(CodexProvider.spendControlItem(notAnObject.spendControl) == nil)
    }

    @Test("Pin keys follow window length and never collide")
    func pinKeys() {
        func window(_ seconds: Int) -> CodexProvider.UsageResponse.Window {
            .init(usedPercent: 1, limitWindowSeconds: seconds, resetAfterSeconds: nil, resetAt: nil)
        }
        // Plus: 5h primary + weekly secondary keep their historical keys.
        #expect(CodexProvider.pinKey(for: window(18_000), fallback: "Session") == "Session")
        #expect(CodexProvider.pinKey(for: window(604_800), fallback: "Weekly") == "Weekly")
        // Pro: the lone weekly window arrives in the primary slot.
        #expect(CodexProvider.pinKey(for: window(604_800), fallback: "Session") == "Weekly")
        // Weekly primary + monthly secondary stay distinct.
        #expect(CodexProvider.pinKey(for: window(2_592_000), fallback: "Weekly") == "Monthly")
        #expect(CodexProvider.pinKey(for: nil, fallback: "Weekly") == "Weekly")
    }

    @Test("Plan families collapse to their marketing name")
    func planFamilies() {
        #expect(CodexProvider.planLabel(from: "self_serve_business_usage_based") == "Business")
        #expect(CodexProvider.planLabel(from: "enterprise_cbp_automation") == "Enterprise")
        #expect(CodexProvider.planLabel(from: "prolite") == "Pro Lite")
        #expect(CodexProvider.planLabel(from: "plus") == "Plus")
    }
}
