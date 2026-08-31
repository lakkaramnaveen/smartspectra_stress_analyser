import Foundation
import LocalAuthentication

/// Errors surfaced by `AppLocking`, kept small and specific like
/// `CredentialError` so the lock screen can show an actionable message
/// instead of a generic "authentication failed."
enum AppLockError: LocalizedError {
    case noAuthenticationConfigured
    case canceled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noAuthenticationConfigured:
            return "This Mac has no login password set, so SmartSpectra can't verify who you are. Set a password in System Settings > Touch ID & Password, then relaunch."
        case .canceled:
            return "Authentication was canceled."
        case .failed(let message):
            return message
        }
    }
}

protocol AppLocking: AnyObject {
    func authenticate() async -> Result<Void, AppLockError>
}

/// Gates the app behind the Mac's own device-owner authentication —
/// Touch ID with the account password as fallback — via `LocalAuthentication`.
///
/// Why `.deviceOwnerAuthentication` and not `.deviceOwnerAuthenticationWithBiometrics`:
/// the biometrics-only policy has no passcode fallback, so on a Mac without
/// Touch ID hardware (or with it temporarily unavailable, e.g. right after
/// a reboot before the first password entry) it would permanently lock
/// legitimate users out. `.deviceOwnerAuthentication` tries Touch ID first
/// when available and transparently falls back to the account password,
/// which matches "Touch ID with passcode fallback."
///
/// This intentionally piggybacks on the Mac's own account security rather
/// than inventing an app-specific PIN: a separate app passcode would be one
/// more secret for the user to create and remember, and would be weaker
/// than whatever authentication already guards the machine.
final class AppLockService: AppLocking {
    private let reason = "unlock SmartSpectra to view the camera feed and vitals"

    func authenticate() async -> Result<Void, AppLockError> {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"

        var evalError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evalError) else {
            return .failure(.noAuthenticationConfigured)
        }

        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return .success(())
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel:
                return .failure(.canceled)
            default:
                return .failure(.failed(laError.localizedDescription))
            }
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }
}
