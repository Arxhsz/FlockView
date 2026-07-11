import SwiftUI

struct SignalBarsView: View {
    var proximity: ProximityLevel
    var compact: Bool = false

    private var activeBarCount: Int {
        switch proximity {
        case .close:
            3
        case .medium:
            2
        case .far:
            1
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: compact ? 5 : 6) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(index < activeBarCount ? FlockTheme.color(for: proximity) : FlockTheme.dimSignal)
                    .frame(width: compact ? 10 : 12, height: height(for: index))
                    .animation(.easeInOut(duration: 0.2), value: proximity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(proximity.rawValue) signal")
    }

    private func height(for index: Int) -> CGFloat {
        let heights: [CGFloat] = compact ? [18, 25, 32] : [22, 30, 38]
        return heights[index]
    }
}

#Preview("Signal Bars") {
    HStack(spacing: 28) {
        SignalBarsView(proximity: .close)
        SignalBarsView(proximity: .medium)
        SignalBarsView(proximity: .far)
    }
    .padding()
    .background(FlockTheme.background)
}
