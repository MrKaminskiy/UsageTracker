// Sources/UsageTracker/Views/Settings/Pages/ProviderPage.swift
import SwiftUI

/// One provider's Settings page: on/off, live limits, and its API key or cookie.
struct ProviderPage: View {
    let info: ProviderSettingsInfo
    @ObservedObject var appState: AppState

    @State private var key: String
    @State private var saved: Bool

    /// Reads the stored key up front: assigning it after the field appears would look like an
    /// edit, clearing "Saved" and firing a validation request on every visit.
    init(info: ProviderSettingsInfo, appState: AppState) {
        self.info = info
        self.appState = appState
        let stored = info.key.flatMap { ProviderCatalog.loadKey($0.fileName) } ?? ""
        _key = State(initialValue: stored)
        _saved = State(initialValue: !stored.isEmpty)
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
            if let plan = live?.planLabel { return "Connected, \(plan) plan" }
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
                Toggle(isOn: Binding(
                    get: { enabled },
                    set: { appState.updateProviderEnabled(info.id, enabled: $0) }
                )) {
                    Text("Enabled")
                    Text("Show \(info.name) in the popover and menu bar.")
                }
            } header: {
                header
            }

            if enabled {
                Section("Limits") {
                    if let items = live?.items, !items.isEmpty {
                        ForEach(items) { item in
                            UsageItemRow(item: item, reservesMarkerSpace: false)
                        }
                    } else {
                        Text(emptyLimitsMessage)
                            .foregroundStyle(.secondary)
                    }
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

            if let url = info.dashboardURL {
                Section {
                    Link(destination: url) {
                        HStack {
                            Text("Open Usage Dashboard")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            IconTile(symbol: info.icon, tint: info.tint, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(info.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                    if info.isUntested {
                        Text("Untested")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(UsageLevel.warning.color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(UsageLevel.warning.color.opacity(0.14)))
                    }
                }
                Text(info.connection)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                if let color = status.color {
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(status.voiceOverLabel)
        }
        .padding(.bottom, 10)
    }

    private var emptyLimitsMessage: String {
        if live == nil && appState.transientFailureCount > 0 {
            return "Can't reach the service right now. Retrying automatically."
        }
        let signedOut: Bool
        if case .notConnected = live?.status { signedOut = true } else { signedOut = live == nil }
        if signedOut {
            switch info.id {
            case "claude": return "Sign in to Claude Code, or paste a claude.ai cookie below."
            case "codex": return "Run codex login in Terminal."
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
