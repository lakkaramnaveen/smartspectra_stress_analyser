import XCTest
@testable import smartspectra_swift_ui

/// `AppLockCoordinator` reads and writes `UserDefaults.standard` directly
/// (auto-lock preference, idle timeout, and lockout state aren't injected)
/// rather than through an abstraction — a known testability gap, not
/// something these tests pretend around. Every key it touches is cleared
/// in both `setUp` and `tearDown` so a prior crashed run, or a failed
/// assertion mid-test, can't leak state into the next test.
@MainActor
final class AppLockCoordinatorTests: XCTestCase {

    private static let persistedKeys = [
        "composure.applock.autoLockOnSystemSleep",
        "composure.applock.idleLockTimeout",
        "composure.applock.failedAttempts",
        "composure.applock.lockedOutUntil"
    ]

    override func setUp() {
        super.setUp()
        clearPersistedState()
    }

    override func tearDown() {
        clearPersistedState()
        super.tearDown()
    }

    private func clearPersistedState() {
        let defaults = UserDefaults.standard
        for key in Self.persistedKeys {
            defaults.removeObject(forKey: key)
        }
    }

    private func makeCoordinator(
        store: AppLockCredentialStoring = InMemoryAppLockCredentialStore(),
        deviceAuthenticator: DeviceAuthenticating = AlwaysSucceedsDeviceAuthenticator()
    ) -> AppLockCoordinator {
        AppLockCoordinator(store: store, deviceAuthenticator: deviceAuthenticator)
    }

    // MARK: - Setup

    func test_freshCoordinator_isNotConfiguredOrUnlocked() {
        let coordinator = makeCoordinator()
        XCTAssertFalse(coordinator.isConfigured)
        XCTAssertFalse(coordinator.isUnlocked)
    }

    func test_setUp_withMatchingPasscodes_configuresAndUnlocks() {
        let coordinator = makeCoordinator()
        let succeeded = coordinator.setUp(passcode: "1234", confirmation: "1234")
        XCTAssertTrue(succeeded)
        XCTAssertTrue(coordinator.isConfigured)
        XCTAssertTrue(coordinator.isUnlocked)
        XCTAssertEqual(coordinator.errorMessage, "")
    }

    func test_setUp_withMismatchedPasscodes_fails() {
        let coordinator = makeCoordinator()
        let succeeded = coordinator.setUp(passcode: "1234", confirmation: "5678")
        XCTAssertFalse(succeeded)
        XCTAssertFalse(coordinator.isConfigured)
        XCTAssertFalse(coordinator.errorMessage.isEmpty)
    }

    /// Regression coverage: `setUp` used to compare the raw fields, so a
    /// trailing space in only one of them reported a false mismatch.
    func test_setUp_trimsBeforeComparing() {
        let coordinator = makeCoordinator()
        let succeeded = coordinator.setUp(passcode: "1234", confirmation: "1234 ")
        XCTAssertTrue(succeeded)
    }

    func test_setUp_tooShort_isRejected() {
        let coordinator = makeCoordinator()
        let tooShort = String(repeating: "1", count: AppLockPolicy.minimumPasscodeLength - 1)
        let succeeded = coordinator.setUp(passcode: tooShort, confirmation: tooShort)
        XCTAssertFalse(succeeded)
        XCTAssertFalse(coordinator.isConfigured)
    }

    // MARK: - Unlock

