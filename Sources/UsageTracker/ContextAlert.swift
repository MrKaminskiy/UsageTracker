import Foundation
import UserNotifications

/// Pure decision logic for the "active chat exceeded its context threshold" alert.
/// Kept free of side effects so it can be unit-tested; `ContextAlertNotifier` does the I/O.
enum ContextAlert {
    struct State: Equatable {
        /// Chats we've already alerted for and that have stayed over the threshold since.
        /// A chat is removed (re-armed) once it's observed back below the threshold.
        /// In-memory only, so it's bounded by app uptime and clears on restart.
        var alertedSessionIds: Set<String> = []
    }

    /// Decide whether to fire a notification for the current active-chat snapshot.
    ///
    /// De-duplication is **per chat**: each chat alerts once when its context crosses
    /// `threshold`, and doesn't alert again until that same chat is seen back below the
    /// threshold (e.g. after `/compact`) and then crosses again. This means:
    ///   - staying in one large chat across refreshes → one alert, not one per cycle;
    ///   - a second chat growing large → its own single alert;
    ///   - two large chats alternating as the active one → no repeated alerts (each already fired);
    ///   - returning to a still-large chat after a detour → no alert (it never shrank).
    ///
    /// Only the currently-active chat is observed per call, so a chat re-arms when it *itself*
    /// becomes active again below the threshold — not merely because focus moved elsewhere.
    static func evaluate(currentContext: Int?, sessionId: String?, threshold: Int,
                         state: State) -> (fire: Bool, state: State) {
        guard let ctx = currentContext, let sid = sessionId else { return (false, state) }
        var alerted = state.alertedSessionIds
        if ctx >= threshold {
            if alerted.contains(sid) { return (false, state) }  // already alerted; still large
            alerted.insert(sid)
            return (true, State(alertedSessionIds: alerted))
        }
        // Below threshold: re-arm this chat so a later crossing fires again.
        if alerted.contains(sid) {
            alerted.remove(sid)
            return (false, State(alertedSessionIds: alerted))
        }
        return (false, state)
    }
}

/// Posts a local macOS notification when the active chat's context grows too large.
///
/// A retained `UNUserNotificationCenterDelegate` is required so the banner shows even when
/// UsageTracker is the active app (a menu-bar app activates itself when its popover/settings
/// opens); without `willPresent` returning `.banner`, macOS silently suppresses foreground alerts.
@MainActor
final class ContextAlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    private var configured = false

    /// `UNUserNotificationCenter` requires a real app bundle; a bare `swift run` executable has
    /// no bundle identifier and touching the center there traps. Guard so debug runs no-op.
    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    /// Install the delegate (so foreground alerts aren't suppressed) and prompt for permission
    /// once, early — before any refresh could try to post. Idempotent.
    func configureIfNeeded() {
        guard isBundled, !configured else { return }
        configured = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                Log.error("Notification authorization failed: \(error)")
            } else {
                Log.info("Notification authorization: \(granted ? "granted" : "denied")")
            }
        }
    }

    /// Post the alert, resolving authorization first. Returns whether it was actually delivered
    /// (unbundled counts as "handled" so debug runs don't retry forever). The caller commits its
    /// de-duplication state only on a real delivery, so a dropped or denied alert isn't
    /// permanently suppressed — a later refresh (or a later grant in System Settings) retries.
    func notifyContextExceeded(contextTokens: Int, title: String?, threshold: Int) async -> Bool {
        guard isBundled else {
            Log.info("Context alert (unbundled — skipped): ~\(contextTokens / 1000)k ≥ \(threshold / 1000)k")
            return true
        }
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            status = granted ? .authorized : .denied
        }
        guard status == .authorized || status == .provisional else {
            Log.info("Context alert not delivered (authorization status \(status.rawValue)); will retry")
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "Chat context is large"
        let chat = title.map { "“\($0)” " } ?? ""
        content.body = "\(chat)is at ~\(contextTokens / 1000)k tokens. /compact mid-task or /clear between tasks."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch {
            Log.error("Failed to post context alert: \(error)")
            return false
        }
    }

    /// Show the banner even when UsageTracker is the foreground/active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
