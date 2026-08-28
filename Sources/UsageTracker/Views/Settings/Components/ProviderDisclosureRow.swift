// Sources/UsageTracker/Views/Settings/Components/ProviderDisclosureRow.swift
import SwiftUI

/// One row in the Providers tab. Displays the toggle, status dot, and an
/// optional API key field that expands when the chevron is clicked.
struct ProviderDisclosureRow: View {
    let provider: ProviderSettingsItem
    @ObservedObject var appState: AppState
    @State private var isExpanded: Bool = false

    private var enabled: Bool {
        appState.config.isProviderEnabled(provider.id)
    }

    private var liveProvider: Provider? {
        appState.providers.first(where: { $0.id == provider.id })
    }

    private var connectionStatus: ConnectionStatus {
        guard let live = liveProvider else {
            return enabled ? .idle : .disabled
        }
        return ConnectionStatus.from(providerStatus: live.status, enabled: enabled)
    }

    private var subtitle: String {
        if !enabled { return provider.hint }
        if provider.keyConfig == nil {
            return provider.hint
        }
        switch connectionStatus {
        case .connected: return "Connected"
        case .idle: return "Not configured"
        case .failed:
            if case .error(let message) = liveProvider?.status,
               message.localizedCaseInsensitiveContains("invalid") {
                return "Invalid key"
            }
            return "Connection failed"
        case .disabled: return provider.hint
        }
    }

    private var isUntested: Bool {
        provider.id == "runway" || provider.id == "stability"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            if isExpanded {
                SettingsCardDivider()
                VStack(spacing: 0) {
                    limitsSection
                    if let key = provider.keyConfig {
                        SettingsCardDivider()
                        apiKeySection(keyConfig: key)
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 14)

                Image(systemName: provider.icon)
                    .frame(width: 22)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.system(size: 13))
                        if isUntested && isExpanded {
                            Text("Untested")
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundColor(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                StatusDot(status: connectionStatus)

                Toggle("", isOn: Binding(
                    get: { enabled },
                    set: { appState.updateProviderEnabled(provider.id, enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 14)
            }
            .settingsRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var limitsSection: some View {
        let items = liveProvider?.items ?? []
        VStack(alignment: .leading, spacing: 6) {
            Text("LIMITS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)

            if items.isEmpty {
                emptyLimitsView
                    .padding(.vertical, 2)
            } else {
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        UsageItemRow(item: item)
                    }
                }
                .padding(.leading, -24) // UsageItemRow internally pads .leading 24; cancel it for full-width
            }
        }
        .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
        .padding(.vertical, SettingsDesign.rowVerticalPadding)
    }

    @ViewBuilder
    private var emptyLimitsView: some View {
        if case .notConnected(let url) = liveProvider?.status {
            HStack(spacing: 6) {
                Text(emptyLimitsMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Link("View dashboard ↗", destination: url)
                    .font(.system(size: 11))
            }
        } else {
            Text(emptyLimitsMessage)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var emptyLimitsMessage: String {
        // Claude has a key field, but the cookie is the fallback for web-only users —
        // most people connect it by signing in to Claude Code and need no key at all.
        if provider.id == "claude" {
            return "Sign in to Claude Code, or paste your claude.ai cookie below."
        }
        if provider.keyConfig != nil {
            return "Add an API key to start tracking."
        }
        return "No data yet — usage will appear after the next refresh."
    }

    private func apiKeySection(keyConfig: ProviderKeyConfig) -> some View {
        APIKeyInput(
            placeholder: keyConfig.placeholder,
            hint: keyConfig.hint,
            linkTitle: keyConfig.linkTitle,
            linkURL: keyConfig.linkURL,
            key: keyConfig.key,
            saved: keyConfig.saved,
            onSave: keyConfig.onSave,
            validateKey: keyConfig.validateKey
        )
        .padding(.horizontal, SettingsDesign.rowHorizontalPadding)
        .padding(.vertical, SettingsDesign.rowVerticalPadding + 2)
    }
}
