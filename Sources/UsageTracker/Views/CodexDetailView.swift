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
        Divider().padding(.vertical, 10)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) { Image(systemName: "chevron.left") }
                .buttonStyle(.icon)

            Image(systemName: "terminal.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("Codex")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if let plan = provider?.planLabel {
                PlanBadge(plan: plan)
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

                        UsageBar(percentage: item.percentage, height: UsageDesign.detailBarHeight)

                        UsagePercentText(percentage: item.percentage)
                            .frame(width: 36, alignment: .trailing)
                    }

                    if let reset = item.resetsAt {
                        Text(ClaudeDetailFormat.absoluteResetLabel(for: reset))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .padding(.leading, 96)
                    } else if let detail = item.resetLabel {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .padding(.leading, 96)
                    }
                }
            }
        }
    }

    private func localActivitySection(_ insights: CodexInsights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionHeader(title: "Today on this Mac")
                .help("From Codex CLI sessions on this Mac.")

            if let today = insights.today {
                HStack(alignment: .top, spacing: 8) {
                    StatCell(value: "\(today.updatedThreadCount)", label: today.updatedThreadCount == 1 ? "chat updated" : "chats updated")
                    StatCell(value: "\(today.createdThreadCount)", label: "started")
                    StatCell(value: ClaudeDetailFormat.tokenCount(today.activeThreadTokens), label: "local tokens")
                        .help("Codex's locally stored cumulative token counter for threads updated today. This is not an account-wide billing total.")
                }
            } else {
                Text("No local Codex chats updated today")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if !insights.models.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(insights.models) { model in
                        detailRow(model.model, value: "\(model.threadCount) chat\(model.threadCount == 1 ? "" : "s")")
                            .help("\(model.threadCount) chat\(model.threadCount == 1 ? "" : "s") updated today")
                    }
                }
            }

            let balance = insights.creditBalance.flatMap { $0.isEmpty ? nil : $0 }
            let resets = insights.resetCreditsAvailable.flatMap { $0 > 0 ? $0 : nil }
            if balance != nil || resets != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let balance {
                        detailRow("Credit balance", value: balance)
                    }
                    if let resets {
                        detailRow("Limit resets available", value: "\(resets)")
                            .help("Banked full resets of the 5-hour and weekly limits. Run /usage in Codex to use one.")
                    }
                }
            }
        }
    }

    /// Label on the left, figure on the right.
    private func detailRow(_ label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 11))
    }

    private func recentThreadsSection(_ threads: [CodexThreadSummary]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailSectionHeader(title: "Recent chats")
            ForEach(threads) { thread in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(thread.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        let subtitle = [thread.project, thread.model].compactMap { $0 }.joined(separator: " · ")
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(ClaudeDetailFormat.tokenCount(thread.tokensUsed))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
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
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
}
