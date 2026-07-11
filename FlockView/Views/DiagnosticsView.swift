import SwiftUI

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: ScannerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summaryGrid
                    actionBar
                    recentEvents
                }
                .padding(.bottom, 12)
            }
        }
        .padding(20)
        .background(FlockTheme.background)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Scanner Diagnostics")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(FlockTheme.textPrimary)
                Text(viewModel.connectionState.visibleStatus)
                    .font(.subheadline)
                    .foregroundStyle(FlockTheme.textSecondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Close diagnostics")
        }
    }

    private var summaryGrid: some View {
        let diagnostics = viewModel.diagnostics
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            DiagnosticTile(title: "Connection", value: viewModel.connectionState.visibleStatus)
            DiagnosticTile(title: "Source", value: viewModel.sessionSourceLabel)
            DiagnosticTile(title: "Baud", value: "\(diagnostics.baudRate)")
            DiagnosticTile(title: "Device", value: diagnostics.selectedDevice?.displayName ?? "None")
            DiagnosticTile(title: "Path", value: diagnostics.selectedDevice?.path ?? "None")
            DiagnosticTile(title: "Firmware", value: diagnostics.firmwareVersion ?? viewModel.status.firmwareVersion ?? "Unknown")
            DiagnosticTile(title: "Board", value: diagnostics.board ?? "Unknown")
            DiagnosticTile(title: "Schema", value: diagnostics.schemaVersion.map(String.init) ?? "Unknown")
            DiagnosticTile(title: "Last Event", value: diagnostics.lastValidEventDate?.flockTimeString ?? "None")
            DiagnosticTile(title: "Valid Lines", value: "\(diagnostics.validJSONLineCount)")
            DiagnosticTile(title: "Malformed", value: "\(diagnostics.malformedLineCount)")
            DiagnosticTile(title: "Unknown Events", value: "\(diagnostics.unknownEventCount)")
            DiagnosticTile(title: "Commands", value: "\(diagnostics.commandCount)")
            DiagnosticTile(title: "Timeouts", value: "\(diagnostics.commandTimeoutCount)")
            DiagnosticTile(title: "Bytes", value: "\(diagnostics.bytesReceived)")
            DiagnosticTile(title: "Reconnects", value: "\(diagnostics.reconnectAttempts)")
            DiagnosticTile(title: "Queue Depth", value: "\(diagnostics.queueDepth)")
            DiagnosticTile(title: "Dropped", value: "\(diagnostics.droppedFirmwareObservations)")
            DiagnosticTile(title: "Free Heap", value: diagnostics.freeHeap.map(String.init) ?? "Unknown")
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.copyDiagnostics()
            } label: {
                Label("Copy Diagnostics", systemImage: "doc.on.doc")
            }

            Button {
                viewModel.clearDiagnostics()
            } label: {
                Label("Clear", systemImage: "trash")
            }

            Button {
                viewModel.sendPing()
            } label: {
                Label("Send PING", systemImage: "paperplane")
            }

            Button {
                viewModel.requestStatus()
            } label: {
                Label("Request STATUS", systemImage: "list.bullet.rectangle")
            }

            Spacer()

            Button {
                Task {
                    await viewModel.disconnectCurrentScanner()
                }
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }

            Button {
                Task {
                    await viewModel.reconnectCurrentScanner()
                }
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.plain)
        .font(.callout.weight(.medium))
        .controlSurface()
    }

    private var recentEvents: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Events")
                .font(.headline)
                .foregroundStyle(FlockTheme.textPrimary)

            if viewModel.diagnostics.recentEvents.isEmpty {
                Text("No events yet")
                    .foregroundStyle(FlockTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .flockPanel(cornerRadius: 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.diagnostics.recentEvents.reversed()) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(event.kind)
                                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(FlockTheme.signalGreen)
                                Spacer()
                                Text(event.date.flockTimeString)
                                    .font(.caption)
                                    .foregroundStyle(FlockTheme.textMuted)
                            }

                            Text(event.summary)
                                .font(.caption)
                                .foregroundStyle(FlockTheme.textSecondary)
                                .lineLimit(2)
                        }
                        .padding(10)
                        .flockPanel(cornerRadius: 7)
                    }
                }
            }
        }
    }
}

private struct DiagnosticTile: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(FlockTheme.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(FlockTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(.horizontal, 10)
        .flockPanel(cornerRadius: 7)
    }
}

#Preview("Diagnostics") {
    let settings = AppSettings()
    DiagnosticsView()
        .environmentObject(ScannerViewModel(transport: MockScannerTransport(settings: settings), settings: settings))
        .environmentObject(settings)
        .frame(width: 760, height: 640)
}
