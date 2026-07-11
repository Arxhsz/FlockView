import SwiftUI

struct ToastView: View {
    var toast: ToastMessage

    var body: some View {
        Label(toast.text, systemImage: toast.symbolName)
            .font(.headline)
            .foregroundStyle(FlockTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                AcrylicSurface(opacity: 0.82, strong: true, cornerRadius: 8, blur: 24)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(FlockTheme.borderStrong, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 8)
            .accessibilityElement(children: .combine)
    }
}

#Preview("Toast") {
    ToastView(toast: ToastMessage(text: "Camera marked", symbolName: "star.fill"))
        .padding()
        .background(FlockTheme.background)
}
