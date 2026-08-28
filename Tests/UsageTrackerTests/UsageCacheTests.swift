import Foundation
import Testing
@testable import UsageTracker

@Suite("UsageCache restore")
struct UsageCacheRestoreTests {

    // Fixed reference point; never `Date()`, so a slow test can't drift across a boundary.
    // Anchored at local midday so the same-calendar-day rule in `restore` can't flip on a
    // runner whose timezone puts this instant near midnight.
    private let now = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0,
        of: Date(timeIntervalSince1970: 1_800_000_000)
    )!

    private func provider(
        id: String = "claude",
        fetchedAt: Date,
        items: [UsageCache.CachedItem]
    ) -> UsageCache.CachedProvider {
        UsageCache.CachedProvider(
            id: id, name: id.capitalized, icon: "brain",
            fetchedAt: fetchedAt, items: items, planLabel: "Max"
        )
    }

    private func item(
        label: String = "Session",
        current: Double = 42,
        resetLabel: String? = nil,
        resetsAt: Date?,
        isExtraUsage: Bool = false
    ) -> UsageCache.CachedItem {
        UsageCache.CachedItem(
            label: label, current: current, limit: 100,
            resetLabel: resetLabel, resetsAt: resetsAt,
            pinKey: nil, isExtraUsage: isExtraUsage
        )
    }

    @Test("A fresh snapshot restores its rows and reports when the data was fetched")
    func restoresFreshSnapshot() {
        let fetchedAt = now.addingTimeInterval(-5 * 60)
        let snap = UsageCache.Snapshot(providers: [
            provider(fetchedAt: fetchedAt, items: [item(resetsAt: now.addingTimeInterval(3 * 3600))])
        ])

        let restored = UsageCache.restore(snap, now: now)

        #expect(restored?.savedAt == fetchedAt)
        #expect(restored?.providers.count == 1)
        #expect(restored?.providers.first?.planLabel == "Max")
        #expect(restored?.providers.first?.items.first?.percentage == 42)
        #expect(restored?.providers.first?.status == .loaded)
    }

    @Test("The reset countdown is recomputed against now, not the label saved earlier")
    func recomputesResetLabel() {
        // Saved 3h ago when the window had 4h left; only 1h remains now.
        let snap = UsageCache.Snapshot(providers: [
            provider(
                fetchedAt: now.addingTimeInterval(-3 * 3600),
                items: [item(resetLabel: "4h 0m", resetsAt: now.addingTimeInterval(3600))]
            )
        ])

        let restored = UsageCache.restore(snap, now: now)

        #expect(restored?.providers.first?.items.first?.resetLabel == "1h 0m")
    }

    @Test("A label with no reset deadline is the reading itself and survives verbatim")
    func keepsNonCountdownLabels() {
        // OpenAI, OpenRouter, Stability and Runway put their only meaningful figure in
        // resetLabel and never set resetsAt. Recomputing it would blank the row.
        let snap = UsageCache.Snapshot(providers: [
            provider(id: "openai", fetchedAt: now.addingTimeInterval(-60), items: [
                item(label: "Spend", current: 0, resetLabel: "$12.34 this month", resetsAt: nil)
            ])
        ])

        let restored = UsageCache.restore(snap, now: now)

        #expect(restored?.providers.first?.items.first?.resetLabel == "$12.34 this month")
    }

    @Test("An item whose window already reset is dropped rather than shown stale")
    func dropsExpiredItems() {
        let snap = UsageCache.Snapshot(providers: [
            provider(fetchedAt: now.addingTimeInterval(-2 * 3600), items: [
                item(label: "Session", resetsAt: now.addingTimeInterval(-60)),
                item(label: "Weekly", resetsAt: now.addingTimeInterval(4 * 24 * 3600))
            ])
        ])

        let restored = UsageCache.restore(snap, now: now)

        #expect(restored?.providers.first?.items.map(\.label) == ["Weekly"])
    }

    @Test("A provider whose every window reset is dropped, leaving nothing to restore")
    func dropsProviderWithNoLiveItems() {
        let snap = UsageCache.Snapshot(providers: [
            provider(fetchedAt: now.addingTimeInterval(-2 * 3600),
                     items: [item(resetsAt: now.addingTimeInterval(-60))])
        ])

        #expect(UsageCache.restore(snap, now: now) == nil)
    }

    @Test("Staleness is per provider: an old reading drops while a fresh one restores")
    func agesProvidersIndependently() {
        let snap = UsageCache.Snapshot(providers: [
            provider(id: "claude", fetchedAt: now.addingTimeInterval(-(UsageCache.maxAge + 60)),
                     items: [item(resetsAt: now.addingTimeInterval(3600))]),
            provider(id: "codex", fetchedAt: now.addingTimeInterval(-120),
                     items: [item(resetsAt: now.addingTimeInterval(3600))])
        ])

        let restored = UsageCache.restore(snap, now: now)

        #expect(restored?.providers.map(\.id) == ["codex"])
        #expect(restored?.savedAt == now.addingTimeInterval(-120))
    }

    @Test("A reading stamped in the future (clock change) is ignored")
    func ignoresFutureTimestamp() {
        let snap = UsageCache.Snapshot(providers: [
            provider(fetchedAt: now.addingTimeInterval(60),
                     items: [item(resetsAt: now.addingTimeInterval(3600))])
        ])

        #expect(UsageCache.restore(snap, now: now) == nil)
    }

    @Test("Extra-usage items keep their kind, so popover filtering still applies")
    func preservesExtraUsageKind() {
        let snap = UsageCache.Snapshot(providers: [
            provider(fetchedAt: now.addingTimeInterval(-60),
                     items: [item(label: "Extra", resetLabel: "5/50", resetsAt: nil, isExtraUsage: true)])
        ])

        let restored = UsageCache.restore(snap, now: now)

        #expect(restored?.providers.first?.items.first?.kind == .extraUsage)
    }

    @Test("A snapshot survives an encode/decode round trip")
    func roundTripsThroughJSON() throws {
        let snap = UsageCache.Snapshot(providers: [
            provider(fetchedAt: now.addingTimeInterval(-60),
                     items: [item(resetsAt: now.addingTimeInterval(3600))])
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(UsageCache.Snapshot.self, from: encoder.encode(snap))

        #expect(UsageCache.restore(decoded, now: now)?.providers.first?.items.first?.current == 42)
    }
}

@Suite("relativeResetLabel")
struct RelativeResetLabelTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Formats minutes, hours, and days; nil once the deadline passes")
    func formatsEachRange() {
        #expect(relativeResetLabel(now.addingTimeInterval(45 * 60), now: now) == "45m")
        #expect(relativeResetLabel(now.addingTimeInterval(4 * 3600 + 47 * 60), now: now) == "4h 47m")
        #expect(relativeResetLabel(now.addingTimeInterval(6 * 24 * 3600), now: now) == "6d")
        #expect(relativeResetLabel(now.addingTimeInterval(-1), now: now) == nil)
        #expect(relativeResetLabel(nil, now: now) == nil)
    }
}

