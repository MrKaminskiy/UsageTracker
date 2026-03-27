import SwiftUI

/// Help page view
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Auto-Detected Services") {
                HelpRow(
                    icon: "brain",
                    iconColor: .purple,
                    title: "Claude",
                    description: "Detected from Claude Code CLI. Run 'claude' in terminal to sign in."
                )
                HelpRow(
                    icon: "cursorarrow.rays",
                    iconColor: .blue,
                    title: "Cursor",
                    description: "Detected from Cursor app. Sign in to Cursor to see your usage."
                )
                HelpRow(
                    icon: "terminal.fill",
                    iconColor: .green,
                    title: "Codex",
                    description: "Detected from Codex CLI. Run 'codex login' in terminal to sign in."
                )
            }

            Section("API Key Services") {
                HelpRow(
                    icon: "sparkles",
                    iconColor: .teal,
                    title: "OpenAI",
                    description: "Add API key from platform.openai.com/api-keys"
                )
                HelpRow(
                    icon: "waveform",
                    iconColor: .pink,
                    title: "ElevenLabs",
                    description: "Add API key from elevenlabs.io/app/settings/api-keys"
                )
                HelpRow(
                    icon: "paintbrush",
                    iconColor: .orange,
                    title: "Stability AI",
                    description: "Add API key from platform.stability.ai/account/keys"
                )
                HelpRow(
                    icon: "film",
                    iconColor: .red,
                    title: "Runway",
                    description: "Add API key from dev.runwayml.com"
                )
                HelpRow(
                    icon: "arrow.trianglehead.branch",
                    iconColor: .cyan,
                    title: "OpenRouter",
                    description: "Add API key from openrouter.ai/settings/keys"
                )
            }

            Section("Tips") {
                HelpRow(
                    icon: "cursorarrow.click.2",
                    iconColor: .blue,
                    title: "View Usage",
                    description: "Left-click the menu bar icon to see your usage stats."
                )
                HelpRow(
                    icon: "contextualmenu.and.cursorarrow",
                    iconColor: .gray,
                    title: "Quick Access",
                    description: "Right-click for Settings, Clear Cache, and Quit options."
                )
                HelpRow(
                    icon: "line.3.horizontal",
                    iconColor: .purple,
                    title: "Reorder",
                    description: "Drag providers in Settings to change display order."
                )
                HelpRow(
                    icon: "eye.slash",
                    iconColor: .secondary,
                    title: "Hide Services",
                    description: "Toggle off services you don't use in Settings."
                )
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.never)
        .navigationTitle("How It Works")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

/// Help row for the How It Works section
struct HelpRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}
