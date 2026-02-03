import Foundation
import SQLite3

actor CursorProvider {
    private let dbPath = NSString(string: "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb").expandingTildeInPath
    private let usageURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    private let refreshURL = URL(string: "https://api2.cursor.sh/oauth/token")!
    private let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
    private let refreshBufferMs: Double = 5 * 60 * 1000 // 5 minutes

    struct UsageResponse: Codable {
        var enabled: Bool?
        var planUsage: PlanUsage?
        var spendLimitUsage: SpendLimitUsage?
        var billingCycleEnd: Double?

        struct PlanUsage: Codable {
            var totalSpend: Double?
            var limit: Double?
            var bonusSpend: Double?
        }

        struct SpendLimitUsage: Codable {
            var individualLimit: Double?
            var individualRemaining: Double?
            var pooledLimit: Double?
            var pooledRemaining: Double?
        }
    }

    private let settingsURL = URL(string: "https://cursor.sh/settings")!

    func fetchUsage() async throws -> Provider {
        guard var accessToken = readStateValue("cursorAuth/accessToken"),
              let refreshToken = readStateValue("cursorAuth/refreshToken") else {
            return Provider(
                id: "cursor",
                name: "Cursor",
                icon: "cursorarrow.rays",
                items: [],
                status: .notConnected(url: settingsURL)
            )
        }

        // Refresh if needed
        if needsRefresh(accessToken) {
            if let refreshed = try? await refreshTokenRequest(refreshToken) {
                accessToken = refreshed
                writeStateValue("cursorAuth/accessToken", refreshed)
            }
        }

        // Fetch usage
        var request = URLRequest(url: usageURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = "{}".data(using: .utf8)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return Provider(
                id: "cursor",
                name: "Cursor",
                icon: "cursorarrow.rays",
                items: [],
                status: .error("Invalid response")
            )
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            // Try refresh and retry
            if let refreshed = try? await refreshTokenRequest(refreshToken) {
                writeStateValue("cursorAuth/accessToken", refreshed)
                return try await fetchUsage()
            }
            return Provider(
                id: "cursor",
                name: "Cursor",
                icon: "cursorarrow.rays",
                items: [],
                status: .error("Token expired. Sign in via Cursor app.")
            )
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            return Provider(
                id: "cursor",
                name: "Cursor",
                icon: "cursorarrow.rays",
                items: [],
                status: .error("HTTP \(httpResponse.statusCode)")
            )
        }

        let usage = try JSONDecoder().decode(UsageResponse.self, from: data)

        guard usage.enabled == true, let planUsage = usage.planUsage else {
            return Provider(
                id: "cursor",
                name: "Cursor",
                icon: "cursorarrow.rays",
                items: [],
                status: .error("Usage tracking disabled")
            )
        }

        var items: [UsageItem] = []

        // Plan usage (in dollars)
        if let totalSpend = planUsage.totalSpend, let limit = planUsage.limit, limit > 0 {
            let percentage = (totalSpend / limit) * 100
            items.append(UsageItem(
                label: "Plan",
                current: percentage,
                limit: 100,
                resetLabel: formatResetTime(usage.billingCycleEnd)
            ))
        }

        // On-demand usage
        if let spendLimit = usage.spendLimitUsage {
            let limit = spendLimit.individualLimit ?? spendLimit.pooledLimit ?? 0
            let remaining = spendLimit.individualRemaining ?? spendLimit.pooledRemaining ?? 0
            if limit > 0 {
                let used = limit - remaining
                let percentage = (used / limit) * 100
                items.append(UsageItem(
                    label: "On-demand",
                    current: percentage,
                    limit: 100,
                    resetLabel: nil
                ))
            }
        }

        return Provider(
            id: "cursor",
            name: "Cursor",
            icon: "cursorarrow.rays",
            items: items,
            status: items.isEmpty ? .error("No usage data") : .loaded
        )
    }

    private func readStateValue(_ key: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }

        let query = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, key, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        guard let cString = sqlite3_column_text(stmt, 0) else {
            return nil
        }

        return String(cString: cString)
    }

    private func writeStateValue(_ key: String, _ value: String) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_close(db) }

        let query = "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?);"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, key, -1, nil)
        sqlite3_bind_text(stmt, 2, value, -1, nil)

        sqlite3_step(stmt)
    }

    private func needsRefresh(_ accessToken: String) -> Bool {
        // Decode JWT to get expiration
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { return true }

        var base64 = String(parts[1])
        // Pad base64 if needed
        while base64.count % 4 != 0 {
            base64 += "="
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else {
            return true
        }

        let expiresAt = exp * 1000
        let now = Date().timeIntervalSince1970 * 1000
        return now + refreshBufferMs >= expiresAt
    }

    private func refreshTokenRequest(_ refreshToken: String) async throws -> String? {
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            return nil
        }

        struct RefreshResponse: Codable {
            var access_token: String?
            var shouldLogout: Bool?
        }

        let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)

        if refreshResponse.shouldLogout == true {
            return nil
        }

        return refreshResponse.access_token
    }

    private func formatResetTime(_ timestampMs: Double?) -> String? {
        guard let timestampMs = timestampMs else { return nil }

        let resetDate = Date(timeIntervalSince1970: timestampMs / 1000)
        let diff = resetDate.timeIntervalSinceNow
        if diff <= 0 { return nil }

        let days = Int(diff / 86400)
        if days > 0 {
            return "\(days)d"
        }

        let hours = Int(diff / 3600)
        let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
