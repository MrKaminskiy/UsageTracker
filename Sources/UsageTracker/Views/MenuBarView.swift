import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.providers.isEmpty && !appState.isLoading {
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
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 24))
                .foregroundColor(.secondary)

            Text("No plugins found")
                .font(.system(size: 13, weight: .medium))

            Text("Add plugins to ~/.usagetracker/plugins/")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button("Open Plugins Folder") {
                openPluginsFolder()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($appState.providers) { $provider in
                ProviderRow(provider: $provider)

                if provider.id != appState.providers.last?.id {
                    Divider()
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
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(appState.isLoading)

            Spacer()

            if let lastUpdated = appState.lastUpdated {
                Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            SettingsLink {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "xmark")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11))
    }

    private func openPluginsFolder() {
        let pluginsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".usagetracker/plugins")

        try? FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(pluginsDir)
    }
}
