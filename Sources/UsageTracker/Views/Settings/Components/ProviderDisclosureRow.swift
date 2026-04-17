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
        case .failed: return "Connection failed"
        case .disabled: return provider.hint
        }
    }

    private var hasKeyField: Bool { provider.keyConfig != nil }

    private var isUntested: Bool {
        provider.id == "runway" || provider.id == "stability"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            if isExpanded, let key = provider.keyConfig {
                SettingsCardDivider()
                expandedBody(keyConfig: key)
            }
        }
    }

    private var headerRow: some View {
        Button {
            if hasKeyField {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
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

                if hasKeyField {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 14)
                } else {
                    Color.clear.frame(width: 14)
                }
            }
            .settingsRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func expandedBody(keyConfig: ProviderKeyConfig) -> some View {
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
