import AppKit
import SwiftUI

struct ProviderRow: View {
    @Binding var provider: Provider
    var isDisplayedInBar: Bool = false
    var isPinned: (String) -> Bool = { _ in false }
    var onTogglePin: ((String) -> Void)? = nil
    var onOpenDetail: (() -> Void)? = nil
    @State private var isCardHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            providerHeader
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            if case .notConnected(let url) = provider.status {
                HStack {
                    Spacer()
                    Button("View Usage") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            } else if provider.isExpanded && !provider.items.isEmpty {
                // Find the first item with max percentage (used when nothing is pinned)
                let maxItemId = provider.items.max(by: { $0.percentage < $1.percentage })?.id
                let hasPinnedItem = provider.items.contains { isPinned($0.label) }

                // Inset content area
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(provider.items) { item in
                        let itemIsPinned = isPinned(item.label)
                        // Show green dot if: pinned, OR (no pin anywhere AND this is max in displayed provider)
                        let showDot = itemIsPinned || (!hasPinnedItem && isDisplayedInBar && item.id == maxItemId)
                        UsageItemRow(
                            item: item,
                            isDisplayedInBar: showDot,
                            isPinned: itemIsPinned,
                            onTap: { onTogglePin?(item.label) }
                        )
                    }

                    if let cost = provider.costEstimate {
                        Divider()
                            .padding(.vertical, 4)

                        HStack(spacing: 8) {
                            Text("Code API cost est.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(Self.formatCost(cost))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)

                            Text("this month")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .frame(width: 60, alignment: .trailing)
                        }
                        .padding(.leading, 24)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.03))
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
        .onHover { hovering in
            isCardHovered = hovering
        }
    }

    private var providerHeader: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    provider.isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: provider.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    Image(systemName: provider.icon)
                        .font(.system(size: 12))
                        .foregroundColor(provider.displayColor)

                    Text(provider.name)
                        .font(.system(size: 13, weight: .medium))

                    if provider.insights?.hasWarnings == true {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                            .help("Usage insights available — open Claude details")
                    }

                    if let boost = provider.boostStatus {
                        HStack(spacing: 2) {
                            Text("2x")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                            if let label = boost.nextTransitionLabel {
                                Text(label)
                                    .font(.system(size: 8, weight: .medium))
                            }
                        }
                        .foregroundColor(boost.isActive
                            ? Color(red: 0.204, green: 0.780, blue: 0.349)  // match app green
                            : .secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(boost.isActive
                                    ? Color(red: 0.204, green: 0.780, blue: 0.349).opacity(0.12)
                                    : Color.primary.opacity(0.04))
                        )
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onOpenDetail {
                Button(action: onOpenDetail) {
                    Image(systemName: "chevron.right.circle")
                }
                .buttonStyle(.icon)
                .help("Claude details & insights")
                .opacity(isCardHovered ? 1 : 0)
            }

            switch provider.status {
            case .loading:
                ProgressView()
                    .scaleEffect(0.6)
            case .notConnected:
                Text("Not connected")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            case .error(let message):
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            case .loaded:
                Text("\(Int(provider.maxPercentage))%")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
    }

    private static func formatCost(_ cost: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: cost)) ?? String(format: "$%.2f", cost)
    }
}

struct UsageItemRow: View {
    let item: UsageItem
    var isDisplayedInBar: Bool = false
    var isPinned: Bool = false
    var onTap: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isDisplayedInBar ? Color.green : Color.clear)
                        .frame(width: 5, height: 5)
                    if isPinned {
                        Circle()
                            .stroke(Color.green, lineWidth: 1)
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(width: 8, height: 8)
                .padding(.trailing, 4)

                Text(item.label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(width: 92, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track with inset shadow effect
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                        )

                    // Filled portion with gradient
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [item.gradientColors.start, item.gradientColors.end],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * min(item.percentage / 100, 1))
                        .overlay(
                            // Subtle top highlight
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.25), Color.white.opacity(0)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: geometry.size.width * min(item.percentage / 100, 1))
                        )
                }
            }
            .frame(height: 8)

            Text("\(Int(item.percentage))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(item.percentage >= 85 ? item.color : .secondary)
                .frame(width: 32, alignment: .trailing)

            Text(item.resetLabel ?? "")
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.leading, 24)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap?()
        }
    }
}

#if DEBUG
struct ProviderRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ProviderRow(provider: .constant(Provider(
                id: "claude",
                name: "Claude",
                icon: "brain",
                items: [
                    UsageItem(label: "Session", current: 2, limit: 100, resetLabel: "4h 37m"),
                    UsageItem(label: "All models", current: 27, limit: 100, resetLabel: "19h 37m"),
                    UsageItem(label: "Weekly", current: 8, limit: 100, resetLabel: "Wed 2PM")
                ],
                status: .loaded
            )))
        }
        .frame(width: 320)
        .padding()
    }
}
#endif
