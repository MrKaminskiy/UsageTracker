import SwiftUI

/// Shared visual tokens for the popover, its detail pages, and onboarding.
enum UsageDesign {
    /// Provider containers and grouped lists.
    static let containerRadius: CGFloat = 10
    /// Hover highlights and small inset rows.
    static let rowRadius: CGFloat = 6

    static let barHeight: CGFloat = 6
    static let detailBarHeight: CGFloat = 8
    static let shareBarHeight: CGFloat = 4

    static let containerFill = Color.primary.opacity(0.04)
    static let barTrack = Color.primary.opacity(0.08)
}

/// One severity scale for every usage readout: bars, percentages, and the menu bar ring.
enum UsageLevel {
    case normal
    case warning
    case critical

    static let warningThreshold: Double = 60
    static let criticalThreshold: Double = 85

    init(percentage: Double) {
        switch percentage {
        case ..<Self.warningThreshold: self = .normal
        case ..<Self.criticalThreshold: self = .warning
        default: self = .critical
        }
    }

    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

/// Flat capsule meter. Tinted by `UsageLevel` unless a tint is given (e.g. shares, which aren't limits).
struct UsageBar: View {
    let percentage: Double
    var tint: Color? = nil
    var height: CGFloat = UsageDesign.barHeight

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(UsageDesign.barTrack)
                Capsule()
                    .fill(tint ?? UsageLevel(percentage: percentage).color)
                    .frame(width: geometry.size.width * min(max(percentage, 0), 100) / 100)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int(percentage)) percent")
    }
}

/// Percentage readout next to a bar: neutral until the limit is nearly used up.
struct UsagePercentText: View {
    let percentage: Double
    var size: CGFloat = 11

    var body: some View {
        Text("\(Int(percentage))%")
            .font(.system(size: size, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(UsageLevel(percentage: percentage) == .critical
                ? AnyShapeStyle(UsageLevel.critical.color)
                : AnyShapeStyle(.secondary))
    }
}

/// Sentence-case section title for detail pages.
struct DetailSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// A single figure with its caption underneath, laid out in rows of equal-width cells.
struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Plan name ("Max", "Plus") shown in detail headers.
struct PlanBadge: View {
    let plan: String

    var body: some View {
        Text(plan)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(UsageDesign.barTrack))
    }
}
