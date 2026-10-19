import AppKit
import SwiftUI

enum ClaudeDetailFormat {
    /// "resets 4:40 PM" for today, "resets Sat 11 PM" otherwise.
    static func absoluteResetLabel(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "h:mm a"
        } else {
            let minute = calendar.component(.minute, from: date)
            formatter.dateFormat = minute == 0 ? "EEE h a" : "EEE h:mm a"
        }
        return "resets \(formatter.string(from: date))"
    }

    /// The line under a limit bar: when a running window resets, the row's own text otherwise —
    /// including "reset" for a window that elapsed since an idle account's last reading.
    static func resetText(for item: UsageItem, now: Date = Date(), calendar: Calendar = .current) -> String? {
        if let resetsAt = item.resetsAt, resetsAt > now {
            return absoluteResetLabel(for: resetsAt, now: now, calendar: calendar)
        }
        return item.resetLabel
    }

    /// 123 → "123", 45600 → "46k", 1200000 → "1.2M"
    static func tokenCount(_ count: Int) -> String {
        switch count {
        case ..<1000:
            return "\(count)"
        case ..<999_500:
            return "\(Int((Double(count) / 1000).rounded()))k"
        default:
            let millions = Double(count) / 1_000_000
            let formatted = millions >= 10
                ? "\(Int(millions.rounded()))"
                : String(format: "%.1f", millions).replacingOccurrences(of: ".0", with: "")
            return "\(formatted)M"
        }
    }
}

struct ClaudeDetailView: View {
    @ObservedObject var appState: AppState
    let providerID: String
    var onBack: () -> Void

    private var provider: Provider? {
        appState.providers.first { $0.id == providerID }
    }

    /// Transcript stats cover every account on this Mac; say so once there is more than one.
    private var sharedSuffix: String {
        appState.claudeAccountCount >= 2 ? ", all accounts" : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 10)

            if let provider {
                barsSection(provider)

                if !provider.productShares.isEmpty {
                    sectionDivider
                    productSharesSection(provider.productShares)
                }

                if let insights = provider.insights {
                    sectionDivider
                    insightsSection(insights)

                    if !insights.skills.isEmpty || !insights.subagents.isEmpty {
                        sectionDivider
                        breakdownSection(insights)
                    }

                    if let today = insights.today {
                        sectionDivider
                        todaySection(today)
                    }
                }
            } else {
                Text("Claude is not connected")
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
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.icon)

            Image(systemName: "brain")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(provider?.name ?? "Claude")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)

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

                    // A reset time, or non-time trailing detail (e.g. extra credits "16.10/50")
                    if let detail = ClaudeDetailFormat.resetText(for: item) {
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

    private func insightsSection(_ insights: ClaudeInsights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionHeader(title: "Last 24 hours on this Mac\(sharedSuffix)")
                .help("Approximate, from local Claude Code sessions on this Mac.")

            if let avg = insights.avgContextTokens {
                let sub = Int((insights.subagentShare ?? 0).rounded())
                HStack(spacing: 8) {
                    StatCell(value: "~\(ClaudeDetailFormat.tokenCount(avg))", label: "avg context per turn")
                    StatCell(value: "\(sub)%", label: "from subagents")
                }
                .help("Average context re-sent each turn (the main token driver) and the share of tokens from subagent-heavy sessions. 0% subagents means plain single-agent sessions.")
            }

            let contextWarning = (insights.contextShareOver150k ?? 0) >= ClaudeInsights.contextWarningThreshold
            let subagentWarning = (insights.subagentShare ?? 0) >= ClaudeInsights.subagentWarningThreshold

            if contextWarning, let share = insights.contextShareOver150k {
                insightRow(
                    stat: "\(Int(share.rounded()))% of usage at >150k context",
                    hint: "/compact mid-task, /clear between tasks"
                )
                if !insights.heaviestSessions.isEmpty {
                    heaviestChats(insights.heaviestSessions)
                }
            }
            if subagentWarning, let share = insights.subagentShare {
                insightRow(
                    stat: "\(Int(share.rounded()))% from subagent-heavy sessions",
                    hint: "Be deliberate about spawning subagents"
                )
            }
            if !contextWarning && !subagentWarning {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(UsageLevel.normal.color)
                    Text("Nothing to flag in the last 24 hours")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Which specific chats drove the >150k-context usage, ranked by heavy tokens.
    private func heaviestChats(_ sessions: [HeavySession]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Heaviest chats")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(sessions.enumerated()), id: \.offset) { _, s in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(s.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        if let p = s.project, p != s.title {
                            Text(p)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Text("peaked \(ClaudeDetailFormat.tokenCount(s.peakContextTokens))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    Text("\(Int(s.share.rounded()))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(UsageLevel.warning.color)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(.leading, 17)
        .help("Chats that spent the most tokens while their context was above 150k. Together they make up the % above. /compact a long chat, or /clear to start fresh.")
    }

    private func insightRow(stat: String, hint: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(UsageLevel.warning.color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(stat)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Account-wide, from claude.ai — unlike the sections below, not limited to this machine.
    private func productSharesSection(_ shares: [UsageShare]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailSectionHeader(title: "This week by product")
            ForEach(shares, id: \.name) { share in
                HStack(spacing: 8) {
                    Text(share.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 88, alignment: .leading)
                    UsageBar(percentage: share.share, tint: .accentColor, height: UsageDesign.shareBarHeight)
                    Text("\(Int(share.share.rounded()))%")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .help("Share of this week's usage by product, across all your devices (from claude.ai).")
    }

    private func breakdownSection(_ insights: ClaudeInsights) -> some View {
        HStack(alignment: .top, spacing: 16) {
            if !insights.skills.isEmpty {
                breakdownColumn(title: "Top skills", shares: insights.skills)
            }
            if !insights.subagents.isEmpty {
                breakdownColumn(title: "Top agents", shares: insights.subagents)
            }
        }
    }

    private func breakdownColumn(title: String, shares: [UsageShare]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DetailSectionHeader(title: title)
            ForEach(shares, id: \.name) { share in
                HStack(spacing: 4) {
                    Text(share.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(share.name)
                    Spacer(minLength: 4)
                    Text(share.share < 1 ? "<1%" : "\(Int(share.share.rounded()))%")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func todaySection(_ today: TodayStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionHeader(title: "Today\(sharedSuffix)")
            HStack(alignment: .top, spacing: 8) {
                if appState.config.showCostEstimate {
                    StatCell(value: ClaudeProvider.formatDollars(today.cost.rounded(toPlaces: 2)), label: "est. cost")
                }
                StatCell(value: "\(today.sessionCount)", label: today.sessionCount == 1 ? "session" : "sessions")
                StatCell(value: ClaudeDetailFormat.tokenCount(today.totalTokens), label: "tokens")
                StatCell(value: "+\(ClaudeDetailFormat.tokenCount(today.linesAdded)) −\(ClaudeDetailFormat.tokenCount(today.linesRemoved))", label: "lines")
            }
            if today.cacheReadTokens > 0 {
                Text("\(ClaudeDetailFormat.tokenCount(today.cacheReadTokens)) cache reads, \(ClaudeDetailFormat.tokenCount(today.newTokens)) new")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .help("Cache reads are re-sent context (cheap). \"New\" is input + output + cache writes: the tokens that reflect actual work.")
            }
        }
    }

    private var footerLink: some View {
        HStack {
            Spacer()
            Button {
                NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
            } label: {
                HStack(spacing: 3) {
                    Text("Open claude.ai usage")
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

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
