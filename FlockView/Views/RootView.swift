import AppKit
import SwiftUI

extension Notification.Name {
    static let focusSearchRequested = Notification.Name("FlockView.focusSearchRequested")
}

struct RootView: View {
    @EnvironmentObject private var viewModel: ScannerViewModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        GeometryReader { proxy in
            let isNarrow = proxy.size.width < 1180

            ZStack(alignment: .top) {
                MicaWindowBackground()
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    TopStatusBar()

                    HStack(spacing: 10) {
                        CameraListView {
                            if isNarrow {
                                viewModel.isDetailSheetPresented = true
                            }
                        }

                        if !isNarrow, viewModel.isInspectorVisible {
                            CameraDetailView(isSheet: false)
                                .frame(width: 430)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: settings.reduceMotion ? 0 : 0.2), value: viewModel.isInspectorVisible)

                    BottomStatusBar()
                }
                .padding(.top, 16)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

                if let toast = viewModel.toast {
                    ToastView(toast: toast)
                        .padding(.top, 42)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(2)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { isNarrow && viewModel.isDetailSheetPresented },
                    set: { viewModel.isDetailSheetPresented = $0 }
                )
            ) {
                CameraDetailView(isSheet: true)
                    .environmentObject(viewModel)
                    .environmentObject(settings)
                    .frame(minWidth: 520, minHeight: 720)
                    .background(FlockTheme.background)
            }
            .sheet(item: $viewModel.rawEvent) { event in
                RawEventSheet(event: event)
                    .frame(width: 620, height: 420)
                    .environmentObject(settings)
            }
            .sheet(isPresented: $viewModel.isDiagnosticsPresented) {
                DiagnosticsView()
                    .environmentObject(viewModel)
                    .environmentObject(settings)
                    .frame(width: 760, height: 640)
                    .background(FlockTheme.background)
            }
            .onChange(of: proxy.size.width) { _, width in
                if width >= 1180 {
                    viewModel.isDetailSheetPresented = false
                }
            }
        }
        .preferredColorScheme(.dark)
        .background(WindowConfigurator())
    }
}

private struct RawEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: RawEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Raw Event")
                        .font(.headline)
                        .foregroundStyle(FlockTheme.textPrimary)
                    Text(event.cameraName)
                        .font(.subheadline)
                        .foregroundStyle(FlockTheme.textSecondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            TextEditor(text: .constant(event.text))
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .flockPanel(strong: true)
                .accessibilityLabel("Raw event")
        }
        .padding(20)
        .background(FlockTheme.background)
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }

        window.title = "FlockView"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.minSize = NSSize(width: 1280, height: 760)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

#Preview("Root View") {
    let settings = AppSettings()
    RootView()
        .environmentObject(ScannerViewModel(transport: MockScannerTransport(settings: settings), settings: settings))
        .environmentObject(settings)
        .frame(width: 1600, height: 960)
}
