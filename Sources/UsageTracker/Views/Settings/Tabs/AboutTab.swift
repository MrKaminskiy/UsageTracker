// Sources/UsageTracker/Views/Settings/Tabs/AboutTab.swift
import SwiftUI
import AppKit

struct AboutTab: View {
    @ObservedObject var appState: AppState

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?): return "v\(version) (\(build))"
        case let (version?, nil): return "v\(version)"
        case let (nil, build?): return "v\(build)"
        default: return "v1.0"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    Text("UsageTracker")
                        .font(.system(size: 16, weight: .semibold))
                    Text(versionLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                if appState.updateChecker.updateAvailable,
                   let version = appState.updateChecker.latestVersion,
                   let url = appState.updateChecker.downloadURL {
                    SettingsCard {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Update available")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Version \(version)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Link("Download", destination: url)
                                .controlSize(.small)
                        }
                        .settingsRowPadding()
                    }
                }

                SettingsCard {
                    aboutLink(label: "GitHub repository",
                              icon: "chevron.left.forwardslash.chevron.right",
                              urlString: "https://github.com/MrKaminskiy/UsageTracker")
                    SettingsCardDivider()
                    aboutLink(label: "Report an issue",
                              icon: "exclamationmark.bubble",
                              urlString: "https://github.com/MrKaminskiy/UsageTracker/issues")
                    SettingsCardDivider()
                    aboutLink(label: "License",
                              icon: "doc.text",
                              urlString: "https://github.com/MrKaminskiy/UsageTracker/blob/main/LICENSE")
                }

                Button("Quit UsageTracker") {
                    NSApp.terminate(nil)
                }
                .controlSize(.regular)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
    }

    private func aboutLink(label: String, icon: String, urlString: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12))
            Spacer()
            if let url = URL(string: urlString) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .settingsRowPadding()
    }
}
