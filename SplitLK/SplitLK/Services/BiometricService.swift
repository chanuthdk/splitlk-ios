import Foundation
import LocalAuthentication

/// Wraps LocalAuthentication so views don't touch LAContext directly.
@MainActor
@Observable
final class BiometricService {

    enum State {
        case locked
        case unlocked
        case failed(String)
    }

    private(set) var state: State = .locked

    var isUnlocked: Bool {
        if case .unlocked = state { return true }
        return false
    }

    /// What the device actually offers, so the button can say the right thing.
    var biometryLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        default:       return "Passcode"
        }
    }

    var symbolName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .touchID ? "touchid" : "faceid"
    }

    func authenticate() async {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        // deviceOwnerAuthentication falls back to the passcode automatically,
        // so a user whose biometrics fail is never locked out of their own data.
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set at all — there is nothing to authenticate against,
            // so locking the user out would be worse than letting them in.
            state = .unlocked
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock SplitLK to view your balances"
            )
            state = success ? .unlocked : .failed("Authentication was not successful.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func lock() {
        state = .locked
    }
}
