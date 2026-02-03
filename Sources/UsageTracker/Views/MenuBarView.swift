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

    var body: some View {
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
        .task {
            await appState.refresh()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if appState.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading...")
                    .font(.system(size: 13, weight: .medium))
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

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(appState.visibleProviders) { provider in
                if let index = appState.providers.firstIndex(where: { $0.id == provider.id }) {
                    ProviderRow(
                        provider: $appState.providers[index],
                        isDisplayedInBar: provider.id == maxProvider?.id && provider.maxPercentage > 0
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
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(appState.isLoading ? 360 : 0))
                    .animation(
                        appState.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                        value: appState.isLoading
                    )
            }
            .buttonStyle(.icon)
            .disabled(appState.isLoading)

            Spacer()

            if let lastUpdated = appState.lastUpdated {
                Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
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
