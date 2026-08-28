import Foundation

/// Last-known usage, persisted to `~/.usagetracker/usage-cache.json`.
///
/// Without it the popover is empty from launch until the first network round-trip returns —
/// and if that round-trip fails it stays empty. The Claude usage endpoint rate-limits hard
/// (a relaunch plus a short refresh interval is enough to trip a 429 that lasts minutes), and
/// a 429 is deliberately thrown so `refresh()` preserves last-known data. On a cold start
/// there was nothing to preserve, so the user saw "No data yet" with no way to tell a rate
/// limit from a broken sign-in. Seeding from disk gives that fallback a starting point.
///
/// Only what the rows render is stored. Insights and boost status are recomputed locally on
/// the next successful refresh and are not worth persisting.
enum UsageCache {
    /// A provider's reading is ignored once it is this old: a day-stale number is worse than none.
    static let maxAge: TimeInterval = 24 * 60 * 60

    struct Snapshot: Codable {
        var providers: [CachedProvider]
    }

    struct CachedProvider: Codable {
        var id: String
        var name: String
        var icon: String
        /// When this provider's reading actually came back from its source — NOT when the file
        /// was last written. A provider that keeps failing has its previous reading carried
        /// forward untouched, so its age keeps counting and `maxAge` can still retire it.
        var fetchedAt: Date
        var items: [CachedItem]
        var planLabel: String?
    }

    struct CachedItem: Codable {
        var label: String
        var current: Double
        var limit: Double
        /// The trailing text of the row. For Claude and Codex it is a countdown derived from
        /// `resetsAt` and is recomputed on restore; every other provider puts its only
        /// meaningful figure here ("$12.34 this month", "3.5 left") with no `resetsAt` at all,
        /// so the stored string is the data and has to survive the round trip.
        var resetLabel: String?
        var resetsAt: Date?
        var pinKey: String?
        var isExtraUsage: Bool
    }

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker/usage-cache.json")
    }

    // MARK: - Saving

    /// Merges this refresh's results into the stored snapshot.
    ///
    /// `freshlyFetched` is the set of provider ids that actually returned something this cycle
    /// (as opposed to throwing). Merging rather than overwriting matters because `providers`
    /// carries entries that were only carried forward in memory: rewriting those with a new
    /// timestamp would renew their age forever and defeat `maxAge`, and dropping the ones that
    /// merely errored would discard a perfectly good earlier reading over one HTTP 500.
    ///
    /// Per provider: a fresh `.loaded` reading replaces the entry, a fresh `.notConnected`
    /// removes it (genuinely signed out — stale usage would be a lie), and anything else
    /// (`.error`, `.loading`, or a provider that threw) leaves the stored entry as it was.
    static func save(_ providers: [Provider], freshlyFetched: Set<String>, now: Date = Date()) {
        let kept = merging(providers, into: loadSnapshot()?.providers ?? [],
                           freshlyFetched: freshlyFetched, now: now)

        guard !kept.isEmpty else {
            clear()
            return
        }

        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Snapshot(providers: kept)) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    /// Pure part of `save`, so the merge rules are testable without touching the disk.
    static func merging(
        _ providers: [Provider],
        into existing: [CachedProvider],
        freshlyFetched: Set<String>,
        now: Date = Date()
    ) -> [CachedProvider] {
        var stored: [String: CachedProvider] = [:]
        for provider in existing {
            stored[provider.id] = provider
        }

        for provider in providers where freshlyFetched.contains(provider.id) {
            switch provider.status {
            case .loaded where !provider.items.isEmpty:
                stored[provider.id] = CachedProvider(
                    id: provider.id,
                    name: provider.name,
                    icon: provider.icon,
                    fetchedAt: now,
                    items: provider.items.map {
                        CachedItem(
                            label: $0.label,
                            current: $0.current,
                            limit: $0.limit,
                            resetLabel: $0.resetLabel,
                            resetsAt: $0.resetsAt,
                            pinKey: $0.pinKey,
                            isExtraUsage: $0.kind == .extraUsage
                        )
                    },
                    planLabel: provider.planLabel
                )
            case .notConnected:
                stored.removeValue(forKey: provider.id)
            case .loaded, .error, .loading:
                break  // keep whatever reading is already stored
            }
        }

        // Housekeeping: entries past their usable age are dropped on write rather than left to
        // accumulate for a provider the user has stopped using.
        return stored.values
            .filter { now.timeIntervalSince($0.fetchedAt) <= maxAge }
            .sorted { $0.id < $1.id }
    }

    // MARK: - Loading

    private static func loadSnapshot() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }

    /// Restores the snapshot for display at launch, or nil when there is nothing usable.
    static func load(now: Date = Date()) -> (providers: [Provider], savedAt: Date)? {
        guard let snapshot = loadSnapshot() else { return nil }
        return restore(snapshot, now: now)
    }

    /// Pure part of `load`, so the staleness rules are testable without touching the disk.
    static func restore(_ snapshot: Snapshot, now: Date = Date()) -> (providers: [Provider], savedAt: Date)? {
        let usable = snapshot.providers.filter {
            // A reading stamped in the future is a clock change, not something to reason about.
            $0.fetchedAt <= now && now.timeIntervalSince($0.fetchedAt) <= maxAge
        }

        let providers: [Provider] = usable.compactMap { cached in
            // An item whose window has already reset carries a percentage that is certainly
            // wrong now, so it is dropped rather than shown stale.
            //
            // Items with no `resetsAt` can't be checked that way, and some of them are still
            // period-scoped: OpenAI's "$12.34 this month" and OpenRouter's "$1.20 today" would
            // otherwise be replayed into the following day as if they were current. Requiring
            // the same calendar day retires those. It also retires standing figures like a
            // credit balance overnight, which is the safer way to be wrong — one successful
            // refresh brings them straight back.
            let sameDay = Calendar.current.isDate(cached.fetchedAt, inSameDayAs: now)
            let items: [UsageItem] = cached.items.compactMap { item in
                guard item.resetsAt != nil || sameDay else { return nil }
                if let resetsAt = item.resetsAt, resetsAt <= now { return nil }
                return UsageItem(
                    label: item.label,
                    current: item.current,
                    limit: item.limit,
                    // Recompute a countdown from its deadline; keep any other label verbatim,
                    // since for most providers that string is the reading itself.
                    resetLabel: item.resetsAt == nil
                        ? item.resetLabel
                        : relativeResetLabel(item.resetsAt, now: now),
                    resetsAt: item.resetsAt,
                    pinKey: item.pinKey,
                    kind: item.isExtraUsage ? .extraUsage : .standard
                )
            }
            guard !items.isEmpty else { return nil }
            var restored = Provider(
                id: cached.id,
                name: cached.name,
                icon: cached.icon,
                items: items,
                status: .loaded,
                planLabel: cached.planLabel
            )
            // Carried so that a restored reading kept across later failed refreshes still ages
            // out in memory, instead of living on screen for as long as the app stays open.
            restored.fetchedAt = cached.fetchedAt
            return restored
        }

        // Freshness has to come from what actually survived: a provider whose items all
        // expired contributes no rows, so letting its timestamp win would label the older
        // readings that did survive as more recent than they are.
        let survivingIDs = Set(providers.map(\.id))
        guard !providers.isEmpty,
              let newest = usable.filter({ survivingIDs.contains($0.id) })
                  .map(\.fetchedAt).max() else { return nil }
        return (providers, newest)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
