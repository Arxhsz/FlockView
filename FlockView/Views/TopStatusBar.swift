import SwiftUI

struct TopStatusBar: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var viewModel: ScannerViewModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                RadarLogo(
                    isScanning: isRadarScanning,
                    reduceMotion: settings.reduceMotion
                )
                    .frame(width: 46, height: 46)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("FlockView")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(FlockTheme.textPrimary)
                    Text("v1.0.0")
                        .font(.caption)
                        .foregroundStyle(FlockTheme.textSecondary)
                }
            }
            .frame(width: 210, alignment: .leading)

            StatusMenuControl(
                symbolName: connectionSymbolName,
                title: "Scanner",
                value: esp32PrimaryValue,
                detail: esp32DetailValue,
                valueColor: connectionColor
            ) {
                connectionMenuContent
            }

            StatusMenuControl(
                symbolName: "antenna.radiowaves.left.and.right",
                title: "Scan Mode",
                value: scanModePrimaryValue,
                detail: scanModeDetailValue,
                valueColor: scanModeStatusColor
            ) {
                ForEach(ScanMode.allCases) { mode in
                    Button {
                        viewModel.setScanMode(mode)
                    } label: {
                        Label(mode.rawValue, systemImage: viewModel.status.mode == mode ? "checkmark" : "")
                    }
                    .disabled(!canControlScanner)
                }
            }

            StatusMenuControl(
                symbolName: "wifi",
                title: "Wi-Fi Channel",
                value: wifiChannelPrimaryValue,
                detail: wifiChannelDetailValue,
                valueColor: wifiChannelStatusColor
            ) {
                if viewModel.scannerSource == .hardware {
                    Text("Firmware channel hopping")
                    Text("Current: \(viewModel.status.wifiChannelDisplay)")
                } else if viewModel.scannerSource == .macNative {
                    Text("CoreWLAN scans visible networks")
                    Text("Manual channel selection is unavailable")
                } else {
                    ForEach(WiFiChannelSetting.allCases) { channel in
                        Button {
                            viewModel.setWiFiChannel(channel)
                        } label: {
                            Label(channel.rawValue, systemImage: viewModel.status.wifiChannelDisplay == channel.displayValue ? "checkmark" : "")
                        }
                    }
                }
            }

            StatusMenuControl(
                symbolName: "wave.3.right",
                title: "BLE Scan",
                value: blePrimaryValue,
                detail: bleDetailValue,
                valueColor: bleStatusColor
            ) {
                if viewModel.scannerSource == .macNative {
                    Text("CoreBluetooth scans while BLE mode is enabled")
                    Text("BLE MAC addresses are not exposed by macOS")
                } else {
                    ForEach(BLEScanState.allCases) { state in
                        Button {
                            viewModel.setBLEScanState(state)
                        } label: {
                            Label(state.rawValue, systemImage: viewModel.status.bleScanState == state ? "checkmark" : "")
                        }
                        .disabled(!canControlScanner)
                    }
                }
            }

            Spacer(minLength: 12)

            Text(viewModel.sessionSourceLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(sourceColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(sourceColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(sourceColor.opacity(0.16), lineWidth: 1)
                }
                .accessibilityLabel("Session source \(viewModel.sessionSourceLabel)")

            Button {
                Task {
                    await viewModel.toggleScan()
                }
            } label: {
                Label(viewModel.scanControlState.buttonLabel, systemImage: viewModel.scanControlState.buttonSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 132)
            }
            .buttonStyle(.plain)
            .controlSurface()
            .help(viewModel.scanControlState.buttonLabel)
            .accessibilityLabel(viewModel.scanControlState.buttonLabel)

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 38, height: 34)
            }
            .buttonStyle(.plain)
            .controlSurface()
            .help("Settings")
            .accessibilityLabel("Open Settings")
        }
        .frame(height: 64)
    }

    @ViewBuilder
    private var connectionMenuContent: some View {
        if viewModel.scannerSource == .macNative {
            Text("Mac BLE + Wi-Fi Scanner")
            Text("CoreBluetooth + CoreWLAN")

            Divider()

            Button {
                Task {
                    await viewModel.reconnectCurrentScanner()
                }
            } label: {
                Label("Reconnect Mac Scanner", systemImage: "arrow.clockwise")
            }

            Button {
                Task {
                    await viewModel.disconnectCurrentScanner()
                }
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }
        } else {
            Button {
                Task {
                    await viewModel.refreshDevices()
                }
            } label: {
                Label("Refresh Devices", systemImage: "arrow.clockwise")
            }

            if viewModel.availableSerialDevices.isEmpty {
                Text("No serial devices found")
            } else {
                Section("Serial Devices") {
                    ForEach(viewModel.availableSerialDevices) { device in
                        Button {
                            Task {
                                await viewModel.connectToDevice(device)
                            }
                        } label: {
                            Label(device.displayName, systemImage: device.isLikelyESP32 ? "cpu" : "cable.connector")
                        }
                        .help(device.path)
                    }
                }
            }

            Divider()

            Toggle("Auto-Reconnect", isOn: $settings.autoReconnect)
        }

        if settings.developerRecordedMode {
            Button {
                Task {
                    await viewModel.switchSource(.recorded)
                }
            } label: {
                Label("Recorded Playback", systemImage: viewModel.scannerSource == .recorded ? "checkmark" : "recordingtape")
            }
        }

        Divider()

        if let device = viewModel.connectionState.connectedDevice {
            Text(device.displayName)
            Text(device.path)
            if let version = viewModel.connectionState.capabilities?.firmwareVersion {
                Text("Firmware \(version)")
            }
            Button("Disconnect") {
                Task {
                    await viewModel.disconnectCurrentScanner()
                }
            }
            Button("Reconnect") {
                Task {
                    await viewModel.reconnectCurrentScanner()
                }
            }
        } else {
            Button("Connect Selected Device") {
                Task {
                    if viewModel.scannerSource == .macNative {
                        await viewModel.reconnectCurrentScanner()
                    } else if let device = viewModel.selectedSerialDevice ?? viewModel.availableSerialDevices.first {
                        await viewModel.connectToDevice(device)
                    }
                }
            }
            .disabled(viewModel.scannerSource != .macNative && viewModel.availableSerialDevices.isEmpty)
        }

        Button("Open Diagnostics") {
            viewModel.isDiagnosticsPresented = true
        }

        if let error = viewModel.lastConnectionError {
            Divider()
            Text(error)
        }
    }

    private var canControlScanner: Bool {
        switch viewModel.scannerSource {
        case .hardware, .macNative:
            return viewModel.connectionState.isConnected && !viewModel.scanControlState.isBusy
        case .test, .recorded:
            return !viewModel.scanControlState.isBusy
        }
    }

    private var isRadarScanning: Bool {
        viewModel.status.isScanning || viewModel.scanControlState == .starting || viewModel.scanControlState == .scanning
    }

    private var esp32PrimaryValue: String {
        if viewModel.scannerSource == .macNative {
            switch viewModel.connectionState {
            case .connected:
                return "Mac Scanner"
            case .failed:
                return "Unavailable"
            case .disconnected:
                return "Disconnected"
            default:
                return viewModel.connectionState.visibleStatus
            }
        }

        switch viewModel.connectionState {
        case .connected:
            return "Connected"
        case .discovering:
            return "Discovering…"
        case .connecting:
            return "Connecting…"
        case .handshaking:
            return "Handshaking…"
        case .reconnecting(let attempt):
            return "Reconnecting · \(attempt)"
        case .failed:
            return "Connection failed"
        case .testMode:
            return "Test source"
        case .recordedMode:
            return "Recorded source"
        case .disconnected:
            return "Disconnected"
        }
    }

    private var esp32DetailValue: String {
        if viewModel.scannerSource == .macNative {
            switch viewModel.connectionState {
            case .connected:
                return "CoreBluetooth + CoreWLAN"
            case .failed:
                return "Check permissions"
            case .disconnected:
                return "Mac radios"
            default:
                return "Mac radios"
            }
        }

        switch viewModel.connectionState {
        case .connected(let device, _):
            return device.displayName
        case .failed:
            return "Check connection"
        case .testMode:
            return "Local test source"
        case .recordedMode:
            return "Fixture playback"
        default:
            return "ESP32 scanner"
        }
    }

    private var scanModePrimaryValue: String {
        if viewModel.scannerSource.requiresScannerConnection && !viewModel.connectionState.isConnected {
            return "Unavailable"
        }

        switch viewModel.status.mode {
        case .dual:
            return "Dual"
        case .wifiOnly:
            return "Wi-Fi Only"
        case .bleOnly:
            return "BLE Only"
        }
    }

    private var scanModeDetailValue: String {
        if viewModel.scannerSource.requiresScannerConnection && !viewModel.connectionState.isConnected {
            return "Scanner offline"
        }

        return viewModel.status.isScanning ? "Scanning mode" : "Selected mode"
    }

    private var scanModeStatusColor: Color {
        if viewModel.scanControlState.isBusy {
            return FlockTheme.signalYellow
        }

        if viewModel.scannerSource.requiresScannerConnection && !viewModel.connectionState.isConnected {
            return FlockTheme.textMuted
        }

        return FlockTheme.signalGreen
    }

    private var wifiChannelPrimaryValue: String {
        if viewModel.scannerSource.requiresScannerConnection && !viewModel.connectionState.isConnected {
            return "Unavailable"
        }

        guard let channel = viewModel.status.wifiChannel else {
            return "Hopping"
        }

        return "CH \(channel)"
    }

    private var wifiChannelDetailValue: String {
        if viewModel.scannerSource.requiresScannerConnection && !viewModel.connectionState.isConnected {
            return "Wi-Fi scanner"
        }

        guard let channel = viewModel.status.wifiChannel else {
            if viewModel.scannerSource == .hardware {
                return "Firmware hop"
            }
            if viewModel.scannerSource == .macNative {
                return "CoreWLAN scan"
            }
            return "Auto hop"
        }

        return "\(frequencyMHz(forWiFiChannel: channel)) MHz"
    }

    private var wifiChannelStatusColor: Color {
        if viewModel.scannerSource.requiresScannerConnection && !viewModel.connectionState.isConnected {
            return FlockTheme.textMuted
        }

        return FlockTheme.signalGreen
    }

    private var blePrimaryValue: String {
        if viewModel.scannerSource.requiresScannerConnection && !viewModel.connectionState.isConnected {
            return "Unavailable"
        }

        return viewModel.status.bleScanState.rawValue
    }

    private var bleDetailValue: String {
        if viewModel.scannerSource.requiresScannerConnection && !viewModel.connectionState.isConnected {
            return "BLE scanner"
        }

        switch viewModel.status.bleScanState {
        case .active:
            return "Listening now"
        case .waiting:
            return "Waiting phase"
        case .paused:
            return "Scan paused"
        case .disabled:
            return "Off in Wi-Fi mode"
        case .unavailable:
            return "Unavailable"
        }
    }

    private var bleStatusColor: Color {
        if viewModel.scannerSource.requiresScannerConnection && !viewModel.connectionState.isConnected {
            return FlockTheme.textMuted
        }

        switch viewModel.status.bleScanState {
        case .active:
            return FlockTheme.signalGreen
        default:
            return FlockTheme.signalYellow
        }
    }

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .connected:
            FlockTheme.signalGreen
        case .discovering, .connecting, .handshaking, .reconnecting:
            FlockTheme.signalYellow
        case .failed:
            FlockTheme.signalRed
        case .testMode, .recordedMode:
            FlockTheme.textSecondary
        case .disconnected:
            FlockTheme.textMuted
        }
    }

    private var sourceColor: Color {
        switch viewModel.scannerSource {
        case .hardware:
            viewModel.connectionState.isConnected ? FlockTheme.signalGreen : FlockTheme.signalYellow
        case .macNative:
            viewModel.connectionState.isConnected ? FlockTheme.signalGreen : FlockTheme.signalYellow
        case .test:
            FlockTheme.textSecondary
        case .recorded:
            FlockTheme.signalYellow
        }
    }

    private var connectionSymbolName: String {
        switch viewModel.scannerSource {
        case .macNative:
            "macbook.and.iphone"
        case .hardware:
            "cpu"
        case .test:
            "play.rectangle"
        case .recorded:
            "recordingtape"
        }
    }

    private func frequencyMHz(forWiFiChannel channel: Int) -> Int {
        2407 + channel * 5
    }
}

