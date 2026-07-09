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
            if appState.visibleProviders.isEmpty && !appState.isLoading {
                emptyState
            } else {
                providerList
            }

            Divider()
                .padding(.vertical, 8)

            footer
        }
        .padding(12)
        .frame(width: 340)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if appState.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading...")
                    .font(.system(size: 13, weight: .medium))
            } else if appState.transientFailureCount > 0 {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)

                Text("Can't reach the service")
                    .font(.system(size: 13, weight: .medium))

                Text("Rate-limited or offline — retrying automatically")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)

                Text("No usage data")
                    .font(.system(size: 13, weight: .medium))

                Text("Sign in to Claude Code or Cursor")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var maxProvider: Provider? {
        appState.visibleProviders.max(by: { $0.maxPercentage < $1.maxPercentage })
    }

    private var displayedProvider: Provider? {
        // If pinned, return that provider; otherwise return max
        if let pinned = appState.pinnedItem {
            return appState.visibleProviders.first { $0.id == pinned.providerId }
        }
        return maxProvider
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(appState.visibleProviders) { provider in
                if let index = appState.providers.firstIndex(where: { $0.id == provider.id }) {
                    ProviderRow(
                        provider: $appState.providers[index],
                        isDisplayedInBar: provider.id == displayedProvider?.id && appState.maxPercentage > 0,
                        isPinned: { itemLabel in
                            appState.isPinned(providerId: provider.id, itemLabel: itemLabel)
                        },
                        onTogglePin: { itemLabel in
                            appState.togglePin(providerId: provider.id, itemLabel: itemLabel)
                        },
                        onOpenDetail: provider.id == "claude" ? {
                            withAnimation(.easeInOut(duration: 0.2)) { screen = .claudeDetail }
                        } : nil
                    )
                }
            }
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

            Spacer()

            if let lastUpdated = appState.lastUpdated {
                Text("Updated \(lastUpdated.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US"))))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.icon)
        }
    }
}
