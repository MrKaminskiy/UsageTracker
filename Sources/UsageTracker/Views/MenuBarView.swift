import SwiftUI

struct IconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(width: 24, height: 24)
            .background(
                Circle()
                    .fill(
                        configuration.isPressed ? Color.primary.opacity(0.12) :
                        isHovered ? Color.primary.opacity(0.08) : Color.clear
                    )
            )
            .contentShape(Circle())
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
}

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    private enum Screen: Equatable {
        case list
        case claudeDetail
        case codexDetail
    }

    @State private var screen: Screen = .list

    var body: some View {
        Group {
            switch screen {
            case .list:
                listScreen
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .claudeDetail:
                ClaudeDetailView(appState: appState) {
                    withAnimation(.easeInOut(duration: 0.2)) { screen = .list }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .codexDetail:
                CodexDetailView(appState: appState) {
                    withAnimation(.easeInOut(duration: 0.2)) { screen = .list }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: screen)
        .onAppear { screen = .list }
        .task {
            await appState.refresh()
        }
    }

    private var listScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.popoverProviders.isEmpty && !appState.isLoading {
                emptyState
            } else {
                providerList
            }

            Divider()
                .padding(.top, 10)
                .padding(.bottom, 6)

            footer
        }
        .padding(12)
        .frame(width: 340)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            if appState.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 2)
                Text("Loading usage…")
                    .font(.system(size: 13, weight: .medium))
            } else if appState.transientFailureCount > 0 {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                Text("Can't reach the service")
                    .font(.system(size: 13, weight: .medium))

                Text("Rate-limited or offline. Retrying automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "gauge.with.dots.needle.0percent")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                Text("No usage data yet")
                    .font(.system(size: 13, weight: .medium))

                Text("Sign in to Claude Code, Codex, or Cursor, or add an API key in Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
    }

    private var maxProvider: Provider? {
        appState.popoverProviders.max(by: { $0.maxPercentage < $1.maxPercentage })
    }

    private var displayedProvider: Provider? {
        // If pinned, return that provider; otherwise return max
        if let pinned = appState.pinnedItem {
            return appState.popoverProviders.first { $0.id == pinned.providerId }
        }
        return maxProvider
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(appState.popoverProviders) { provider in
                if let index = appState.providers.firstIndex(where: { $0.id == provider.id }) {
                    ProviderRow(
                        provider: $appState.providers[index],
                        hidesExtraUsage: !appState.config.shouldShowExtraUsageInPopover,
                        isDisplayedInBar: provider.id == displayedProvider?.id && appState.maxPercentage > 0,
                        isPinned: { itemLabel in
                            appState.isPinned(providerId: provider.id, itemLabel: itemLabel)
                        },
                        onTogglePin: { itemLabel in
                            appState.togglePin(providerId: provider.id, itemLabel: itemLabel)
                        },
                        onOpenDetail: detailAction(for: provider.id)
                    )
                }
            }
        }
    }

    private func detailAction(for providerID: String) -> (() -> Void)? {
        switch providerID {
        case "claude":
            return { withAnimation(.easeInOut(duration: 0.2)) { screen = .claudeDetail } }
        case "codex":
            return { withAnimation(.easeInOut(duration: 0.2)) { screen = .codexDetail } }
        default:
            return nil
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task {
                    await appState.refresh()
                }
            } label: {
                // Angle is derived from the clock each frame instead of a persistent
                // repeatForever animation: an in-flight repeating animation captures
                // footer layout shifts (providers/"Updated" text changing mid-refresh)
                // and leaves the icon permanently offset.
                TimelineView(.animation(minimumInterval: nil, paused: !appState.isLoading)) { context in
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(
                            appState.isLoading
                                ? context.date.timeIntervalSinceReferenceDate
                                    .truncatingRemainder(dividingBy: 1) * 360
                                : 0
                        ))
                }
            }
            .buttonStyle(.icon)
            .disabled(appState.isLoading)
            .help("Refresh now")

            Spacer()

            if let lastUpdated = appState.lastUpdated {
                Text("Updated \(lastUpdated.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US"))))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.icon)
            .help("Settings")
        }
    }
}
