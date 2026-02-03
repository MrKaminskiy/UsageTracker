import SwiftUI

struct ProviderRow: View {
    @Binding var provider: Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            providerHeader

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
                .padding(.vertical, 4)
            } else if provider.isExpanded {
                ForEach(provider.items) { item in
                    UsageItemRow(item: item)
                }
            }
        }
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
