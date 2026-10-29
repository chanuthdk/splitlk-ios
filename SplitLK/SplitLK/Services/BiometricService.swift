import Foundation
import LocalAuthentication

/// Wraps LocalAuthentication so views don't touch LAContext directly.
@MainActor
@Observable
final class BiometricService {

    enum State: Equatable {
        case locked
        case unlocked
        case failed(String)
    }

    private(set) var state: State = .locked

    /// True while a prompt is on screen. Two prompts at once leaves
    /// LocalAuthentication in a state where neither returns, which looked
    /// from the outside like Face ID had simply stopped working.
    private(set) var isAuthenticating = false

    var isUnlocked: Bool {
        if case .unlocked = state { return true }
        return false
    }

    // MARK: - What the device offers
    //
    // Resolved once rather than on every access: each call built a fresh
    // LAContext, and the label and the symbol were asking separately, so they
    // could disagree with each other.

    /// Static so the LAContext is built once for the process, not once per
    /// caller. Settings reads the label from its body, which ran on every
    /// redraw.
    private static let biometry: LABiometryType = {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }()

    /// What to call the unlock method in the interface. Static so a view can
    /// ask without holding the service.
    static var label: String {
        switch biometry {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        default:       return "Passcode"
        }
    }

    var biometryLabel: String { Self.label }

    var symbolName: String {
        switch Self.biometry {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        // Previously returned "faceid" here, so a device with no biometrics
        // offered a Face ID symbol above the word "Passcode".
        default:       return "lock.fill"
        }
    }

    // MARK: - Authenticating

    func authenticate() async {
        guard !isAuthenticating, !isUnlocked else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        // deviceOwnerAuthentication falls back to the passcode automatically,
        // so a user whose biometrics fail is never locked out of their own data.
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set at all — there is nothing to authenticate
            // against, so locking the user out would be worse than letting
            // them in. This is the usual state of a fresh Simulator.
            state = .unlocked
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock SplitLK to view your balances"
            )
            state = success ? .unlocked : .locked
        } catch {
            state = Self.isCancellation(error) ? .locked : .failed(Self.message(for: error))
        }
    }

    func lock() {
        state = .locked
    }

    // MARK: - Errors

    /// Cancelling is a choice, not a failure. Treating it as one left a red
    /// error on screen after the user had simply dismissed the prompt.
    private static func isCancellation(_ error: Error) -> Bool {
        guard let code = (error as? LAError)?.code else { return false }
        return code == .userCancel || code == .appCancel || code == .systemCancel
    }

    /// LocalAuthentication's own descriptions are written for developers.
    /// These say what the user can do about it.
    private static func message(for error: Error) -> String {
        guard let code = (error as? LAError)?.code else {
            return error.localizedDescription
        }
        switch code {
        case .biometryNotEnrolled:
            return "No Face ID or Touch ID is set up on this device. Use your passcode instead."
        case .biometryLockout:
            return "Too many failed attempts. Unlock with your passcode to re-enable Face ID."
        case .biometryNotAvailable:
            return "Biometrics are unavailable on this device. Use your passcode instead."
        case .userFallback:
            return "Enter your device passcode to continue."
        case .authenticationFailed:
            return "That wasn't recognised. Try again, or use your passcode."
        default:
            return error.localizedDescription
        }
    }
}
