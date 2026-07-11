import SwiftUI

struct BottomStatusBar: View {
    @EnvironmentObject private var viewModel: ScannerViewModel

    var body: some View {
        HStack(spacing: 0) {
            BottomStatusItem(
                symbolName: "timer",
                title: "Session Duration",
                value: viewModel.formattedSessionDuration
            )

            DividerLine()

            BottomStatusItem(
                symbolName: "person.2",
                title: "Active Cameras",
                value: "\(viewModel.activeCameraCount)"
            )

            DividerLine()

            BottomStatusItem(
                symbolName: "wifi",
                title: "Wi-Fi Channel",
                value: viewModel.status.wifiChannelDisplay
            )

            DividerLine()

            BottomStatusItem(
                symbolName: "wave.3.right",
                title: "BLE Scan",
                value: viewModel.status.bleScanState.rawValue
            )

            DividerLine()

            BottomStatusItem(
                symbolName: "waveform.path.ecg",
                title: "Dropped Packets",
                value: "\(viewModel.status.droppedObservations)"
            )

            DividerLine()

            BottomStatusItem(
                symbolName: "cpu",
                title: "Firmware",
                value: viewModel.status.firmwareVersion ?? viewModel.connectionState.capabilities?.firmwareVersion ?? "Unknown"
            )

            Spacer(minLength: 12)

            Menu {
                Button("Export JSON") {
                    Task {
                        await viewModel.exportJSON()
                    }
                }
                Button("Export CSV") {
                    Task {
                        await viewModel.exportCSV()
                    }
                }
            } label: {
                Label("Export Data", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(width: 146)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .controlSurface()
            .help("Export session data")
        }
        .frame(height: 64)
        .padding(.horizontal, 14)
        .flockPanel(strong: true)
    }
}

private struct BottomStatusItem: View {
    var symbolName: String
    var title: String
    var value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 22))
                .foregroundStyle(FlockTheme.textSecondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(FlockTheme.textSecondary)
                    .lineLimit(1)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(FlockTheme.signalGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(minWidth: 170, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

private struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(FlockTheme.border)
            .frame(width: 1, height: 42)
            .padding(.horizontal, 14)
    }
}

#Preview("Bottom Status Bar") {
    let settings = AppSettings()
    BottomStatusBar()
        .environmentObject(ScannerViewModel(transport: MockScannerTransport(settings: settings), settings: settings))
        .environmentObject(settings)
        .padding()
        .background(FlockTheme.background)
        .frame(width: 1500)
}
