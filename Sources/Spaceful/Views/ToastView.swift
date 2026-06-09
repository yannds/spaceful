import SwiftUI

/// Transient confirmation after a trash action, with an Undo button and a close control.
/// Floats at the bottom of the window and auto-dismisses after a few seconds.
struct ToastView: View {
    @EnvironmentObject var model: AppModel
    let toast: ToastState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text(toast.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button("Annuler") { toast.undo() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button { model.dismissToast() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Fermer")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.horizontal, 20).padding(.bottom, 16)
        .frame(maxWidth: 560)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.message)
    }
}
