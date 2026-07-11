import SwiftUI

struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var noteText: String

    var cameraName: String
    var onSave: (String) -> Void

    init(camera: CameraDetection, onSave: @escaping (String) -> Void) {
        cameraName = camera.name
        self.onSave = onSave
        _noteText = State(initialValue: camera.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(cameraName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(FlockTheme.textPrimary)

            TextEditor(text: $noteText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 220)
                .flockPanel(strong: true)
                .accessibilityLabel("Camera note")

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save Note") {
                    onSave(noteText)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(FlockTheme.background)
    }
}

struct NoteViewerView: View {
    @Environment(\.dismiss) private var dismiss

    let camera: CameraDetection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(camera.name)
                    .font(.headline)
                    .foregroundStyle(FlockTheme.textPrimary)
                Text(camera.macAddress)
                    .font(.caption.monospaced())
                    .foregroundStyle(FlockTheme.textSecondary)
            }

            ScrollView {
                Text(camera.note)
                    .font(.body)
                    .foregroundStyle(FlockTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120, maxHeight: 220)

            if let noteUpdatedAt = camera.noteUpdatedAt {
                Text("Updated \(noteUpdatedAt.flockDateTimeString)")
                    .font(.caption)
                    .foregroundStyle(FlockTheme.textMuted)
            }

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .background(FlockTheme.background)
    }
}

#Preview("Note Editor") {
    NoteEditorView(camera: CameraDetection.makeMockDetections()[0]) { _ in }
        .environmentObject(AppSettings())
}

#Preview("Note Viewer") {
    var camera = CameraDetection.makeMockDetections()[0]
    camera.note = "Observed near the north gate with strong RSSI."
    camera.noteUpdatedAt = Date()
    return NoteViewerView(camera: camera)
        .frame(width: 360)
        .background(FlockTheme.background)
}
