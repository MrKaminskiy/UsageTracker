// Sources/UsageTracker/Views/Settings/Tabs/HelpTab.swift
import SwiftUI

struct HelpTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section(title: "Auto-Detected Services", rows: [
                    HelpEntry(icon: "brain", title: "Claude",
                              description: "Detected from Claude Code CLI. Run 'claude' in terminal to sign in."),
                    HelpEntry(icon: "cursorarrow.rays", title: "Cursor",
                              description: "Detected from Cursor app. Sign in to Cursor to see your usage."),
                    HelpEntry(icon: "terminal.fill", title: "Codex",
                              description: "Detected from Codex CLI. Run 'codex login' in terminal to sign in.")
                ])

                section(title: "API Key Services", rows: [
                    HelpEntry(icon: "sparkles", title: "OpenAI",
                              description: "Add API key from platform.openai.com/api-keys"),
                    HelpEntry(icon: "waveform", title: "ElevenLabs",
                              description: "Add API key from elevenlabs.io/app/settings/api-keys"),
                    HelpEntry(icon: "paintbrush", title: "Stability AI",
                              description: "Add API key from platform.stability.ai/account/keys"),
                    HelpEntry(icon: "film", title: "Runway",
                              description: "Add API key from dev.runwayml.com"),
                    HelpEntry(icon: "arrow.trianglehead.branch", title: "OpenRouter",
                              description: "Add API key from openrouter.ai/settings/keys")
                ])

                section(title: "Tips", rows: [
                    HelpEntry(icon: "cursorarrow.click.2", title: "View Usage",
                              description: "Left-click the menu bar icon to see your usage stats."),
                    HelpEntry(icon: "contextualmenu.and.cursorarrow", title: "Quick Access",
                              description: "Right-click for Settings, Clear Cache, and Quit options."),
                    HelpEntry(icon: "line.3.horizontal", title: "Reorder",
                              description: "Drag providers in Settings to change display order."),
                    HelpEntry(icon: "eye.slash", title: "Hide Services",
                              description: "Toggle off services you don't use in Settings.")
                ])

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func section(title: String, rows: [HelpEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)

            SettingsCard {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, entry in
                    helpRow(entry)
                    if index < rows.count - 1 {
                        SettingsCardDivider()
                    }
                }
            }
        }
    }

    private func helpRow(_ entry: HelpEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                Text(entry.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .settingsRowPadding()
    }

    private struct HelpEntry: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
    }
}
