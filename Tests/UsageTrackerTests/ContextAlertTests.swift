import Testing
@testable import UsageTracker

@Suite("Context alert decision logic")
struct ContextAlertTests {
    let threshold = 150_000

    @Test("Fires when a chat first crosses the threshold")
    func firesOnCrossing() {
        let (fire, state) = ContextAlert.evaluate(
            currentContext: 160_000, sessionId: "A", threshold: threshold, state: .init())
        #expect(fire)
        #expect(state.alertedSessionIds == ["A"])
    }

    @Test("Does not re-fire while the same chat stays over the threshold")
    func noRefireSameSession() {
        let (fire, state) = ContextAlert.evaluate(
            currentContext: 200_000, sessionId: "A", threshold: threshold,
            state: .init(alertedSessionIds: ["A"]))
        #expect(!fire)
        #expect(state.alertedSessionIds == ["A"])
    }

    @Test("Re-arms after the alerted chat drops back below (e.g. /compact), then re-fires")
    func reArmsAfterDrop() {
        let (fire, state) = ContextAlert.evaluate(
            currentContext: 90_000, sessionId: "A", threshold: threshold,
            state: .init(alertedSessionIds: ["A"]))
        #expect(!fire)
        #expect(state.alertedSessionIds.isEmpty)  // A re-armed

        let (fire2, state2) = ContextAlert.evaluate(
            currentContext: 160_000, sessionId: "A", threshold: threshold, state: state)
        #expect(fire2)
        #expect(state2.alertedSessionIds == ["A"])
    }

    @Test("A second chat growing large fires its own single alert")
    func secondChatFires() {
        let (fire, state) = ContextAlert.evaluate(
            currentContext: 160_000, sessionId: "B", threshold: threshold,
            state: .init(alertedSessionIds: ["A"]))
        #expect(fire)
        #expect(state.alertedSessionIds == ["A", "B"])
    }

    @Test("Two large chats alternating as active do not re-alert (each already fired once)")
    func alternatingLargeChatsNoSpam() {
        // A and B both already alerted and still large; the active one flips between them.
        var state = ContextAlert.State(alertedSessionIds: ["A", "B"])
        for sid in ["A", "B", "A", "B"] {
            let (fire, next) = ContextAlert.evaluate(
                currentContext: 160_000, sessionId: sid, threshold: threshold, state: state)
            #expect(!fire)
            state = next
        }
        #expect(state.alertedSessionIds == ["A", "B"])
    }

    @Test("Detour to a below-threshold chat does not re-alert a still-large chat on return")
    func detourDoesNotReArmStillLargeChat() {
        // A alerted and still large; briefly a different, small chat B is active.
        let (fire1, s1) = ContextAlert.evaluate(
            currentContext: 90_000, sessionId: "B", threshold: threshold,
            state: .init(alertedSessionIds: ["A"]))
        #expect(!fire1)
        #expect(s1.alertedSessionIds == ["A"])  // A untouched — B was never over, isn't tracked

        // Returning to still-large A: no alert, because A never dropped below.
        let (fire2, _) = ContextAlert.evaluate(
            currentContext: 160_000, sessionId: "A", threshold: threshold, state: s1)
        #expect(!fire2)
    }

    @Test("Exactly at the threshold counts as crossed")
    func boundaryInclusive() {
        let (fire, _) = ContextAlert.evaluate(
            currentContext: 150_000, sessionId: "A", threshold: threshold, state: .init())
        #expect(fire)
    }

    @Test("No active-chat data leaves state untouched and does not fire")
    func noDataNoFire() {
        let start = ContextAlert.State(alertedSessionIds: ["A"])
        let (fire, state) = ContextAlert.evaluate(
            currentContext: nil, sessionId: nil, threshold: threshold, state: start)
        #expect(!fire)
        #expect(state == start)
    }
}