@Suite("UsageCache merge")
struct UsageCacheMergeTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func cached(id: String, fetchedAt: Date, current: Double = 42) -> UsageCache.CachedProvider {
        UsageCache.CachedProvider(
            id: id, name: id.capitalized, icon: "brain", fetchedAt: fetchedAt,
            items: [UsageCache.CachedItem(
                label: "Session", current: current, limit: 100,
                resetLabel: nil, resetsAt: nil, pinKey: nil, isExtraUsage: false
            )],
            planLabel: nil
        )
    }

    private func live(id: String, status: ProviderStatus, current: Double = 42) -> Provider {
        Provider(
            id: id, name: id.capitalized, icon: "brain",
            items: status == .loaded
                ? [UsageItem(label: "Session", current: current, limit: 100, resetLabel: nil)]
                : [],
            status: status
        )
    }

    @Test("A provider that threw keeps its stored reading AND its original age")
    func carriedForwardProviderKeepsItsAge() {
        // refresh() re-adds last-known data to `providers` for anything that threw. Restamping
        // it would renew the age on every failed refresh and maxAge could never retire it.
        let fetchedAt = now.addingTimeInterval(-6 * 3600)
        let existing = [cached(id: "claude", fetchedAt: fetchedAt)]

        // Carried forward in memory, so it looks .loaded — but it is not in freshlyFetched.
        let merged = UsageCache.merging([live(id: "claude", status: .loaded)],
                                        into: existing, freshlyFetched: [], now: now)

        #expect(merged.count == 1)
        #expect(merged.first?.fetchedAt == fetchedAt)
    }

    @Test("Repeated failed refreshes cannot keep a reading alive past its max age")
    func repeatedFailuresStillExpire() {
        let existing = [cached(id: "claude", fetchedAt: now.addingTimeInterval(-(UsageCache.maxAge + 60)))]

        let merged = UsageCache.merging([live(id: "claude", status: .loaded)],
                                        into: existing, freshlyFetched: [], now: now)

        #expect(merged.isEmpty)
    }

    @Test("A fresh reading replaces the stored one and is restamped")
    func freshReadingReplaces() {
        let existing = [cached(id: "claude", fetchedAt: now.addingTimeInterval(-3600), current: 10)]

        let merged = UsageCache.merging([live(id: "claude", status: .loaded, current: 88)],
                                        into: existing, freshlyFetched: ["claude"], now: now)

        #expect(merged.first?.fetchedAt == now)
        #expect(merged.first?.items.first?.current == 88)
    }

    @Test("One provider's error does not erase its own cache, nor another's")
    func errorLeavesStoredReadingsIntact() {
        // Most providers return .error for an HTTP failure rather than throwing, so an
        // overwrite-everything save would drop a perfectly good earlier reading.
        let existing = [
            cached(id: "claude", fetchedAt: now.addingTimeInterval(-3600), current: 10),
            cached(id: "cursor", fetchedAt: now.addingTimeInterval(-3600), current: 20)
        ]

        let merged = UsageCache.merging(
            [live(id: "claude", status: .loaded, current: 55),
             live(id: "cursor", status: .error("Service unavailable"))],
            into: existing, freshlyFetched: ["claude", "cursor"], now: now
        )

        #expect(merged.map(\.id) == ["claude", "cursor"])
        #expect(merged.first(where: { $0.id == "claude" })?.items.first?.current == 55)
        #expect(merged.first(where: { $0.id == "cursor" })?.items.first?.current == 20)
    }

    @Test("Signing out removes the stored reading rather than leaving stale usage behind")
    func notConnectedClearsEntry() {
        let existing = [cached(id: "cursor", fetchedAt: now.addingTimeInterval(-3600))]

        let merged = UsageCache.merging(
            [live(id: "cursor", status: .notConnected(url: URL(string: "https://example.com")!))],
            into: existing, freshlyFetched: ["cursor"], now: now
        )

        #expect(merged.isEmpty)
    }

    @Test("A fresh provider with no items does not overwrite a good stored reading")
    func emptyLoadedDoesNotOverwrite() {
        let existing = [cached(id: "claude", fetchedAt: now.addingTimeInterval(-3600), current: 33)]
        var empty = live(id: "claude", status: .loaded)
        empty.items = []

        let merged = UsageCache.merging([empty], into: existing,
                                        freshlyFetched: ["claude"], now: now)

        #expect(merged.first?.items.first?.current == 33)
    }
}

