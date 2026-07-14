import Foundation
import SQLite3

actor CodexInsightsAnalyzer {
    struct ThreadRecord: Equatable, Sendable {
        let id: String
        let title: String
        let cwd: String
        let model: String?
        let tokensUsed: Int
        let createdAt: Date
        let updatedAt: Date
    }

    func analyze(now: Date = Date(), calendar: Calendar = .current) -> CodexInsights? {
        guard let databaseURL = stateDatabaseURL(),
              let records = loadThreads(from: databaseURL) else { return nil }
        return Self.aggregate(records: records, now: now, calendar: calendar)
    }

    static func aggregate(records: [ThreadRecord], now: Date, calendar: Calendar = .current) -> CodexInsights {
        let dayStart = calendar.startOfDay(for: now)
        let today = records.filter { $0.updatedAt >= dayStart && $0.updatedAt <= now.addingTimeInterval(1) }
        let recent = records
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)
            .map { record in
                CodexThreadSummary(
                    id: record.id,
                    title: record.title.isEmpty ? "Untitled chat" : record.title,
                    project: projectName(from: record.cwd),
                    model: record.model,
                    tokensUsed: record.tokensUsed,
                    updatedAt: record.updatedAt
                )
            }
        let models = Dictionary(grouping: today, by: { $0.model ?? "Unknown" })
            .map { CodexModelSummary(model: $0.key, threadCount: $0.value.count) }
            .sorted { $0.threadCount != $1.threadCount ? $0.threadCount > $1.threadCount : $0.model < $1.model }
            .prefix(3)

        return CodexInsights(
            today: today.isEmpty ? nil : CodexTodayStats(
                updatedThreadCount: today.count,
                createdThreadCount: today.filter { $0.createdAt >= dayStart }.count,
                activeThreadTokens: today.reduce(0) { $0 + $1.tokensUsed }
            ),
            recentThreads: Array(recent),
            models: Array(models)
        )
    }

    private func stateDatabaseURL() -> URL? {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return files
            .filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
            .max { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return leftDate < rightDate
            }
    }

    private func loadThreads(from databaseURL: URL) -> [ThreadRecord]? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { return nil }
        defer { sqlite3_close(database) }

        let sql = """
        SELECT id, title, cwd, model, tokens_used, created_at, updated_at
        FROM threads
        WHERE archived = 0
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        var records: [ThreadRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = string(statement, column: 0),
                  let title = string(statement, column: 1),
                  let cwd = string(statement, column: 2) else { continue }
            records.append(ThreadRecord(
                id: id,
                title: title,
                cwd: cwd,
                model: string(statement, column: 3),
                tokensUsed: Int(sqlite3_column_int64(statement, 4)),
                createdAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 5))),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 6)))
            ))
        }
        return records
    }

    private func string(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: text)
    }

    private static func projectName(from cwd: String) -> String? {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
