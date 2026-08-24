import Foundation
import LocalAuthentication

/// Verifies the person at the keyboard is actually this Mac's owner — via
/// Touch ID where available, falling back to the macOS account password
/// otherwise.
///
/// This is the one place in the app-lock flow that checks something the
/// person at the keyboard can't just invent on the spot. The passcode
/// itself is a secret Composure made up locally; "Forgot passcode?" resets
/// *that* secret, so gating the reset on the same kind of secret would be
/// circular — anyone who can tap the button could just set a new one.
/// Requiring the actual device owner's credential is what makes the reset
/// a recovery path rather than a bypass.
protocol DeviceAuthenticating {
    /// Prompts for Touch ID / the account password and returns whether the
    /// device owner was confirmed. `reason` is shown in the system prompt.
    func authenticateDeviceOwner(reason: String) async -> Bool

    /// Whether this Mac actually has a biometric sensor enrolled — as
    /// opposed to `authenticateDeviceOwner` succeeding via the password
    /// fallback. Drives whether `AppLockView` offers a Touch ID button on
    /// the unlock screen at all.
    var supportsBiometrics: Bool { get }
}

struct LAContextDeviceAuthenticator: DeviceAuthenticating {
    func authenticateDeviceOwner(reason: String) async -> Bool {
        let context = LAContext()
        var evaluationError: NSError?

        // `.deviceOwnerAuthentication` (rather than `.deviceOwnerAuthenticationWithBiometrics`)
        // deliberately allows the password fallback — a Mac with no
        // enrolled Touch ID must still have a way to reset the passcode.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            return false
        }

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            // Covers both an explicit failure and the person cancelling
            // the prompt — either way, no reset.
            return false
        }
    }

    var supportsBiometrics: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }
}

// MARK: - Test / Preview Doubles

struct AlwaysSucceedsDeviceAuthenticator: DeviceAuthenticating {
    var supportsBiometrics: Bool = true
    func authenticateDeviceOwner(reason: String) async -> Bool { true }
}

struct AlwaysFailsDeviceAuthenticator: DeviceAuthenticating {
    var supportsBiometrics: Bool = true
    func authenticateDeviceOwner(reason: String) async -> Bool { false }
}