@Suite("UsageCache day boundary")
struct UsageCacheDayBoundaryTests {

    // Midday, so "yesterday" and "today" are unambiguous regardless of the runner's timezone.
    private let now = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0,
        of: Date(timeIntervalSince1970: 1_800_000_000)
    )!

    private func snapshot(fetchedAt: Date, resetsAt: Date?) -> UsageCache.Snapshot {
        UsageCache.Snapshot(providers: [
            UsageCache.CachedProvider(
                id: "openai", name: "OpenAI", icon: "sparkles", fetchedAt: fetchedAt,
                items: [UsageCache.CachedItem(
                    label: "Today", current: 5, limit: 100,
                    resetLabel: "$1.20 today", resetsAt: resetsAt,
                    pinKey: nil, isExtraUsage: false
                )],
                planLabel: nil
            )
        ])
    }

    @Test("A period row with no reset deadline survives within the same day")
    func keepsSameDayPeriodRow() {
        let restored = UsageCache.restore(
            snapshot(fetchedAt: now.addingTimeInterval(-2 * 3600), resetsAt: nil), now: now
        )

        #expect(restored?.providers.first?.items.first?.resetLabel == "$1.20 today")
    }

    @Test("A period row with no reset deadline is retired once the day rolls over")
    func retiresPreviousDayPeriodRow() {
        // Yesterday's "$1.20 today" must not be replayed as if it were today's.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!

        #expect(UsageCache.restore(snapshot(fetchedAt: yesterday, resetsAt: nil), now: now) == nil)
    }

    @Test("A row with a real reset deadline is judged by that deadline, not the day")
    func deadlineBeatsDayBoundary() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let restored = UsageCache.restore(
            snapshot(fetchedAt: yesterday, resetsAt: now.addingTimeInterval(4 * 3600)), now: now
        )

        #expect(restored?.providers.first?.items.first?.resetLabel == "4h 0m")
    }
}

@Suite("Transient HTTP status")
struct TransientHTTPStatusTests {

    @Test("429 and 5xx are transient; 4xx client errors are not")
    func classifiesStatuses() {
        #expect(isTransientHTTPStatus(429))
        #expect(isTransientHTTPStatus(500))
        #expect(isTransientHTTPStatus(503))
        #expect(!isTransientHTTPStatus(401))
        #expect(!isTransientHTTPStatus(403))
        #expect(!isTransientHTTPStatus(404))
        #expect(!isTransientHTTPStatus(200))
    }
}

