// Sources/UsageTracker/Views/Settings/Pages/AboutPage.swift
import SwiftUI
import AppKit

struct AboutPage: View {
    @ObservedObject var appState: AppState

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?): return "Version \(version) (\(build))"
        case let (version?, nil): return "Version \(version)"
        case let (nil, build?): return "Build \(build)"
        default: return "Development build"
        }
    }

    var body: some View {
        SettingsForm {
            Section {
                if appState.updateChecker.updateAvailable,
                   let version = appState.updateChecker.latestVersion,
                   let url = appState.updateChecker.downloadURL {
                    LabeledContent {
                        Link("Download", destination: url)
                    } label: {
                        Text("Update Available")
                        Text("Version \(version) is ready to download.")
                    }
                }

                link("GitHub Repository", icon: "chevron.left.forwardslash.chevron.right",
                     url: "https://github.com/MrKaminskiy/UsageTracker")
                link("Report an Issue", icon: "exclamationmark.bubble",
                     url: "https://github.com/MrKaminskiy/UsageTracker/issues")
                link("License", icon: "doc.text",
                     url: "https://github.com/MrKaminskiy/UsageTracker/blob/main/LICENSE")
            } header: {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UsageTracker")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(versionLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 10)
            }

            Section {
                LabeledContent("Quit UsageTracker") {
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    private func link(_ title: String, icon: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text(title)
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
