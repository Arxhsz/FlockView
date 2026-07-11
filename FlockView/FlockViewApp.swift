import AppKit
import SwiftUI

@main
struct FlockViewApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var viewModel: ScannerViewModel

    init() {
        let appSettings = AppSettings()
        _settings = StateObject(wrappedValue: appSettings)
        _viewModel = StateObject(
            wrappedValue: ScannerViewModel(
                settings: appSettings
            )
        )
        NotificationService.shared.requestAuthorizationIfNeeded(enabled: appSettings.cameraDetectionNotifications)
        Self.applyApplicationIcon()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(viewModel)
                .environmentObject(settings)
                .onAppear {
                    NotificationService.shared.requestAuthorizationIfNeeded(enabled: settings.cameraDetectionNotifications)
                    Self.applyApplicationIcon()
                }
        }
        .defaultSize(width: 1600, height: 960)
        .commands {
            FlockCommands(viewModel: viewModel, settings: settings)
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(viewModel)
        }
    }

    private static func applyApplicationIcon() {
        if let image = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = image
            return
        }

        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }
}

struct FlockCommands: Commands {
    @ObservedObject var viewModel: ScannerViewModel
    @ObservedObject var settings: AppSettings

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()
            Button("Export JSON") {
                Task {
                    await viewModel.exportJSON()
                }
            }
            .keyboardShortcut("e", modifiers: [.command])

            Button("Export CSV") {
                Task {
                    await viewModel.exportCSV()
                }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandMenu("Scanner") {
            Button(viewModel.scanControlState.buttonLabel) {
                Task {
                    await viewModel.toggleScan()
                }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(viewModel.scanControlState.isBusy)

            Button("Reset Session") {
                Task {
                    await viewModel.clearSession()
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandMenu("View") {
            Button("Toggle Inspector") {
                viewModel.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            Toggle("Compact Rows", isOn: $settings.compactCameraRows)

            Button("Focus Search") {
                NotificationCenter.default.post(name: .focusSearchRequested, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command])
        }

        CommandGroup(replacing: .help) {
            Button("About FlockView") {
                NSApplication.shared.orderFrontStandardAboutPanel(
                    options: [
                        .applicationName: "FlockView",
                        .applicationVersion: "1.0.0",
                        .credits: NSAttributedString(string: "Native SwiftUI scanner console for FlockViewScanner over USB serial, with explicit Test Mode for local verification.")
                    ]
                )
            }
        }
    }
}
