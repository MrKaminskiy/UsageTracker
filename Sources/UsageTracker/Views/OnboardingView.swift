import AppKit
import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .padding(.bottom, 4)

                Text("Welcome to UsageTracker")
                    .font(.system(size: 20, weight: .semibold))

                Text("Monitor your AI service usage limits in one place")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()

            // Providers section
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ProviderSection(
                        title: "Works automatically",
                        providers: [
                            ProviderInfo(icon: "brain", name: "Claude", description: "Claude Code login or claude.ai cookie"),
                            ProviderInfo(icon: "cursorarrow.rays", name: "Cursor", description: "Sign in to the Cursor app"),
                            ProviderInfo(icon: "terminal.fill", name: "Codex", description: "Run codex login in Terminal")
                        ]
                    )

                    ProviderSection(
                        title: "Needs an API key",
                        footnote: "Add keys in Settings once you're set up.",
                        providers: [
                            ProviderInfo(icon: "sparkles", name: "OpenAI", description: "platform.openai.com"),
                            ProviderInfo(icon: "arrow.trianglehead.branch", name: "OpenRouter", description: "openrouter.ai"),
                            ProviderInfo(icon: "waveform", name: "ElevenLabs", description: "elevenlabs.io")
                        ]
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        DetailSectionHeader(title: "Tips")
                            .padding(.horizontal, 4)

                        SettingsCard {
                            TipRow(icon: "cursorarrow.click", text: "Click the menu bar icon to see usage")
                            SettingsCardDivider()
                            TipRow(icon: "contextualmenu.and.cursorarrow", text: "Right-click it for Settings and Quit")
                            SettingsCardDivider()
                            TipRow(icon: "arrow.up.arrow.down", text: "Drag providers in Settings to reorder")
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer
            Button("Get Started") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .frame(width: 420, height: 580)
    }
}

struct ProviderSection: View {
    let title: String
    var footnote: String? = nil
    let providers: [ProviderInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionHeader(title: title)
                .padding(.horizontal, 4)

            SettingsCard {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    HStack(spacing: 10) {
                        Image(systemName: provider.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        Text(provider.name)
                            .font(.system(size: 13))

                        Spacer(minLength: 12)

                        Text(provider.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .settingsRowPadding()

                    if index < providers.count - 1 {
                        SettingsCardDivider()
                    }
                }
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct ProviderInfo: Identifiable {
    let id = UUID()
    let icon: String
    let name: String
    let description: String
}

struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(text)
                .font(.system(size: 12))

            Spacer(minLength: 0)
        }
        .settingsRowPadding()
    }
}
