import AppKit
import SwiftUI

struct ProviderRow: View {
    @Binding var provider: Provider
    var hidesExtraUsage: Bool = false
    var isDisplayedInBar: Bool = false
    var isPinned: (String) -> Bool = { _ in false }
    var onTogglePin: ((String) -> Void)? = nil
    var onOpenDetail: (() -> Void)? = nil
    /// "as of 9h ago" when the rows are an old reading kept on screen.
    var staleLabel: String? = nil
    var costLabel: String = "Est. API cost this month"
    @State private var isCardHovered = false

    private var displayedItems: [UsageItem] {
        provider.items.filter { !hidesExtraUsage || $0.kind != .extraUsage }
    }

    private var displayedMaxPercentage: Double {
        displayedItems.map(\.percentage).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            providerHeader
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            if case .notConnected(let url) = provider.status {
                Button("View Usage") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            } else if provider.isExpanded && !displayedItems.isEmpty {
                // Find the first item with max percentage (used when nothing is pinned)
                let maxItemId = displayedItems.max(by: { $0.percentage < $1.percentage })?.id
                let hasPinnedItem = displayedItems.contains { isPinned($0.stablePinKey) }

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(displayedItems) { item in
                        let itemIsPinned = isPinned(item.stablePinKey)
                        // Mark the item if: pinned, OR (no pin anywhere AND this is max in displayed provider)
                        let showMarker = itemIsPinned || (!hasPinnedItem && isDisplayedInBar && item.id == maxItemId)
                        UsageItemRow(
                            item: item,
                            isDisplayedInBar: showMarker,
                            isPinned: itemIsPinned,
                            onTap: onTogglePin.map { toggle in { toggle(item.stablePinKey) } }
                        )
                    }

                    if let cost = provider.costEstimate {
                        Divider()
                            .padding(.vertical, 4)
                            .padding(.leading, 24)
                            .padding(.trailing, 6)

                        HStack(spacing: 8) {
                            Text(costLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(Self.formatCost(cost))
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 24)
                        .padding(.trailing, 6)
                        .help("What this month's Claude Code usage would cost at API prices, estimated from local session logs.")
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: UsageDesign.containerRadius)
                .fill(UsageDesign.containerFill)
        )
        // Clips the rows fading out on collapse to the shrinking card, so the card
        // below doesn't slide over them.
        .clipShape(RoundedRectangle(cornerRadius: UsageDesign.containerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: UsageDesign.containerRadius)
                .stroke(SettingsDesign.hairlineColor, lineWidth: SettingsDesign.hairlineWidth)
        )
        .onHover { hovering in
            isCardHovered = hovering
        }
    }

    private var providerHeader: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    provider.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(provider.isExpanded ? 90 : 0))
                        .frame(width: 12)

                    Image(systemName: provider.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(provider.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let staleLabel {
                        Text(staleLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                            .help("Numbers from the last successful check. They update on the next successful refresh.")
                    }

                    if provider.insights?.hasWarnings == true {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(UsageLevel.warning.color)
                            .help("Usage insights available. Open Claude details.")
                    }

                    if let boost = provider.boostStatus {
                        HStack(spacing: 3) {
                            Text("2x")
                                .font(.system(size: 10, weight: .bold))
                            if let label = boost.nextTransitionLabel {
                                Text(label)
                                    .font(.system(size: 10))
                            }
                        }
                        .foregroundStyle(boost.isActive ? AnyShapeStyle(UsageLevel.normal.color) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(boost.isActive
                                ? UsageLevel.normal.color.opacity(0.14)
                                : UsageDesign.barTrack)
                        )
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            switch provider.status {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            case .notConnected:
                Text("Not connected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .error(let message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(UsageLevel.warning.color)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(message)
            case .loaded:
                UsagePercentText(percentage: displayedMaxPercentage, size: 12)
            }

            if let onOpenDetail {
                Button(action: onOpenDetail) {
                    Image(systemName: "chevron.right.circle")
                }
                .buttonStyle(.icon)
                .help("Usage details")
                .opacity(isCardHovered ? 1 : 0.55)
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
    /// Settings lists rows without menu bar markers, so it drops the marker column.
    var reservesMarkerSpace: Bool = true

    @State private var isHovered = false

    private var markerHelp: String {
        if isPinned { return "Pinned to the menu bar. Click to unpin." }
        if isDisplayedInBar { return "Shown in the menu bar. Click to pin." }
        return "Click to pin to the menu bar"
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                if reservesMarkerSpace {
                    // ZStack, not Group: an empty Group drops its frame and the label column shifts.
                    ZStack {
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 7, weight: .semibold))
                                .rotationEffect(.degrees(45))
                        } else if isDisplayedInBar {
                            Circle().frame(width: 5, height: 5)
                        }
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 10, height: 10)
                }

                // Wraps rather than truncates: metered limits have long names
                // ("GPT-5.3-Codex-Spark Weekly") whose tail is the distinguishing part.
                Text(item.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: reservesMarkerSpace ? 100 : 82, alignment: .leading)

            UsageBar(percentage: item.percentage)

            UsagePercentText(percentage: item.percentage)
                .frame(width: 34, alignment: .trailing)

            // Zero-width space after "/" so "12345.60/50000" wraps at the slash, not mid-number.
            Text(item.resetLabel?.replacingOccurrences(of: "/", with: "/\u{200B}") ?? "")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.leading, reservesMarkerSpace ? 6 : 0)
        .padding(.trailing, reservesMarkerSpace ? 6 : 0)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: UsageDesign.rowRadius)
                .fill(isHovered && onTap != nil ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap?()
        }
        .help(onTap == nil ? "" : markerHelp)
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
