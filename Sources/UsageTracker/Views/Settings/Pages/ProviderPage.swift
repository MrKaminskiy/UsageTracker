// Sources/UsageTracker/Views/Settings/Pages/ProviderPage.swift
import SwiftUI

/// One provider's Settings page: on/off, live limits, and its API key or cookie.
struct ProviderPage: View {
    let info: ProviderSettingsInfo
    @ObservedObject var appState: AppState

    @State private var key: String
    @State private var saved: Bool
    @State private var accountName: String
    @FocusState private var nameFocused: Bool

    /// Reads the stored key up front: assigning it after the field appears would look like an
    /// edit, clearing "Saved" and firing a validation request on every visit.
    init(info: ProviderSettingsInfo, appState: AppState) {
        self.info = info
        self.appState = appState
        let stored = info.key.flatMap { ProviderCatalog.loadKey($0.fileName) } ?? ""
        _key = State(initialValue: stored)
        _saved = State(initialValue: !stored.isEmpty)
        _accountName = State(initialValue: appState.config.claudeAccountNames?[info.id] ?? "")
    }

    private var live: Provider? {
        appState.providers.first { $0.id == info.id }
    }

    private var enabled: Bool {
        appState.config.isProviderEnabled(info.id)
    }

    private var status: ConnectionStatus {
        guard let live else { return enabled ? .idle : .disabled }
        return ConnectionStatus.from(providerStatus: live.status, enabled: enabled)
    }

    private var statusText: String {
        switch status {
        case .connected:
            if let plan = live?.planLabel { return "Connected · \(plan) plan" }
            return "Connected"
        case .idle:
            return live?.status == .loading ? "Checking…" : "Not connected"
        case .failed:
            if case .error(let message) = live?.status { return message }
            return "Connection failed"
        case .disabled:
            return "Off"
        }
    }

