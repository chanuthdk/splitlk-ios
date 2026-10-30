import SwiftUI

/// The locked state, drawn as a folded receipt: the app's name printed above
/// the tear, nothing below it. The balances really are on the other side of
/// the fold, so the screen says what is being withheld rather than just
/// showing a padlock.
struct LockView: View {
    let service: BiometricService

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            receipt

            Spacer()

            if case .failed(let message) = service.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Palette.owing)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }

            Button {
                Task {
                    if service.biometricsBlocked {
                        await service.authenticateWithPasscode()
                    } else {
                        await service.authenticate()
                    }
                }
            } label: {
                Label(service.actionTitle, systemImage: service.symbolName)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Palette.stamp)
            .disabled(service.isAuthenticating)
            .padding(.horizontal, 32)

            // Offered only while biometrics are still the main route. Once
            // they are blocked the button above is already the passcode.
            if service.passcodeAvailable && !service.biometricsBlocked {
                Button("Use passcode instead") {
                    Task { await service.authenticateWithPasscode() }
                }
                .font(.subheadline)
                .tint(Palette.stamp)
                .disabled(service.isAuthenticating)
                .padding(.top, 10)
            }
        }
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
        .animation(.snappy, value: service.state)
    }

    private var receipt: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("SplitLK")
                    .font(.system(.largeTitle, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                Text("Locked")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.inkSoft)
            }
            .padding(.top, 36)
            .padding(.bottom, 26)

            TearLine()
                .padding(.horizontal, 18)

            // Below the tear: what is being withheld, drawn as redacted
            // figures rather than left blank, so the shape of the screen
            // matches the one behind it.
            VStack(alignment: .leading, spacing: 11) {
                redactedRow(width: 0.55)
                redactedRow(width: 0.78)
                redactedRow(width: 0.4)
            }
            .padding(.horizontal, 26)
            .padding(.top, 26)
            .padding(.bottom, 34)
        }
        .frame(maxWidth: 300)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Palette.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Palette.rule, lineWidth: 1)
                }
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SplitLK is locked. Your balances are hidden.")
    }

    private func redactedRow(width: CGFloat) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 10) {
                Capsule()
                    .fill(Palette.rule)
                    .frame(width: proxy.size.width * width, height: 9)
                Spacer(minLength: 0)
                Capsule()
                    .fill(Palette.rule)
                    .frame(width: 44, height: 9)
            }
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }
}
