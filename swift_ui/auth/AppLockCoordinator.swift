import Foundation

/// Gates the whole app behind a passcode, shown by `AppLockGateView` above
/// `RootSwitcherView` — before any profile is chosen, not per-profile. A
/// household shares one Mac and one lock, the same way it already shares
/// one SmartSpectra API key.
///
/// Deliberately holds no reference to `AppModel` or `ProfileCoordinator`:
/// it sits one layer above both, exactly the way `ProfileCoordinator`
/// itself sits above `AppModel`. Ending an in-progress session before
/// locking is the caller's job (see the "Lock Composure" menu command in
/// `SmartSpectraSwiftApp`), not this coordinator's.
@MainActor
final class AppLockCoordinator: ObservableObject {

    /// Whether a passcode has ever been set up. `false` on first launch,
    /// which is what routes `AppLockView` to the "create a passcode"
    /// flow instead of "enter your passcode."
    @Published private(set) var isConfigured: Bool

    /// Whether the app is currently past the lock screen. Starts `false`
    /// even when `isConfigured` is `false` — an unconfigured lock still
    /// has to be *set* once before the rest of the app is reachable.
    @Published private(set) var isUnlocked = false

    @Published var errorMessage: String = ""

    private let store: AppLockCredentialStoring
    private let deviceAuthenticator: DeviceAuthenticating

    /// Consecutive wrong-passcode guesses since the last success (or the
    /// last lockout). Reset by any successful unlock and by each lockout
    /// window elapsing.
    private var failedAttempts = 0

    /// Set once `failedAttempts` crosses `maxAttemptsBeforeLockout` —
    /// `unlock(passcode:)` refuses to even check the passcode until this
    /// passes, so guesses can't be thrown at `store.verify` back-to-back
    /// with no cost.
    private var lockedOutUntil: Date?

    private static let maxAttemptsBeforeLockout = 5
    private static let lockoutDuration: TimeInterval = 30

    init(
        store: AppLockCredentialStoring = KeychainAppLockCredentialStore(),
        deviceAuthenticator: DeviceAuthenticating = LAContextDeviceAuthenticator()
    ) {
        self.store = store
        self.deviceAuthenticator = deviceAuthenticator
        self.isConfigured = store.isConfigured
    }

    /// Creates the passcode and unlocks in one step — there's no separate
    /// confirmation screen between "I just set this" and "I'm in," the
    /// same way a first-run setup flow on any platform works.
    @discardableResult
    func setUp(passcode: String, confirmation: String) -> Bool {
        let trimmedPasscode = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirmation = confirmation.trimmingCharacters(in: .whitespacesAndNewlines)

        // Compared post-trim, matching what `store.setPasscode` itself
        // trims before hashing — otherwise two fields that are equal
        // once trimmed (e.g. a trailing space in only one of them) can
        // report "don't match" while two fields that are unequal once
        // trimmed (matching whitespace padding) can sail through.
        guard trimmedPasscode == trimmedConfirmation else {
            errorMessage = "Passcodes don't match."
            return false
        }

        do {
            try store.setPasscode(trimmedPasscode)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        errorMessage = ""
        failedAttempts = 0
        lockedOutUntil = nil
        isConfigured = true
        isUnlocked = true
        return true
    }

    @discardableResult
    func unlock(passcode: String) -> Bool {
        if let lockedOutUntil {
            let remaining = lockedOutUntil.timeIntervalSinceNow
            if remaining > 0 {
                errorMessage = "Too many attempts. Try again in \(Int(remaining.rounded(.up)))s."
                return false
            }
            self.lockedOutUntil = nil
            failedAttempts = 0
        }

        guard store.verify(passcode) else {
            failedAttempts += 1
            if failedAttempts >= Self.maxAttemptsBeforeLockout {
                lockedOutUntil = Date().addingTimeInterval(Self.lockoutDuration)
                errorMessage = "Too many attempts. Try again in \(Int(Self.lockoutDuration))s."
            } else {
                errorMessage = "Incorrect passcode."
            }
            return false
        }

        errorMessage = ""
        failedAttempts = 0
        lockedOutUntil = nil
        isUnlocked = true
        return true
    }

    func lock() {
        isUnlocked = false
    }

    /// The "Forgot passcode?" escape hatch. Requires proving you're the
    /// device owner first — via `deviceAuthenticator` (Touch ID or the
    /// macOS account password) — since without that check this would just
    /// be a two-tap bypass of the lock rather than a recovery path. Only
    /// once that succeeds does it clear the passcode itself; no profile's
    /// sessions, goals, or logs are touched either way. The view calling
    /// this is responsible for its own confirmation UI first — this
    /// method doesn't ask beyond the device-owner check.
    @discardableResult
    func resetPasscode() async -> Bool {
        guard await deviceAuthenticator.authenticateDeviceOwner(
            reason: "reset your Composure passcode"
        ) else {
            errorMessage = "Authentication failed. Passcode wasn't reset."
            return false
        }

        store.clear()
        isConfigured = false
        isUnlocked = false
        errorMessage = ""
        failedAttempts = 0
        lockedOutUntil = nil
        return true
    }
}
