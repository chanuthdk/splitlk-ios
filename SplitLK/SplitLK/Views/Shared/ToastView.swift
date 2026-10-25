import SwiftUI

/// A brief confirmation that something was saved.
///
/// An alert would need dismissing, and a silent return to the list leaves the
/// user unsure whether the save worked — this says so and gets out of the way.
struct ToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Capsule().fill(Color.green.gradient))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .padding(.horizontal, 20)
    }
}

extension View {
    /// Shows a toast while `message` is non-nil, then clears it.
    ///
    /// The binding is cleared by the toast itself rather than by a timer at
    /// the call site, so a second save during the first toast restarts the
    /// countdown instead of leaving one stuck on screen.
    func toast(message: Binding<String?>, duration: Duration = .seconds(2.2)) -> some View {
        modifier(ToastModifier(message: message, duration: duration))
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    let duration: Duration

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    ToastView(message: message)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        // Announced rather than left as a visual-only cue,
                        // since the confirmation is the whole point.
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .animation(.snappy, value: message)
            .task(id: message) {
                guard message != nil else { return }
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                await clear()
            }
    }

    /// The closure `.task` takes is sendable rather than main-actor isolated,
    /// so the write is hopped explicitly instead of relying on where the
    /// closure happens to run.
    @MainActor
    private func clear() {
        message = nil
    }
}
