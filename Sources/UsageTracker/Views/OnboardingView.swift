import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Text("Welcome to UsageTracker")
                    .font(.system(size: 24, weight: .bold))

                Text("Monitor your AI service usage limits in one place")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()
                .padding(.horizontal, 24)

            // Providers section
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Auto-detected providers
                    ProviderSection(
                        title: "Works Automatically",
                        subtitle: "These services are detected from your local config",
                        providers: [
                            ProviderInfo(icon: "brain", name: "Claude", description: "Claude Code login, or a claude.ai cookie"),
                            ProviderInfo(icon: "cursorarrow.rays", name: "Cursor", description: "Sign in to Cursor app"),
                            ProviderInfo(icon: "terminal.fill", name: "Codex", description: "Run 'codex login' in terminal")
                        ]
                    )

                    // API key providers
                    ProviderSection(
                        title: "Requires API Key",
                        subtitle: "Add your API keys in Settings",
                        providers: [
                            ProviderInfo(icon: "sparkles", name: "OpenAI", description: "platform.openai.com/api-keys"),
                            ProviderInfo(icon: "waveform", name: "ElevenLabs", description: "elevenlabs.io/app/settings/api-keys"),
                            ProviderInfo(icon: "paintbrush", name: "Stability AI", description: "platform.stability.ai/account/keys"),
                            ProviderInfo(icon: "film", name: "Runway", description: "dev.runwayml.com")
                        ]
                    )

                    // Tips
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Quick Tips", systemImage: "lightbulb.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.orange)

                        TipRow(icon: "cursorarrow.click.2", text: "Left-click menu bar icon to see usage")
                        TipRow(icon: "contextualmenu.and.cursorarrow", text: "Right-click for Settings and Quit")
                        TipRow(icon: "arrow.up.arrow.down", text: "Drag providers in Settings to reorder")
                    }
                    .padding(16)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(24)
            }

            Divider()
                .padding(.horizontal, 24)

            // Footer
            HStack {
                Spacer()
                Button("Get Started") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Spacer()
            }
            .padding(24)
        }
        .frame(width: 420, height: 580)
    }
}

struct ProviderSection: View {
    let title: String
    let subtitle: String
    let providers: [ProviderInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(providers) { provider in
                    HStack(spacing: 12) {
                        Image(systemName: provider.icon)
                            .font(.system(size: 14))
                            .frame(width: 24)
                            .foregroundColor(.secondary)

                        Text(provider.name)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 80, alignment: .leading)

                        Text(provider.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)

                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                }
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
                .font(.system(size: 12))
                .foregroundColor(.orange)
                .frame(width: 20)

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}