    var body: some View {
        SettingsForm {
            Section {
                SettingsPageHeader(info.name, badge: info.isUntested ? "Untested" : nil) {
                    IconTile(symbol: info.icon, tint: info.tint, size: SettingsDesign.headerTileSize)
                } subtitle: {
                    statusLine
                } trailing: {
                    Toggle("Show \(info.name)", isOn: Binding(
                        get: { enabled },
                        set: { appState.updateProviderEnabled(info.id, enabled: $0) }
                    ))
                    .labelsHidden()
                    .help("Show \(info.name) in the popover and menu bar")
                }
            }

            if isClaudeProviderID(info.id) && appState.claudeAccountCount >= 2 {
                Section {
                    TextField("Name", text: $accountName, prompt: Text(live?.accountLabel ?? ""))
                        .focused($nameFocused)
                        .onSubmit { appState.renameClaudeAccount(info.id, to: accountName) }
                        .onChange(of: nameFocused) { _, focused in
                            if !focused { appState.renameClaudeAccount(info.id, to: accountName) }
                        }
                } footer: {
                    Text("Shown on this account's card. Leave empty to use the account's email.")
                        .foregroundStyle(.secondary)
                }
            }

            if enabled {
                Section {
                    if let items = live?.items, !items.isEmpty {
                        ForEach(items) { item in
                            SettingsLimitRow(item: item)
                        }
                    } else {
                        Text(LocalizedStringKey(emptyLimitsMessage))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("Limits")
                        Spacer()
                        if let url = info.dashboardURL {
                            Link(destination: url) {
                                HStack(spacing: 3) {
                                    Text("Usage Dashboard")
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 9, weight: .semibold))
                                        .accessibilityHidden(true)
                                }
                            }
                            .font(.system(size: 12, weight: .regular))
                        }
                    }
                }
            } else if let url = info.dashboardURL {
                // No Limits header to carry the link while the provider is off.
                Section {
                    Link(destination: url) {
                        HStack {
                            Text("Open Usage Dashboard")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let spec = info.key {
                Section {
                    APIKeyInput(
                        placeholder: spec.placeholder,
                        hint: spec.hint,
                        linkTitle: spec.linkTitle,
                        linkURL: spec.linkURL,
                        key: $key,
                        saved: $saved,
                        onSave: { save(spec) },
                        validateKey: spec.validate
                    )
                    .padding(.vertical, 2)
                } header: {
                    Text(spec.title)
                } footer: {
                    if info.id == "claude" {
                        Text("Only needed if you use claude.ai without Claude Code.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Live status while the provider is on; how it connects while it is off.
    @ViewBuilder
    private var statusLine: some View {
        if status == .disabled {
            Text(info.connection)
        } else {
            HStack(spacing: 5) {
                if let color = status.color {
                    Circle().fill(color).frame(width: 6, height: 6)
                }
                Text(statusText)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Status: \(statusText)")
        }
    }

    private var emptyLimitsMessage: String {
        if live == nil && appState.transientFailureCount > 0 {
            return "Can't reach the service right now. Retrying automatically."
        }
        let signedOut: Bool
        if case .notConnected = live?.status { signedOut = true } else { signedOut = live == nil }
        if signedOut {
            if isClaudeProviderID(info.id) && info.id != "claude" {
                return "Sign in to Claude Code with this account's config folder."
            }
            switch info.id {
            case "claude": return "Sign in to Claude Code, or paste a claude.ai cookie below."
            case "codex": return "Run `codex login` in Terminal."
            case "cursor": return "Sign in to the Cursor app."
            default: break
            }
        }
        if info.key != nil && key.isEmpty { return "Add an API key below to start tracking." }
        return "No data yet. Usage appears after the next refresh."
    }

    private func save(_ spec: ProviderKeySpec) {
        let canonical = spec.canonicalize(key)
        guard ProviderCatalog.saveKey(spec.fileName, canonical) else { return }
        if canonical != key {
            // Rewriting the field fires its onChange, which clears "Saved"; mark it after that.
            key = canonical
            DispatchQueue.main.async { saved = true }
        } else {
            saved = true
        }
        Task { await appState.refresh() }
    }
}

/// A limit as a form row: name and reset on the left, meter and percentage on the right.
struct SettingsLimitRow: View {
    let item: UsageItem

    var body: some View {
        // Redraws each minute so the countdown keeps moving between refreshes.
        TimelineView(.everyMinute) { context in
            let detail = Self.detail(for: item, now: context.date)
            LabeledContent {
                HStack(spacing: 10) {
                    UsageBar(percentage: item.percentage)
                        .frame(width: 140)
                    UsagePercentText(percentage: item.percentage, size: 12)
                        .frame(width: 38, alignment: .trailing)
                }
            } label: {
                Text(item.label)
                if let detail {
                    // Zero-width space after "/" so "12345.60/50000" wraps at the slash, not mid-number.
                    Text(detail.replacingOccurrences(of: "/", with: "/\u{200B}"))
                        .monospacedDigit()
                }
            }
            // One element, read once: the bar and the percentage would each say the number.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.label)
            .accessibilityValue([("\(Int(item.percentage)) percent"), detail].compactMap { $0 }.joined(separator: ", "))
        }
    }

    // nonisolated: View conformance makes members @MainActor, and this is pure text logic.
    private nonisolated static let durationPattern = #"^(\d+d|\d+h \d+m|\d+m)$"#

    /// "Resets in 4h 51m" for windows that reset; the provider's own text ("$12.40 / $50")
    /// for spend and balance rows; nil once a window's reset time has passed.
    nonisolated static func detail(for item: UsageItem, now: Date = Date()) -> String? {
        if let date = item.resetsAt {
            return relativeResetLabel(date, now: now).map { "Resets in \($0)" }
        }
        guard let label = item.resetLabel, !label.isEmpty else { return nil }
        if label.range(of: durationPattern, options: .regularExpression) != nil {
            return "Resets in \(label)"
        }
        return label
    }
}
