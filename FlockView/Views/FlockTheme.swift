import AppKit
import SwiftUI

enum LayoutMetrics {
    static let windowPadding: CGFloat = 16
    static let panelSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 8
    static let majorRadius: CGFloat = 16
    static let rowRadius: CGFloat = 12
    static let smallRadius: CGFloat = 8
}

enum FlockTheme {
    static let background = Color(red: 0.027, green: 0.035, blue: 0.047)
    static let panel = Color.black.opacity(0.72)
    static let panelStrong = Color.black.opacity(0.86)
    static let border = Color.white.opacity(0.09)
    static let borderStrong = Color.white.opacity(0.14)
    static let divider = Color.white.opacity(0.075)
    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.64)
    static let textMuted = Color.white.opacity(0.40)
    static let signalGreen = Color(red: 0.40, green: 0.87, blue: 0.31)
    static let signalYellow = Color(red: 1.00, green: 0.78, blue: 0.14)
    static let signalRed = Color(red: 1.00, green: 0.29, blue: 0.25)
    static let dimSignal = Color.white.opacity(0.18)
    static let windowTint = Color.black.opacity(0.42)
    static let majorPanelTint = Color.black.opacity(0.50)
    static let rowTint = Color.black.opacity(0.40)
    static let selectedTint = Color.green.opacity(0.055)

    static func color(for proximity: ProximityLevel) -> Color {
        switch proximity {
        case .close:
            signalGreen
        case .medium:
            signalYellow
        case .far:
            signalRed
        }
    }
}

struct MatteCard: View {
    var isSelected: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: LayoutMetrics.rowRadius, style: .continuous)
            .fill(FlockTheme.rowTint.opacity(isSelected ? 1.08 : 1.0))
    }
}

struct AcrylicPanel<Content: View>: View {
    var strong: Bool
    var cornerRadius: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                AcrylicSurface(
                    opacity: strong ? 0.54 : 0.46,
                    strong: strong,
                    cornerRadius: cornerRadius,
                    blur: 0
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strong ? FlockTheme.borderStrong : FlockTheme.border, lineWidth: 1)
            }
    }
}

struct FlockPanelModifier: ViewModifier {
    @EnvironmentObject private var settings: AppSettings

    var strong: Bool
    var cornerRadius: CGFloat
    var borderColor: Color

    func body(content: Content) -> some View {
        let opacity = strong ? min(0.58, settings.matteTransparency * 0.82) : settings.matteTransparency * 0.72

        content
            .background {
                AcrylicSurface(
                    opacity: opacity,
                    strong: strong,
                    cornerRadius: cornerRadius,
                    blur: settings.backgroundBlur
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
    }
}

struct AcrylicSurface: View {
    var opacity: Double
    var strong: Bool
    var cornerRadius: CGFloat
    var blur: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            AcrylicBackground(material: strong ? .hudWindow : .underWindowBackground, blendingMode: .withinWindow)
                .opacity(strong ? 0.58 : 0.48)

            shape
                .fill(Color.black.opacity(opacity))

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            FlockTheme.background.opacity(0.22),
                            Color.black.opacity(strong ? 0.34 : 0.28)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            AcrylicGrainView(opacity: strong ? 0.028 : 0.022, density: strong ? 360 : 300)
                .blendMode(.overlay)
        }
        .clipShape(shape)
    }
}

struct MicaWindowBackground: View {
    var body: some View {
        ZStack {
            AcrylicBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                .opacity(0.68)

            FlockTheme.background.opacity(0.82)
            FlockTheme.windowTint

            LinearGradient(
                colors: [
                    Color.white.opacity(0.02),
                    Color.clear,
                    Color.black.opacity(0.24)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            AcrylicGrainView(opacity: 0.018, density: 480)
                .blendMode(.overlay)
        }
    }
}

struct AcrylicBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = blendingMode
        view.material = material
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
        nsView.isEmphasized = true
    }
}

private struct AcrylicGrainView: View {
    var opacity: Double
    var density: Int = 180

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else {
                return
            }

            for index in 0..<density {
                let x = pseudoRandom(index, salt: 17) * size.width
                let y = pseudoRandom(index, salt: 43) * size.height
                let alpha = opacity * (0.45 + pseudoRandom(index, salt: 71) * 0.55)
                let rect = CGRect(x: x, y: y, width: 1, height: 1)
                context.fill(Path(rect), with: .color(.white.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
    }

    private func pseudoRandom(_ value: Int, salt: Int) -> Double {
        let n = sin(Double(value * 127 + salt * 311)) * 43758.5453123
        return n - floor(n)
    }
}

extension View {
    func flockPanel(
        strong: Bool = false,
        cornerRadius: CGFloat = LayoutMetrics.rowRadius,
        borderColor: Color = FlockTheme.border
    ) -> some View {
        modifier(FlockPanelModifier(strong: strong, cornerRadius: cornerRadius, borderColor: borderColor))
    }

    func controlSurface(cornerRadius: CGFloat = LayoutMetrics.smallRadius) -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 7)
            .flockPanel(cornerRadius: cornerRadius, borderColor: FlockTheme.borderStrong)
    }
}

extension CameraDetection {
    @MainActor
    func proximity(settings: AppSettings) -> ProximityLevel {
        proximity(
            closeThreshold: settings.closeThreshold,
            mediumThreshold: settings.mediumThreshold,
            farThreshold: settings.farThreshold
        )
    }

    var relativeSeenText: String {
        if secondsSinceSeen < 60 {
            return "\(secondsSinceSeen) sec ago"
        }

        let minutes = secondsSinceSeen / 60
        if minutes < 60 {
            return "\(minutes) min ago"
        }

        let hours = minutes / 60
        return "\(hours) hr ago"
    }
}

extension Date {
    var flockTimeString: String {
        formatted(date: .omitted, time: .standard)
    }

    var flockDateTimeString: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}
