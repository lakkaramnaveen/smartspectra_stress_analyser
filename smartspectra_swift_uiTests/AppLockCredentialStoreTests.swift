import XCTest
@testable import smartspectra_swift_ui

final class AppLockCredentialStoreTests: XCTestCase {

    // MARK: - InMemoryAppLockCredentialStore (fast, hermetic)

    func test_freshStore_isNotConfigured() {
        let store = InMemoryAppLockCredentialStore()
        XCTAssertFalse(store.isConfigured)
    }

    func test_preconfiguredStore_isConfigured() {
        let store = InMemoryAppLockCredentialStore(preconfiguredPasscode: "1234")
        XCTAssertTrue(store.isConfigured)
    }

    func test_setPasscode_rejectsEmpty() {
        let store = InMemoryAppLockCredentialStore()
        XCTAssertThrowsError(try store.setPasscode(""))
    }

    func test_setPasscode_rejectsWhitespaceOnly() {
        let store = InMemoryAppLockCredentialStore()
        XCTAssertThrowsError(try store.setPasscode("   "))
    }

    func test_setPasscode_rejectsTooShort() {
        let store = InMemoryAppLockCredentialStore()
        let tooShort = String(repeating: "1", count: AppLockPolicy.minimumPasscodeLength - 1)
        XCTAssertThrowsError(try store.setPasscode(tooShort))
    }

    func test_setPasscode_acceptsMinimumLength() throws {
        let store = InMemoryAppLockCredentialStore()
        let minimal = String(repeating: "1", count: AppLockPolicy.minimumPasscodeLength)
        try store.setPasscode(minimal)
        XCTAssertTrue(store.isConfigured)
        XCTAssertTrue(store.verify(minimal))
    }

    func test_verify_succeedsForCorrectPasscode() throws {
        let store = InMemoryAppLockCredentialStore()
        try store.setPasscode("hunter2")
        XCTAssertTrue(store.verify("hunter2"))
    }

    func test_verify_failsForIncorrectPasscode() throws {
        let store = InMemoryAppLockCredentialStore()
        try store.setPasscode("hunter2")
        XCTAssertFalse(store.verify("wrong"))
    }

    func test_verify_isCaseSensitive() throws {
        let store = InMemoryAppLockCredentialStore()
        try store.setPasscode("Hunter2")
        XCTAssertFalse(store.verify("hunter2"))
    }

    func test_clear_removesPasscode() throws {
        let store = InMemoryAppLockCredentialStore()
        try store.setPasscode("hunter2")
        store.clear()
        XCTAssertFalse(store.isConfigured)
        XCTAssertFalse(store.verify("hunter2"))
    }

    func test_setPasscode_trimsWhitespace() throws {
        let store = InMemoryAppLockCredentialStore()
        try store.setPasscode("  hunter2  ")
        XCTAssertTrue(store.verify("hunter2"))
    }

    // MARK: - KeychainAppLockCredentialStore (talks to the real Keychain)
    //
    // Namespaced under a service unique to this run so it can never
    // collide with the app's own stored passcode, and always cleaned up in
    // `tearDown` so a failed assertion doesn't leave a stray Keychain item
    // behind for the next run to trip over.

    private var keychainStore: KeychainAppLockCredentialStore!

    override func setUp() {
        super.setUp()
        keychainStore = KeychainAppLockCredentialStore(service: "com.composure.tests.\(UUID().uuidString)")
    }

    override func tearDown() {
        keychainStore.clear()
        keychainStore = nil
        super.tearDown()
    }

    func test_keychainStore_roundTripsAPasscode() throws {
        XCTAssertFalse(keychainStore.isConfigured)
        try keychainStore.setPasscode("keychain-passcode")
        XCTAssertTrue(keychainStore.isConfigured)
        XCTAssertTrue(keychainStore.verify("keychain-passcode"))
        XCTAssertFalse(keychainStore.verify("wrong-passcode"))
    }

    func test_keychainStore_overwritesExistingPasscode() throws {
        try keychainStore.setPasscode("first")
        try keychainStore.setPasscode("second")
        XCTAssertFalse(keychainStore.verify("first"))
        XCTAssertTrue(keychainStore.verify("second"))
    }

    func test_keychainStore_clear_removesPasscode() throws {
        try keychainStore.setPasscode("keychain-passcode")
        keychainStore.clear()
        XCTAssertFalse(keychainStore.isConfigured)
    }
}
