import XCTest
@testable import smartspectra_swift_ui

/// `LAContextDeviceAuthenticator` itself isn't covered here — it drives a
/// real Touch ID / password system prompt, which can't be automated. These
/// tests exist to pin down the contract its test doubles promise, since
/// `AppLockCoordinatorTests` relies on that contract holding.
final class DeviceAuthenticatorTests: XCTestCase {

    func test_alwaysSucceeds_reportsSuccess() async {
        let authenticator = AlwaysSucceedsDeviceAuthenticator()
        let result = await authenticator.authenticateDeviceOwner(reason: "test")
        XCTAssertTrue(result)
    }

    func test_alwaysFails_reportsFailure() async {
        let authenticator = AlwaysFailsDeviceAuthenticator()
        let result = await authenticator.authenticateDeviceOwner(reason: "test")
        XCTAssertFalse(result)
    }

    func test_supportsBiometrics_isSettableOnDoubles() {
        var authenticator = AlwaysSucceedsDeviceAuthenticator()
        XCTAssertTrue(authenticator.supportsBiometrics)
        authenticator.supportsBiometrics = false
        XCTAssertFalse(authenticator.supportsBiometrics)
    }
}