@Suite("AppState carry-forward")
@MainActor
struct CarriedForwardTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func provider(id: String = "claude",
                          fetchedAt: Date?,
                          resetsAt: Date?) -> Provider {
        var p = Provider(
            id: id, name: id.capitalized, icon: "brain",
            items: [UsageItem(label: "Session", current: 42, limit: 100,
                              resetLabel: "stale", resetsAt: resetsAt)],
            status: .loaded
        )
        p.fetchedAt = fetchedAt
        return p
    }

    @Test("A provider that answered this refresh is not carried forward")
    func skipsFreshProviders() {
        let existing = [provider(fetchedAt: now, resetsAt: now.addingTimeInterval(3600))]

        #expect(AppState.carriedForward(existing, excluding: ["claude"], now: now).isEmpty)
    }

    @Test("A recent reading is carried forward when its provider failed")
    func carriesRecentReading() {
        let existing = [provider(fetchedAt: now.addingTimeInterval(-600),
                                 resetsAt: now.addingTimeInterval(3600))]

        let carried = AppState.carriedForward(existing, excluding: [], now: now)

        #expect(carried.count == 1)
        #expect(carried.first?.items.first?.current == 42)
    }

    @Test("A reading past the max age is retired instead of shown indefinitely")
    func retiresAgedReading() {
        // The app can stay open for days; without this the last good reading would sit on
        // screen forever while every refresh kept failing.
        let existing = [provider(fetchedAt: now.addingTimeInterval(-(UsageCache.maxAge + 60)),
                                 resetsAt: now.addingTimeInterval(3600))]

        #expect(AppState.carriedForward(existing, excluding: [], now: now).isEmpty)
    }

    @Test("An item whose reset window elapsed while the app ran is dropped")
    func dropsElapsedWindow() {
        let existing = [provider(fetchedAt: now.addingTimeInterval(-600),
                                 resetsAt: now.addingTimeInterval(-1))]

        #expect(AppState.carriedForward(existing, excluding: [], now: now).isEmpty)
    }

    @Test("A carried-forward countdown is recomputed, not frozen at fetch time")
    func recomputesCarriedCountdown() {
        let existing = [provider(fetchedAt: now.addingTimeInterval(-600),
                                 resetsAt: now.addingTimeInterval(2 * 3600))]

        let carried = AppState.carriedForward(existing, excluding: [], now: now)

        #expect(carried.first?.items.first?.resetLabel == "2h 0m")
    }

    @Test("A reading with no fetchedAt (pre-existing in-memory data) is kept")
    func keepsUnstampedReading() {
        let existing = [provider(fetchedAt: nil, resetsAt: nil)]

        #expect(AppState.carriedForward(existing, excluding: [], now: now).count == 1)
    }
}

@Suite("Carry-forward and restore edge cases")
@MainActor
struct CacheFreshnessEdgeTests {

    private let now = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0,
        of: Date(timeIntervalSince1970: 1_800_000_000)
    )!

    @Test("A daily figure carried in memory is dropped once the day rolls over")
    func carriedDailyFigureExpiresAtMidnight() {
        // The app can sit open across midnight; yesterday's "$1.20 today" must not survive it.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        var p = Provider(
            id: "openrouter", name: "OpenRouter", icon: "arrow.trianglehead.branch",
            items: [UsageItem(label: "Daily Spend", current: 3, limit: 100,
                              resetLabel: "$1.20 today", resetsAt: nil)],
            status: .loaded
        )
        p.fetchedAt = yesterday

        #expect(AppState.carriedForward([p], excluding: [], now: now).isEmpty)
    }

    @Test("Freshness reflects a provider that survived, not one whose items all expired")
    func savedAtIgnoresDiscardedProviders() {
        let recent = now.addingTimeInterval(-60)
        let older = now.addingTimeInterval(-3 * 3600)
        let snap = UsageCache.Snapshot(providers: [
            // Newest reading, but its only window has already reset — contributes no rows.
            UsageCache.CachedProvider(
                id: "codex", name: "Codex", icon: "terminal.fill", fetchedAt: recent,
                items: [UsageCache.CachedItem(label: "5h", current: 1, limit: 100,
                                              resetLabel: nil, resetsAt: now.addingTimeInterval(-1),
                                              pinKey: nil, isExtraUsage: false)],
                planLabel: nil
            ),
            UsageCache.CachedProvider(
                id: "claude", name: "Claude", icon: "brain", fetchedAt: older,
                items: [UsageCache.CachedItem(label: "Session", current: 42, limit: 100,
                                              resetLabel: nil, resetsAt: now.addingTimeInterval(3600),
                                              pinKey: nil, isExtraUsage: false)],
                planLabel: nil
            )
        ])

        let restored = UsageCache.restore(snap, now: now)

        #expect(restored?.providers.map(\.id) == ["claude"])
        #expect(restored?.savedAt == older)
    }
}
