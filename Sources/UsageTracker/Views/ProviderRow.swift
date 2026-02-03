import SwiftUI

struct ProviderRow: View {
    @Binding var provider: Provider

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
                // Inset content area
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(provider.items) { item in
                        UsageItemRow(item: item)
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
    }

    private var providerHeader: some View {
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

                Spacer()

                switch provider.status {
                case .loading:
                    ProgressView()
                        .scaleEffect(0.6)
                case .notConnected:
                    Text("Not connected")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                case .error(let message):
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .help(message)
                case .loaded:
                    Text("\(Int(provider.maxPercentage))%")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct UsageItemRow: View {
    let item: UsageItem

    var body: some View {
        HStack(spacing: 8) {
            Text(item.label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

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
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .trailing)

            if let resetLabel = item.resetLabel {
                Text(resetLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.leading, 24)
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
