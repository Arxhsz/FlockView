import SwiftUI

struct CameraListView: View {
    @EnvironmentObject private var viewModel: ScannerViewModel
    @EnvironmentObject private var settings: AppSettings
    @FocusState private var searchFocused: Bool
    @State private var notePreviewCamera: CameraDetection?

    var onCameraSelected: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, LayoutMetrics.windowPadding)
                .padding(.top, LayoutMetrics.panelSpacing)
                .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: LayoutMetrics.rowSpacing) {
                    ForEach(viewModel.visibleCameras) { camera in
                        CameraRowView(
                            camera: camera,
                            isSelected: viewModel.selectedCameraID == camera.id,
                            compact: settings.compactCameraRows,
                            onToggleMarked: {
                                viewModel.toggleMarked(cameraID: camera.id)
                            },
                            onViewNote: {
                                notePreviewCamera = camera
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.select(camera)
                            onCameraSelected()
                        }
                        .focusable(true)
                        .focusEffectDisabled()
                    }

                    if viewModel.visibleCameras.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, LayoutMetrics.rowSpacing)
            }

            Text("Showing \(viewModel.activeCameraCount) active · \(viewModel.exportCameras.count) in session")
                .font(.caption)
                .foregroundStyle(FlockTheme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .flockPanel(strong: false)
        .popover(item: $notePreviewCamera) { camera in
            NoteViewerView(camera: camera)
                .frame(width: 360)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchRequested)) { _ in
            searchFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Detected Cameras")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(FlockTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(2)

            Text("\(viewModel.activeCameraCount)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FlockTheme.signalGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(FlockTheme.signalGreen.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.smallRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LayoutMetrics.smallRadius, style: .continuous)
                        .stroke(FlockTheme.signalGreen.opacity(0.14), lineWidth: 1)
                }
                .accessibilityLabel("\(viewModel.activeCameraCount) active cameras")

            Spacer()

            Text("Sort by:")
                .font(.caption)
                .foregroundStyle(FlockTheme.textSecondary)

            Menu {
                ForEach(CameraSortOption.allCases) { option in
                    Button {
                        viewModel.sortOption = option
                    } label: {
                        Label(option.rawValue, systemImage: viewModel.sortOption == option ? "checkmark" : "")
                    }
                }
            } label: {
                HStack {
                    Text(viewModel.sortOption.rawValue)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .frame(width: 118)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .controlSurface()
            .help("Sort cameras")

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FlockTheme.textSecondary)

                TextField("Search cameras...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityLabel("Search cameras")

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(FlockTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .frame(width: 240)
            .controlSurface()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 34))
                .foregroundStyle(FlockTheme.textMuted)
            Text("No active cameras")
                .font(.headline)
                .foregroundStyle(FlockTheme.textSecondary)
            Text("Detections appear while scanning and expire after \(Int(settings.activeDetectionTimeout)) seconds unseen.")
                .font(.caption)
                .foregroundStyle(FlockTheme.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Camera List") {
    let settings = AppSettings()
    CameraListView {}
        .environmentObject(ScannerViewModel(transport: MockScannerTransport(settings: settings), settings: settings))
        .environmentObject(settings)
        .frame(width: 1040, height: 720)
        .padding()
        .background(FlockTheme.background)
}