    func test_unlock_withCorrectPasscode_succeeds() {
        let coordinator = makeCoordinator(store: InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234"))
        XCTAssertTrue(coordinator.unlock(passcode: "1234"))
        XCTAssertTrue(coordinator.isUnlocked)
    }

    func test_unlock_withIncorrectPasscode_fails() {
        let coordinator = makeCoordinator(store: InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234"))
        XCTAssertFalse(coordinator.unlock(passcode: "wrong"))
        XCTAssertFalse(coordinator.isUnlocked)
        XCTAssertEqual(coordinator.errorMessage, "Incorrect passcode.")
    }

    /// Regression coverage for the brute-force fix: five wrong guesses
    /// engage a lockout that refuses even a subsequently-correct passcode.
    func test_unlock_locksOutAfterMaxFailedAttempts() {
        let coordinator = makeCoordinator(store: InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234"))
        for _ in 0..<4 {
            XCTAssertFalse(coordinator.unlock(passcode: "wrong"))
        }
        // The 5th wrong guess crosses the threshold and engages the lockout.
        XCTAssertFalse(coordinator.unlock(passcode: "wrong"))
        XCTAssertTrue(coordinator.errorMessage.contains("Too many attempts"))

        // A correct guess is refused too while locked out — the check
        // never reaches `store.verify` until the window elapses.
        XCTAssertFalse(coordinator.unlock(passcode: "1234"))
        XCTAssertFalse(coordinator.isUnlocked)
    }

    func test_successfulUnlock_resetsFailedAttemptCount() {
        let coordinator = makeCoordinator(store: InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234"))
        XCTAssertFalse(coordinator.unlock(passcode: "wrong"))
        XCTAssertFalse(coordinator.unlock(passcode: "wrong"))
        XCTAssertTrue(coordinator.unlock(passcode: "1234"))
        XCTAssertEqual(coordinator.errorMessage, "")
    }

    // MARK: - Lock

    func test_lock_setsIsUnlockedFalse() {
        let coordinator = makeCoordinator(store: InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234"))
        XCTAssertTrue(coordinator.unlock(passcode: "1234"))
        coordinator.lock()
        XCTAssertFalse(coordinator.isUnlocked)
    }

    // MARK: - Device-owner unlock (Touch ID / account password)

    func test_unlockWithDeviceOwnerAuthentication_succeedsWhenDeviceAuthSucceeds() async {
        let coordinator = makeCoordinator(
            store: InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234"),
            deviceAuthenticator: AlwaysSucceedsDeviceAuthenticator()
        )
        let succeeded = await coordinator.unlockWithDeviceOwnerAuthentication()
        XCTAssertTrue(succeeded)
        XCTAssertTrue(coordinator.isUnlocked)
    }

    func test_unlockWithDeviceOwnerAuthentication_failsWhenDeviceAuthFails() async {
        let coordinator = makeCoordinator(
            store: InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234"),
            deviceAuthenticator: AlwaysFailsDeviceAuthenticator()
        )
        let succeeded = await coordinator.unlockWithDeviceOwnerAuthentication()
        XCTAssertFalse(succeeded)
        XCTAssertFalse(coordinator.isUnlocked)
    }

    // MARK: - Reset ("Forgot passcode?")

    /// Regression coverage for the fix that closed the reset-as-bypass gap:
    /// a failed device-owner check must leave the passcode untouched.
    func test_resetPasscode_requiresDeviceAuthSuccess() async {
        let coordinator = makeCoordinator(
            store: InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234"),
            deviceAuthenticator: AlwaysFailsDeviceAuthenticator()
        )
        let didReset = await coordinator.resetPasscode()
        XCTAssertFalse(didReset)
        XCTAssertTrue(coordinator.isConfigured)
    }

    func test_resetPasscode_clearsConfigurationOnSuccess() async {
        let coordinator = makeCoordinator(
            store: InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234"),
            deviceAuthenticator: AlwaysSucceedsDeviceAuthenticator()
        )
        let didReset = await coordinator.resetPasscode()
        XCTAssertTrue(didReset)
        XCTAssertFalse(coordinator.isConfigured)
        XCTAssertFalse(coordinator.isUnlocked)
    }

    // MARK: - Change passcode

    func test_changePasscode_withCorrectCurrent_succeeds() throws {
        let store = InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234")
        let coordinator = makeCoordinator(store: store)
        try coordinator.changePasscode(current: "1234", new: "5678", confirmation: "5678")
        XCTAssertTrue(store.verify("5678"))
        XCTAssertFalse(store.verify("1234"))
    }

    func test_changePasscode_withIncorrectCurrent_throwsWithoutChangingAnything() {
        let store = InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234")
        let coordinator = makeCoordinator(store: store)
        XCTAssertThrowsError(try coordinator.changePasscode(current: "wrong", new: "5678", confirmation: "5678")) { error in
            guard case ChangePasscodeError.incorrectCurrentPasscode = error else {
                return XCTFail("Expected .incorrectCurrentPasscode, got \(error)")
            }
        }
        XCTAssertTrue(store.verify("1234"))
    }

    func test_changePasscode_withMismatchedNewPasscodes_throws() {
        let coordinator = makeCoordinator(store: InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234"))
        XCTAssertThrowsError(try coordinator.changePasscode(current: "1234", new: "5678", confirmation: "0000")) { error in
            guard case ChangePasscodeError.mismatch = error else {
                return XCTFail("Expected .mismatch, got \(error)")
            }
        }
    }

    // MARK: - Biometric unlock availability

    func test_supportsBiometricUnlock_reflectsDeviceAuthenticatorAtInit() {
        var authenticator = AlwaysSucceedsDeviceAuthenticator()
        authenticator.supportsBiometrics = false
        let coordinator = makeCoordinator(deviceAuthenticator: authenticator)
        XCTAssertFalse(coordinator.supportsBiometricUnlock)
    }

    // MARK: - Preferences

    func test_autoLockOnSystemSleep_defaultsToTrue() {
        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator.autoLockOnSystemSleep)
    }

    func test_idleLockTimeout_defaultsToNever() {
        let coordinator = makeCoordinator()
        XCTAssertEqual(coordinator.idleLockTimeout, .never)
    }

    func test_idleLockTimeout_persistsAcrossInstances() {
        let first = makeCoordinator()
        first.idleLockTimeout = .fiveMinutes
        let second = makeCoordinator()
        XCTAssertEqual(second.idleLockTimeout, .fiveMinutes)
    }
}
