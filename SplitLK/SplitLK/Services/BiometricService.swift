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

    /// Whether a device passcode exists to fall back to. Checked rather than
    /// assumed, because a fresh Simulator often has none.
    private(set) var passcodeAvailable = false

    /// Set when biometrics cannot run at all — locked out, not enrolled, or
    /// unsupported. The lock screen then offers the passcode instead of
    /// pretending Face ID is still an option.
    private(set) var biometricsBlocked = false

    var isUnlocked: Bool {
        if case .unlocked = state { return true }
        return false
    }

    // MARK: - What the device offers

    /// Cached rather than probed on demand, because Settings reads the label
    /// from its body and that runs on every redraw. Refreshed whenever an
    /// unlock is attempted, so enrolling Face ID while the app is installed
    /// is picked up without a reinstall — a `let` here meant the first answer
    /// of the process was the only one, and the button went on saying
    /// "Passcode" after Face ID had been turned on.
    private static var cachedBiometry: LABiometryType?

    private static func probeBiometry() -> LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    private static var biometry: LABiometryType {
        if let cachedBiometry { return cachedBiometry }
        let probed = probeBiometry()
        cachedBiometry = probed
        return probed
    }

    static func refreshBiometry() {
        cachedBiometry = probeBiometry()
    }

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

    /// Whether offering to retry biometrics makes any sense. False on a
    /// device with no Face ID or Touch ID at all, where "Try Passcode again"
    /// would be a button that repeats what just happened.
    var hasBiometricHardware: Bool { Self.biometry != .none }

    /// What the unlock button should say right now. Once biometrics are
    /// blocked, offering "Unlock with Face ID" is a lie.
    var actionTitle: String {
        biometricsBlocked ? "Enter Passcode" : "Unlock with \(Self.label)"
    }

    var symbolName: String {
        if biometricsBlocked { return "key.fill" }
        switch Self.biometry {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        // Previously returned "faceid" here, so a device with no biometrics
        // offered a Face ID symbol above the word "Passcode".
        default:       return "lock.fill"
        }
    }

    // MARK: - Authenticating

    /// Tries biometrics specifically.
    ///
    /// The earlier version asked for `.deviceOwnerAuthentication`, which lets
    /// the system pick. That sounds accommodating and is the cause of the bug
    /// it produced: when Face ID is locked out after repeated failures, the
    /// system skips it silently and opens the passcode pad instead, so the
    /// app appeared to ignore a perfectly good Face ID enrolment. Asking for
    /// biometrics by name means a refusal is reported rather than papered
    /// over, and the passcode becomes something the user chooses.
    func authenticate() async {
        guard !isAuthenticating, !isUnlocked else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        // Re-read what the device offers, so enrolling Face ID between
        // attempts takes effect on the next unlock rather than the next
        // launch.
        Self.refreshBiometry()

        passcodeAvailable = LAContext()
            .canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)

        var biometryError: NSError?
        let canUseBiometrics = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &biometryError
        )

        guard canUseBiometrics else {
            biometricsBlocked = true

            // Nothing to authenticate against at all: no biometrics and no
            // passcode. Locking the user out of their own data would be worse
            // than letting them in.
            guard passcodeAvailable else {
                state = .unlocked
                return
            }

            state = .failed(Self.message(for: biometryError))
            return
        }

        biometricsBlocked = false
        await evaluate(context,
                       policy: .deviceOwnerAuthenticationWithBiometrics,
                       allowingFallback: true)
    }

    /// The passcode route, taken only when the user asks for it or biometrics
    /// have already refused.
    func authenticateWithPasscode() async {
        guard !isAuthenticating, !isUnlocked else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            state = .unlocked
            return
        }
        await evaluate(context,
                       policy: .deviceOwnerAuthentication,
                       allowingFallback: false)
    }

    private func evaluate(_ context: LAContext,
                          policy: LAPolicy,
                          allowingFallback: Bool) async {
        do {
            let success = try await context.evaluatePolicy(
                policy,
                localizedReason: "Unlock SplitLK to view your balances"
            )
            state = success ? .unlocked : .locked
        } catch {
            // The user tapped "Use Passcode" inside the biometric sheet.
            // Honour it straight away rather than making them tap again.
            if allowingFallback, (error as? LAError)?.code == .userFallback {
                isAuthenticating = false
                await authenticateWithPasscode()
                return
            }

            if Self.isCancellation(error) {
                state = .locked
            } else {
                if (error as? LAError)?.code == .biometryLockout {
                    biometricsBlocked = true
                }
                state = .failed(Self.message(for: error))
            }
        }
    }

    func lock() {
        state = .locked
        biometricsBlocked = false
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
    private static func message(for error: Error?) -> String {
        guard let error else { return "Authentication is unavailable." }
        guard let code = (error as? LAError)?.code else {
            return error.localizedDescription
        }
        switch code {
        case .biometryNotEnrolled:
            return "\(label) isn't set up on this device. Use your passcode instead."
        case .biometryLockout:
            return "\(label) is locked after too many failed attempts. Enter your passcode to switch it back on."
        case .biometryNotAvailable:
            return "\(label) is unavailable on this device. Use your passcode instead."
        case .passcodeNotSet:
            return "No device passcode is set, so there is nothing to unlock against."
        case .userFallback:
            return "Enter your device passcode to continue."
        case .authenticationFailed:
            return "That wasn't recognised. Try again, or use your passcode."
        default:
            return error.localizedDescription
        }
    }
}
