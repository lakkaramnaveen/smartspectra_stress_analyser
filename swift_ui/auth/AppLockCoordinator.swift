import AppKit

/// Errors surfaced by `AppLockCoordinator.changePasscode`. Kept separate
/// from the shared `errorMessage` published property — that one drives the
/// lock screen itself, and a routine passcode change happens from deep
/// inside Settings while already unlocked, so the two shouldn't share one
/// piece of state.
enum ChangePasscodeError: LocalizedError {
    case incorrectCurrentPasscode
    case mismatch
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .incorrectCurrentPasscode:
            return "Current passcode is incorrect."
        case .mismatch:
            return "New passcodes don't match."
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

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

    /// Whether Composure should lock itself the moment the Mac's screen
    /// locks or the system sleeps, rather than staying unlocked
    /// underneath until someone remembers ⌘L. Defaults on: a lock feature
    /// nobody engages automatically only ever protects against someone
    /// deliberately choosing to lock it, which defeats most of the point.
    /// Not a secret, so it lives in `UserDefaults` rather than the
    /// Keychain — same reasoning that keeps `AppPreferences` out of it.
    @Published var autoLockOnSystemSleep: Bool {
        didSet {
            UserDefaults.standard.set(autoLockOnSystemSleep, forKey: Self.autoLockPreferenceKey)
        }
    }

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
    private static let autoLockPreferenceKey = "composure.applock.autoLockOnSystemSleep"

    /// Tokens for the two system notifications that trigger an automatic
    /// lock — held so `deinit` can unregister them. `NSWorkspace`'s own
    /// notification center for sleep, `DistributedNotificationCenter` for
    /// screen lock: the latter isn't a public API surface Apple documents
    /// for this purpose, but `com.apple.screenIsLocked` is the
    /// long-standing, widely-used mechanism apps rely on to notice the
    /// screen saver's password lock specifically — sleep alone doesn't
    /// fire it, and this app cares about both.
    private var systemSleepObserver: NSObjectProtocol?
    private var screenLockObserver: NSObjectProtocol?

    init(
        store: AppLockCredentialStoring = KeychainAppLockCredentialStore(),
        deviceAuthenticator: DeviceAuthenticating = LAContextDeviceAuthenticator()
    ) {
        self.store = store
        self.deviceAuthenticator = deviceAuthenticator
        self.isConfigured = store.isConfigured
        self.autoLockOnSystemSleep = (UserDefaults.standard.object(forKey: Self.autoLockPreferenceKey) as? Bool) ?? true
        observeSystemLockEvents()
    }

    deinit {
        if let systemSleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(systemSleepObserver)
        }
        if let screenLockObserver {
            DistributedNotificationCenter.default().removeObserver(screenLockObserver)
        }
    }

    private func observeSystemLockEvents() {
        systemSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lockIfAutoLockEnabled() }
        }

        screenLockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lockIfAutoLockEnabled() }
        }
    }

    private func lockIfAutoLockEnabled() {
        // Skipped when never configured: there's no passcode to protect
        // yet, so this would just be a no-op re-showing the setup flow
        // rather than anything resembling a real lock.
        guard autoLockOnSystemSleep, isConfigured else { return }
        lock()
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

    /// Whether the unlock screen should offer a Touch ID button alongside
    /// the passcode field. `false` on a Mac with no biometric sensor —
    /// `deviceAuthenticator`'s `.deviceOwnerAuthentication` policy would
    /// still succeed there via the account password, but that's exactly
    /// what the passcode field already offers, so a redundant button
    /// would just be confusing.
    var supportsBiometricUnlock: Bool {
        deviceAuthenticator.supportsBiometrics
    }

    /// Alternate unlock path for the button `supportsBiometricUnlock`
    /// gates. A successful device-owner check is at least as strong a
    /// proof of identity as the passcode, so it clears the same lockout
    /// state a correct passcode would.
    @discardableResult
    func unlockWithDeviceOwnerAuthentication() async -> Bool {
        guard await deviceAuthenticator.authenticateDeviceOwner(reason: "unlock Composure") else {
            errorMessage = "Authentication failed."
            return false
        }

        errorMessage = ""
        failedAttempts = 0
        lockedOutUntil = nil
        isUnlocked = true
        return true
    }

    /// Routine passcode change from Settings, distinct from
    /// `resetPasscode()` — this is for someone who remembers their current
    /// passcode and just wants a new one, so it verifies the current
    /// passcode directly rather than reaching for Touch ID/the account
    /// password. Throws instead of setting `errorMessage`: this runs from
    /// deep inside Settings while already unlocked, and routing its
    /// errors through the same property the lock screen reads would let
    /// the two bleed into each other.
    func changePasscode(current: String, new: String, confirmation: String) throws {
        guard store.verify(current) else {
            throw ChangePasscodeError.incorrectCurrentPasscode
        }

        let trimmedNew = new.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirmation = confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedNew == trimmedConfirmation else {
            throw ChangePasscodeError.mismatch
        }

        do {
            try store.setPasscode(trimmedNew)
        } catch {
            throw ChangePasscodeError.underlying(error)
        }
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
