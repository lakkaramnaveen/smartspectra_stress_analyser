import Foundation
import Security
import CryptoKit

/// Errors surfaced by `AppLockCredentialStoring`. Kept small and specific
/// so `AppLockView` can show an actionable message instead of a generic
/// "something went wrong" — same convention as `CredentialError`.
enum AppLockError: LocalizedError {
    case emptyPasscode
    case tooShort
    case keychainWrite(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyPasscode:
            return "Passcode cannot be empty."
        case .tooShort:
            return "Passcode must be at least 4 characters."
        case .keychainWrite(let status):
            return "Failed to securely store passcode (status \(status))."
        }
    }
}

/// Persists the app-lock passcode as a salted hash in the macOS Keychain —
/// never the passcode itself. Deliberately app-wide rather than
/// profile-scoped: the lock screen is shown *before* a profile is chosen
/// (see `AppLockGateView`), so it can't depend on one existing yet — the
/// same reasoning that keeps `KeychainCredentialStore`'s SmartSpectra API
/// key un-scoped.
protocol AppLockCredentialStoring {
    /// Whether a passcode has ever been set. Drives whether `AppLockView`
    /// shows the "create a passcode" flow or the "enter your passcode" one.
    var isConfigured: Bool { get }
    func setPasscode(_ passcode: String) throws
    func verify(_ passcode: String) -> Bool
    /// Forgets the passcode without touching any profile's data — the
    /// "Forgot passcode?" escape hatch. Leaves `isConfigured` false so the
    /// next launch (or gate re-check) falls back to the setup flow.
    func clear()
}

final class KeychainAppLockCredentialStore: AppLockCredentialStoring {
    private let service: String
    private let account = "smartspectra-app-lock"

    /// Salted digest is stored as one blob: a fixed-length random salt
    /// followed by its SHA-256 digest. Storing the salt alongside the hash
    /// (rather than deriving it from something fixed) means two people
    /// setting the same passcode never produce the same stored bytes.
    private static let saltLength = 16

    init(service: String = Bundle.main.bundleIdentifier ?? "com.composure.app") {
        self.service = service
    }

    var isConfigured: Bool {
        loadStoredPayload() != nil
    }

    func setPasscode(_ passcode: String) throws {
        let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppLockError.emptyPasscode }
        guard trimmed.count >= 4 else { throw AppLockError.tooShort }

        let salt = Self.randomSalt()
        let payload = salt + Self.digest(passcode: trimmed, salt: salt)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributesToUpdate: [String: Any] = [kSecValueData as String: payload]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = payload
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AppLockError.keychainWrite(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw AppLockError.keychainWrite(updateStatus)
        }
    }

    func verify(_ passcode: String) -> Bool {
        guard let payload = loadStoredPayload(), payload.count > Self.saltLength else { return false }

        let salt = payload.prefix(Self.saltLength)
        let expectedDigest = payload.suffix(from: payload.index(payload.startIndex, offsetBy: Self.saltLength))
        let candidateDigest = Self.digest(passcode: passcode, salt: Data(salt))

        // Constant-time compare — a passcode check is exactly the kind of
        // comparison where an early-exit `==` on raw bytes can leak how
        // many leading bytes matched via timing.
        return candidateDigest.withUnsafeBytes { candidateBuffer in
            Data(expectedDigest).withUnsafeBytes { expectedBuffer in
                guard candidateBuffer.count == expectedBuffer.count else { return false }
                var difference: UInt8 = 0
                for i in 0..<candidateBuffer.count {
                    difference |= candidateBuffer[i] ^ expectedBuffer[i]
                }
                return difference == 0
            }
        }
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func loadStoredPayload() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltLength, &bytes)
        return Data(bytes)
    }

    private static func digest(passcode: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(passcode.utf8))
        return Data(SHA256.hash(data: input))
    }
}

// MARK: - In-Memory (previews, tests)

final class InMemoryAppLockCredentialStore: AppLockCredentialStoring {
    private var storedPasscode: String?

    init(preconfiguredPasscode: String? = nil) {
        storedPasscode = preconfiguredPasscode
    }

    var isConfigured: Bool { storedPasscode != nil }

    func setPasscode(_ passcode: String) throws {
        let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppLockError.emptyPasscode }
        guard trimmed.count >= 4 else { throw AppLockError.tooShort }
        storedPasscode = trimmed
    }

    func verify(_ passcode: String) -> Bool {
        storedPasscode != nil && storedPasscode == passcode
    }

    func clear() {
        storedPasscode = nil
    }
}
