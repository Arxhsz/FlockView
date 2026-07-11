import SwiftUI

struct CameraRowView: View {
    @EnvironmentObject private var settings: AppSettings

    var camera: CameraDetection
    var isSelected: Bool
    var compact: Bool
    var onToggleMarked: (() -> Void)?
    var onViewNote: (() -> Void)?

    @State private var isHovered = false

    private var proximity: ProximityLevel {
        camera.proximity(settings: settings)
    }

    var body: some View {
        HStack(spacing: 0) {
            Image("FlockCamera")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: compact ? 82 : 104, height: compact ? 62 : 78)
                .padding(.horizontal, compact ? 8 : 11)
                .accessibilityHidden(true)

            Rectangle()
                .fill(FlockTheme.divider)
                .frame(width: 1)
                .padding(.vertical, compact ? 8 : 12)

            VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                HStack(spacing: 7) {
                    Text(camera.name)
                        .font(.system(size: compact ? 15 : 18, weight: .semibold))
                        .foregroundStyle(FlockTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    metadataBadges
                }

                HStack(spacing: compact ? 10 : 14) {
                    Text("MAC: \(camera.macAddress)")
                        .foregroundStyle(FlockTheme.textSecondary)

                    Label(camera.protocolType.rawValue, systemImage: camera.protocolType.symbolName)
                        .foregroundStyle(FlockTheme.textSecondary)

                    Label(camera.channelDescription, systemImage: "link")
                        .foregroundStyle(FlockTheme.textSecondary)
                }
                .font(.system(size: compact ? 11 : 12))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            }
            .padding(.leading, compact ? 12 : 16)

            Spacer(minLength: 10)

            VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                HStack(spacing: 8) {
                    Text(proximity.rawValue)
                        .font(.system(size: compact ? 15 : 18, weight: .medium))
                        .foregroundStyle(FlockTheme.color(for: proximity))

                    Circle()
                        .fill(FlockTheme.color(for: proximity))
                        .frame(width: 5, height: 5)

                    Text("\(camera.rssi) dBm")
                        .font(.system(size: compact ? 13 : 15, weight: .medium))
                        .foregroundStyle(FlockTheme.color(for: proximity))
                }

                Text("Detected \(camera.relativeSeenText)")
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(FlockTheme.textSecondary)
            }
            .frame(width: compact ? 140 : 168, alignment: .leading)

            SignalBarsView(proximity: proximity, compact: compact)
                .frame(width: compact ? 62 : 76)
                .padding(.trailing, compact ? 10 : 14)
        }
        .frame(height: compact ? 74 : 90)
        .background {
            ZStack {
                MatteCard(isSelected: isSelected)
                RoundedRectangle(cornerRadius: LayoutMetrics.rowRadius, style: .continuous)
                    .fill(
                        isSelected ? FlockTheme.selectedTint :
                        (isHovered ? Color.white.opacity(0.04) : Color.clear)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.rowRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LayoutMetrics.rowRadius, style: .continuous)
                .stroke(
                    isSelected ? FlockTheme.signalGreen.opacity(0.85) :
                    (isHovered ? FlockTheme.borderStrong : FlockTheme.border),
                    lineWidth: isSelected ? 1.25 : 1
                )
        }
        .shadow(color: isSelected ? FlockTheme.signalGreen.opacity(0.08) : .clear, radius: 6, x: 0, y: 0)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: settings.reduceMotion ? 0 : 0.2), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var metadataBadges: some View {
        HStack(spacing: 5) {
            Text(camera.type.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FlockTheme.signalGreen)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(FlockTheme.signalGreen.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.smallRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LayoutMetrics.smallRadius, style: .continuous)
                        .stroke(FlockTheme.signalGreen.opacity(0.14), lineWidth: 1)
                }

            if camera.marked {
                Button {
                    onToggleMarked?()
                } label: {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlockTheme.signalYellow.opacity(0.92))
                }
                .buttonStyle(.plain)
                .help("Marked camera")
                .accessibilityLabel("Marked camera")
            }

            if !camera.note.isEmpty {
                Button {
                    onViewNote?()
                } label: {
                    Image(systemName: "note.text")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlockTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("View note")
                .accessibilityLabel("View note for \(camera.name)")
            }
        }
    }

    private var accessibilitySummary: String {
        var parts = [
            camera.name,
            camera.macAddress,
            camera.protocolType.rawValue,
            proximity.rawValue,
            "\(camera.rssi) decibels"
        ]
        if camera.marked {
            parts.append("marked")
        }
        if !camera.note.isEmpty {
            parts.append("has note")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Camera Row") {
    var camera = CameraDetection.makeMockDetections()[0]
    camera.marked = true
    camera.note = "North gate sighting"
    let settings = AppSettings()
    return CameraRowView(camera: camera, isSelected: true, compact: false)
        .environmentObject(settings)
        .padding()
        .background(FlockTheme.background)
        .frame(width: 1060)
}
