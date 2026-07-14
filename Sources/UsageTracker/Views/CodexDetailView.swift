import AppKit
import SwiftUI

struct CodexDetailView: View {
    @ObservedObject var appState: AppState
    var onBack: () -> Void

    private var provider: Provider? {
        appState.providers.first { $0.id == "codex" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 10)

            if let provider {
                barsSection(provider)

                if let insights = provider.codexInsights {
                    sectionDivider
                    localActivitySection(insights)

                    if !insights.recentThreads.isEmpty {
                        sectionDivider
                        recentThreadsSection(insights.recentThreads)
                    }
                }
            } else {
                Text("Codex is not connected")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }

            sectionDivider
            footerLink
        }
        .padding(12)
        .frame(width: 340)
        .onExitCommand { onBack() }
    }

    private var sectionDivider: some View {
        Divider().padding(.vertical, 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) { Image(systemName: "chevron.left") }
                .buttonStyle(.icon)

            Image(systemName: "terminal.fill")
                .font(.system(size: 12))
                .foregroundColor(provider?.displayColor ?? .secondary)

            Text("Codex")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if let plan = provider?.planLabel {
                Text(plan)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            }
        }
    }

    private func barsSection(_ provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(provider.items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(item.label)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 88, alignment: .leading)

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06))
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(LinearGradient(colors: [item.gradientColors.start, item.gradientColors.end], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geometry.size.width * min(item.percentage / 100, 1))
                            }
                        }
                        .frame(height: 10)

                        Text("\(Int(item.percentage))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(item.percentage >= 85 ? item.color : .secondary)
                            .frame(width: 36, alignment: .trailing)
                    }

                    if let reset = item.resetsAt {
                        Text(ClaudeDetailFormat.absoluteResetLabel(for: reset))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .padding(.leading, 96)
                    } else if let detail = item.resetLabel {
                        Text(detail)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .padding(.leading, 96)
                    }
                }
            }
        }
    }

    private func localActivitySection(_ insights: CodexInsights) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionHeader("Local activity · today")
            Text("from Codex CLI sessions on this Mac")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            if let today = insights.today {
                Text("\(today.updatedThreadCount) updated chat\(today.updatedThreadCount == 1 ? "" : "s") · \(today.createdThreadCount) started")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Text("\(ClaudeDetailFormat.tokenCount(today.activeThreadTokens)) local tokens in updated chats")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .help("Codex's locally stored cumulative token counter for threads updated today. This is not an account-wide billing total.")
            } else {
                Text("No local Codex chats updated today")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if let balance = insights.creditBalance, !balance.isEmpty {
                Text("Credit balance: \(balance)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if !insights.models.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(insights.models) { model in
                        Text("\(model.model) \(model.threadCount)x")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .help("\(model.threadCount) chat\(model.threadCount == 1 ? "" : "s") updated today")
                    }
                }
            }
        }
    }

    private func recentThreadsSection(_ threads: [CodexThreadSummary]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Recent chats")
            ForEach(threads) { thread in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(thread.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        let subtitle = [thread.project, thread.model].compactMap { $0 }.joined(separator: " · ")
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(ClaudeDetailFormat.tokenCount(thread.tokensUsed))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .help("Last active \(thread.updatedAt.formatted(.relative(presentation: .named)))")
            }
        }
    }

    private var footerLink: some View {
        HStack {
            Spacer()
            Button {
                NSWorkspace.shared.open(URL(string: "https://chatgpt.com/")!)
            } label: {
                HStack(spacing: 3) {
                    Text("Open ChatGPT")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .kerning(0.5)
    }
}
