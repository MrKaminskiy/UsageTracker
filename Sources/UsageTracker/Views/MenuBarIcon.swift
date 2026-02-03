import SwiftUI

struct MenuBarIcon: View {
    let percentage: Double
    let isLoading: Bool

    private var color: Color {
        switch percentage {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                .frame(width: 16, height: 16)

            Circle()
                .trim(from: 0, to: percentage / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(-90))

            if isLoading {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            } else {
                Text("\(Int(percentage))")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    HStack(spacing: 20) {
        MenuBarIcon(percentage: 25, isLoading: false)
        MenuBarIcon(percentage: 65, isLoading: false)
        MenuBarIcon(percentage: 90, isLoading: false)
        MenuBarIcon(percentage: 50, isLoading: true)
    }
    .padding()
}
#endif