private struct StatusMenuControl<MenuContent: View>: View {
    var symbolName: String
    var title: String
    var value: String
    var detail: String
    var valueColor: Color
    @ViewBuilder var menuContent: () -> MenuContent

    var body: some View {
        Menu {
            menuContent()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(FlockTheme.textSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FlockTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(valueColor)
                            .frame(width: 6, height: 6)

                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(valueColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(FlockTheme.textMuted)
            }
            .frame(width: title == "BLE Scan" ? 142 : 188, height: 40)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .controlSurface()
        .help("\(title): \(value), \(detail)")
        .accessibilityLabel("\(title), \(value), \(detail)")
    }
}

private struct RadarLogo: View {
    var isScanning: Bool
    var reduceMotion: Bool
    @State private var frozenRotationDegrees = -32.0
    @State private var scanStartDate = Date()
    @State private var scanStartRotationDegrees = -32.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: !isScanning || reduceMotion)) { timeline in
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let rotationDegrees = displayedDegrees(at: timeline.date)
                let rotation = Angle(degrees: rotationDegrees)

                ZStack {
                    ForEach([0.38, 0.68, 0.94], id: \.self) { scale in
                        Circle()
                            .stroke(FlockTheme.signalGreen.opacity(scale == 0.94 ? 0.65 : 0.85), lineWidth: scale == 0.94 ? 4 : 3)
                            .frame(width: size * scale, height: size * scale)
                    }

                    if isScanning && !reduceMotion {
                        ForEach(1..<6, id: \.self) { index in
                            sweepPath(center: center, size: size)
                                .fill(FlockTheme.signalGreen.opacity(0.10 / Double(index)))
                                .rotationEffect(.degrees(rotationDegrees - Double(index) * 10))
                                .blur(radius: CGFloat(index) * 0.35)

                            radarLine(center: center, size: size)
                                .stroke(
                                    FlockTheme.signalGreen.opacity(0.16 / Double(index)),
                                    style: StrokeStyle(lineWidth: max(1.4, 4.0 - CGFloat(index) * 0.45), lineCap: .round)
                                )
                                .rotationEffect(.degrees(rotationDegrees - Double(index) * 8))
                                .blur(radius: CGFloat(index) * 0.45)
                        }
                    }

                    sweepPath(center: center, size: size)
                        .fill(FlockTheme.signalGreen.opacity(isScanning && !reduceMotion ? 0.12 : 0.06))
                        .rotationEffect(rotation)

                    radarLine(center: center, size: size)
                    .stroke(FlockTheme.signalGreen.opacity(0.92), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(rotation)
                    .shadow(color: FlockTheme.signalGreen.opacity(isScanning && !reduceMotion ? 0.24 : 0.0), radius: 3, x: 0, y: 0)

                    Circle()
                        .fill(FlockTheme.signalGreen)
                        .frame(width: size * 0.13, height: size * 0.13)
                }
            }
        }
        .onAppear {
            if isScanning && !reduceMotion {
                scanStartDate = Date()
                scanStartRotationDegrees = frozenRotationDegrees
            }
        }
        .onChange(of: isScanning) { _, scanning in
            if scanning {
                scanStartDate = Date()
                scanStartRotationDegrees = frozenRotationDegrees
            } else {
                frozenRotationDegrees = currentDegrees(at: Date())
            }
        }
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced {
                frozenRotationDegrees = currentDegrees(at: Date())
            } else if isScanning {
                scanStartDate = Date()
                scanStartRotationDegrees = frozenRotationDegrees
            }
        }
    }

    private func displayedDegrees(at date: Date) -> Double {
        guard isScanning, !reduceMotion else {
            return frozenRotationDegrees
        }

        return currentDegrees(at: date)
    }

    private func currentDegrees(at date: Date) -> Double {
        let cycleDuration = 1.75
        let elapsed = max(0, date.timeIntervalSince(scanStartDate))
        let degrees = scanStartRotationDegrees + (elapsed / cycleDuration * 360)
        return degrees.truncatingRemainder(dividingBy: 360)
    }

    private func sweepPath(center: CGPoint, size: CGFloat) -> Path {
        Path { path in
            path.move(to: center)
            path.addArc(
                center: center,
                radius: size * 0.43,
                startAngle: .degrees(-18),
                endAngle: .degrees(9),
                clockwise: false
            )
            path.closeSubpath()
        }
    }

    private func radarLine(center: CGPoint, size: CGFloat) -> Path {
        Path { path in
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + size * 0.39, y: center.y))
        }
    }
}

#Preview("Top Status Bar") {
    let settings = AppSettings()
    TopStatusBar()
        .environmentObject(ScannerViewModel(transport: MockScannerTransport(settings: settings), settings: settings))
        .environmentObject(settings)
        .padding()
        .background(FlockTheme.background)
        .frame(width: 1500)
}
