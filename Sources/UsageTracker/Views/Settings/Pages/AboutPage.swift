// Sources/UsageTracker/Views/Settings/Pages/AboutPage.swift
import SwiftUI
import AppKit

struct AboutPage: View {
    @ObservedObject var appState: AppState

    var body: some View {
        SettingsForm {
            Section {
                AboutHeader(checker: appState.updateChecker)
            }

            Section {
                link("GitHub Repository", icon: "chevron.left.forwardslash.chevron.right",
                     url: "https://github.com/MrKaminskiy/UsageTracker")
                link("Report an Issue", icon: "exclamationmark.bubble",
                     url: "https://github.com/MrKaminskiy/UsageTracker/issues")
                link("License", icon: "doc.text",
                     url: "https://github.com/MrKaminskiy/UsageTracker/blob/main/LICENSE")
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

/// App icon, version, and the update control. Observes the checker directly: its changes
/// don't pass through `AppState`, so the page would otherwise miss them.
private struct AboutHeader: View {
    @ObservedObject var checker: UpdateChecker
    /// Background refreshes also run checks; only one the user asked for shows a spinner.
    @State private var requested = false

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

    private var newVersion: String? {
        checker.updateAvailable ? checker.latestVersion : nil
    }

    var body: some View {
        SettingsPageHeader("UsageTracker") {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
                .padding(-4)  // app icons carry their own margin; align with the 40pt tiles
                .accessibilityHidden(true)
        } subtitle: {
            if let newVersion {
                Text("\(versionLabel) · \(newVersion) available")
            } else if requested && checker.lastCheckFailed {
                Text("\(versionLabel) · Couldn't check for updates")
            } else if checker.checkedAt != nil {
                Text("\(versionLabel) · Up to date")
            } else {
                Text(versionLabel)
            }
        } trailing: {
            if newVersion != nil, let url = checker.downloadURL {
                Button("Download") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderedProminent)
            } else if requested && checker.isChecking {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 20)
            } else {
                Button("Check for Updates") {
                    requested = true
                    Task { await checker.check() }
                }
            }
        }
    }
}
