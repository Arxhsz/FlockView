import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var viewModel: ScannerViewModel
    @State private var notificationPermissionStatus = "Checking..."
    @State private var notificationActionMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsSection("Scanner Source") {
                    Picker("Source", selection: $settings.scannerSource) {
                        Text("Hardware").tag(ScannerSource.hardware)
                        Text("Mac Scanner").tag(ScannerSource.macNative)
                        Text("Test Mode").tag(ScannerSource.test)
                        if settings.developerRecordedMode {
                            Text("Recorded Playback").tag(ScannerSource.recorded)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: settings.scannerSource) { _, source in
                        Task {
                            await viewModel.switchSource(source)
                        }
                    }

                    Toggle("Auto-Reconnect", isOn: $settings.autoReconnect)
                    Toggle("Developer Recorded Playback", isOn: $settings.developerRecordedMode)

                    HStack {
                        Button("Refresh Devices") {
                            Task {
                                await viewModel.refreshDevices()
                            }
                        }

                        Button("Open Diagnostics") {
                            viewModel.isDiagnosticsPresented = true
                        }

                        Spacer()

                        Text(viewModel.connectionState.visibleStatus)
                            .foregroundStyle(FlockTheme.textSecondary)
                    }
                }

                settingsSection("Detection") {
                    Toggle("Camera Detection Notifications", isOn: $settings.cameraDetectionNotifications)
                    Toggle("Notification Sound", isOn: $settings.notificationSoundEnabled)
                        .disabled(!settings.cameraDetectionNotifications)
                    Toggle("In-App Detection Sound", isOn: $settings.detectionSoundEnabled)

                    Text("Detection notifications are sent only while FlockView is in the background. Detections received within one second are grouped into one alert and one sound.")
                        .font(.caption)
                        .foregroundStyle(FlockTheme.textMuted)

                    HStack {
                        Text("macOS Permission")
                            .foregroundStyle(FlockTheme.textSecondary)
                        Spacer()
                        Text(notificationPermissionStatus)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(notificationPermissionStatus == "Authorized" ? FlockTheme.signalGreen : FlockTheme.signalYellow)
                    }

                    HStack {
                        Button("Request Permission") {
                            Task {
                                notificationPermissionStatus = await NotificationService.shared.requestAuthorizationFromUser()
                                notificationActionMessage = notificationPermissionStatus
                            }
                        }

                        Button("Send Test Notification") {
                            Task {
                                notificationActionMessage = await NotificationService.shared.sendTestNotification(settings: settings)
                                notificationPermissionStatus = await NotificationService.shared.notificationPermissionStatusText()
                            }
                        }

                        Button("Open macOS Notification Settings") {
                            NotificationService.shared.openSystemNotificationSettings()
                        }
                    }

                    if let notificationActionMessage {
                        Text(notificationActionMessage)
                            .font(.caption)
                            .foregroundStyle(FlockTheme.textMuted)
                    }

                    sliderRow(
                        "Active timeout (sec)",
                        value: $settings.activeDetectionTimeout,
                        range: 5 ... 120,
                        format: "%.0f"
                    )
                    Text("Cameras disappear from the active list after this many seconds without a new observation.")
                        .font(.caption)
                        .foregroundStyle(FlockTheme.textMuted)
                }

                settingsSection("Appearance") {
                    sliderRow("Matte Transparency", value: $settings.matteTransparency, range: 0.48 ... 0.9, format: "%.2f")
                    sliderRow("Background Blur", value: $settings.backgroundBlur, range: 0 ... 36, format: "%.0f")
                    Toggle("Reduce Motion", isOn: $settings.reduceMotion)
                    Toggle("Compact Camera Rows", isOn: $settings.compactCameraRows)
                }

                settingsSection("Signal Thresholds") {
                    thresholdStepper("Close threshold", value: $settings.closeThreshold, range: -70 ... -45)
                    thresholdStepper("Medium threshold", value: $settings.mediumThreshold, range: -88 ... -55)
                    thresholdStepper("Far threshold", value: $settings.farThreshold, range: -100 ... -70)

                    Button("Reset Thresholds") {
                        settings.resetThresholds()
                    }
                }

                settingsSection("Test Mode") {
                    Picker("New detection style", selection: $settings.testDetectionEmissionMode) {
                        ForEach(TestDetectionEmissionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    sliderRow("Detection interval", value: $settings.testDetectionInterval, range: 3 ... 60, format: "%.0f sec")
                    sliderRow("RSSI update speed", value: $settings.mockUpdateSpeed, range: 2 ... 4, format: "%.1f sec")

                    Stepper(value: $settings.testBatchCameraCount, in: 2 ... 8) {
                        HStack {
                            Text("Batch camera count")
                                .foregroundStyle(FlockTheme.textSecondary)
                            Spacer()
                            Text("\(settings.testBatchCameraCount)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(FlockTheme.signalGreen)
                        }
                    }
                    .disabled(settings.testDetectionEmissionMode != .multiple)

                    Toggle("Pause test feed", isOn: $settings.pauseSimulation)

                    HStack {
                        Button("Reset test data") {
                            Task {
                                await viewModel.resetTestData()
                            }
                        }
                        .disabled(viewModel.scannerSource != .test)

                        Button("Add Test Detection") {
                            viewModel.simulateDetection()
                        }
                        .disabled(viewModel.scannerSource != .test)
                    }
                }

                settingsSection("Data") {
                    HStack {
                        Button("Clear current session") {
                            Task {
                                await viewModel.clearSession()
                            }
                        }

                        Spacer()

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
                    }
                }

                settingsSection("About") {
                    HStack {
                        Label("FlockView 1.0.0", systemImage: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(FlockTheme.textSecondary)

                        Spacer()

                        Link(destination: URL(string: "https://github.com/Arxhsz")!) {
                            Label("Made by arxhsz", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.callout.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .help("Open arxhsz on GitHub")
                        .accessibilityLabel("Made by arxhsz on GitHub")
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 560)
        .frame(minHeight: 620)
        .background(FlockTheme.background)
        .task {
            notificationPermissionStatus = await NotificationService.shared.notificationPermissionStatusText()
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(FlockTheme.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .flockPanel(cornerRadius: 8)
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(FlockTheme.textSecondary)
                .frame(width: 160, alignment: .leading)

            Slider(value: value, in: range)

            Text(String(format: format, value.wrappedValue))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(FlockTheme.signalGreen)
                .frame(width: 72, alignment: .trailing)
        }
    }

    private func thresholdStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                    .foregroundStyle(FlockTheme.textSecondary)
                Spacer()
                Text("\(value.wrappedValue) dBm")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(FlockTheme.signalGreen)
            }
        }
    }
}

#Preview("Settings") {
    let settings = AppSettings()
    SettingsView()
        .environmentObject(settings)
        .environmentObject(ScannerViewModel(transport: MockScannerTransport(settings: settings), settings: settings))
}
