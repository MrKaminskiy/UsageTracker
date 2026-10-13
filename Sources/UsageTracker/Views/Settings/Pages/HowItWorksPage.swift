// Sources/UsageTracker/Views/Settings/Pages/HowItWorksPage.swift
import SwiftUI

struct HowItWorksPage: View {
    /// Opens a provider's page, so each entry leads to where it is set up.
    let open: (SettingsPage) -> Void

    var body: some View {
        SettingsForm {
            Section {
                SettingsPageHeader("How It Works") {
                    IconTile(symbol: SettingsPage.howItWorks.icon, size: SettingsDesign.headerTileSize)
                } subtitle: {
                    Text("Where UsageTracker finds your usage.")
                }
            }

            Section("Detected Automatically") {
                entry(provider: "claude", text: "Sign in to Claude Code with `claude` in Terminal, or paste a claude.ai cookie.")
                entry(provider: "codex", text: "Sign in with `codex login` in Terminal.")
                entry(provider: "cursor", text: "Sign in to the Cursor app.")
            }

            Section("Needs an API Key") {
                entry(provider: "openai", text: "An admin key (`sk-admin-…`) shows monthly spend; a project key shows daily usage.")
                entry(provider: "openrouter", text: "Shows credits used, or monthly and daily spend.")
                entry(provider: "elevenlabs", text: "Shows your character quota and when it resets.")
            }

            Section("Tips") {
                tip("cursorarrow.click", "Click the menu bar ring to see usage. Right-click for Settings and Quit.")
                tip("pin", "Click a limit in the popover to pin it to the menu bar.")
                tip("line.3.horizontal", "Drag providers in the sidebar to reorder the popover.")
                tip("eye.slash", "Turn off providers you don't use on their page.")
            }
        }
    }

    @ViewBuilder
    private func entry(provider id: String, text: LocalizedStringKey) -> some View {
        if let info = ProviderCatalog.all[id] {
            Button {
                open(.provider(id))
            } label: {
                HStack(spacing: 10) {
                    IconTile(symbol: info.icon, tint: info.tint, size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name)
                        Text(text)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(info.name) settings")
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 26)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
