import SwiftUI

struct CameraDetailView: View {
    @EnvironmentObject private var viewModel: ScannerViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var showingNoteEditor = false

    var isSheet: Bool

    var body: some View {
        Group {
            if let camera = viewModel.selectedCamera {
                VStack(spacing: 10) {
                    header(camera)

                    ScrollView {
                        VStack(spacing: 10) {
                            topCard(camera)
                            signalSummary(camera)
                            statisticsGrid(camera)
                            RSSIChartView(samples: camera.rssiHistory)

                            if !camera.note.isEmpty {
                                noteCard(camera.note)
                            }

                            actionBar(camera)
                        }
                        .padding(.horizontal, isSheet ? 18 : 12)
                        .padding(.bottom, 12)
                    }
                }
                .sheet(isPresented: $showingNoteEditor) {
                    NoteEditorView(camera: camera) { note in
                        viewModel.saveNote(cameraID: camera.id, note: note)
                    }
                    .environmentObject(settings)
                }
            } else {
                emptyDetail
            }
        }
        .padding(.top, 16)
        .flockPanel(strong: true)
    }

    private func header(_ camera: CameraDetection) -> some View {
        HStack(spacing: 12) {
            Text(camera.name)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(FlockTheme.textPrimary)
                .lineLimit(1)

            Spacer()

            Button {
                viewModel.toggleMarked(cameraID: camera.id)
            } label: {
                Image(systemName: camera.marked ? "star.fill" : "star")
                    .font(.system(size: 23))
                    .foregroundStyle(camera.marked ? FlockTheme.signalYellow : FlockTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help(camera.marked ? "Unmark Camera" : "Mark Camera")
            .accessibilityLabel(camera.marked ? "Unmark Camera" : "Mark Camera")

            Button {
                if isSheet {
                    viewModel.isDetailSheetPresented = false
                } else {
                    viewModel.isInspectorVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22))
                    .foregroundStyle(FlockTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Close inspector")
            .accessibilityLabel("Close inspector")
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private func topCard(_ camera: CameraDetection) -> some View {
        HStack(spacing: 16) {
            Image("FlockCamera")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 168, height: 132)
                .accessibilityHidden(true)

            Rectangle()
                .fill(FlockTheme.border)
                .frame(width: 1)
                .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 11) {
                Text(camera.type.rawValue)
                    .font(.headline)
                    .foregroundStyle(FlockTheme.signalGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(FlockTheme.signalGreen.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(FlockTheme.signalGreen.opacity(0.14), lineWidth: 1)
                    }

                detailValue(title: "MAC Address", value: camera.macAddress, valueStyle: .large)

                HStack(spacing: 32) {
                    detailValue(title: "Protocol", value: camera.protocolType.rawValue)
                    detailValue(title: "Channel", value: camera.channelDescription)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .flockPanel(cornerRadius: 8)
    }

    private func signalSummary(_ camera: CameraDetection) -> some View {
        let proximity = camera.proximity(settings: settings)

        return HStack {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 14) {
                    Text(proximity.rawValue)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(FlockTheme.color(for: proximity))

                    Circle()
                        .fill(FlockTheme.color(for: proximity))
                        .frame(width: 7, height: 7)

                    Text("\(camera.rssi) dBm")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(FlockTheme.color(for: proximity))
                }

                Text(proximity.signalLabel)
                    .font(.headline)
                    .foregroundStyle(FlockTheme.textSecondary)
            }

            Spacer()

            SignalBarsView(proximity: proximity)
                .frame(width: 122)
        }
        .padding(18)
        .flockPanel(cornerRadius: 8)
    }

    private func statisticsGrid(_ camera: CameraDetection) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            StatTile(title: "Peak RSSI", value: "\(camera.peakRSSI) dBm", valueColor: FlockTheme.signalGreen)
            StatTile(title: "Average RSSI", value: "\(Int(camera.averageRSSI.rounded())) dBm", valueColor: FlockTheme.signalGreen)
            StatTile(title: "Observation Count", value: "\(camera.observationCount)", valueColor: FlockTheme.textPrimary)
            StatTile(title: "First Seen", value: camera.firstSeen.flockTimeString, valueColor: FlockTheme.textPrimary)
            StatTile(title: "Last Seen", value: camera.lastSeen.flockTimeString, valueColor: FlockTheme.signalGreen)
            StatTile(title: "Time Since Seen", value: camera.relativeSeenText, valueColor: FlockTheme.signalGreen)
        }
    }

    private func noteCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Note", systemImage: "note.text")
                .font(.headline)
                .foregroundStyle(FlockTheme.textSecondary)
            Text(note)
                .font(.body)
                .foregroundStyle(FlockTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .flockPanel(cornerRadius: 8)
    }

    private func actionBar(_ camera: CameraDetection) -> some View {
        HStack(spacing: 10) {
            Button {
                viewModel.toggleMarked(cameraID: camera.id)
            } label: {
                Label(camera.marked ? "Unmark Camera" : "Mark Camera", systemImage: camera.marked ? "star.fill" : "star")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .controlSurface()

            Button {
                showingNoteEditor = true
            } label: {
                Label("Add Note", systemImage: "note.text")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .controlSurface()

            Menu {
                Button("Copy MAC Address") {
                    viewModel.copyMACAddress(for: camera)
                }
                Button("Copy Camera Details") {
                    viewModel.copyCameraDetails(for: camera)
                }
                Button("View Raw Event") {
                    viewModel.presentRawEvent(for: camera)
                }
                Divider()
                Button("Remove From Current View") {
                    viewModel.removeFromCurrentView(camera)
                }
            } label: {
                Label("More", systemImage: "ellipsis")
                    .frame(maxWidth: .infinity)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .controlSurface()
        }
        .font(.headline)
    }

    private func detailValue(title: String, value: String, valueStyle: DetailValueStyle = .normal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.callout)
                .foregroundStyle(FlockTheme.textSecondary)
            Text(value)
                .font(valueStyle == .large ? .system(size: 21, weight: .semibold) : .headline)
                .foregroundStyle(FlockTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.trailing")
                .font(.system(size: 36))
                .foregroundStyle(FlockTheme.textMuted)
            Text("No Camera Selected")
                .font(.headline)
                .foregroundStyle(FlockTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .flockPanel(strong: true)
    }
}

private enum DetailValueStyle {
    case normal
    case large
}

private struct StatTile: View {
    var title: String
    var value: String
    var valueColor: Color

    var body: some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.callout)
                .foregroundStyle(FlockTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .padding(.horizontal, 8)
        .flockPanel(cornerRadius: 7)
    }
}

#Preview("Camera Details") {
    let settings = AppSettings()
    CameraDetailView(isSheet: false)
        .environmentObject(ScannerViewModel(transport: MockScannerTransport(settings: settings), settings: settings))
        .environmentObject(settings)
        .frame(width: 492, height: 760)
        .padding()
        .background(FlockTheme.background)
}
