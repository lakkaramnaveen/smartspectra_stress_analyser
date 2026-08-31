import Foundation
import Security

/// Errors surfaced by `CredentialStore`. Kept small and specific so callers
/// can show actionable messages instead of a generic "something went wrong."
enum CredentialError: LocalizedError {
    case emptyKey
    case keychainWrite(OSStatus)
    case keychainRead(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "API key cannot be empty."
        case .keychainWrite(let status):
            return "Failed to securely store API key (status \(status))."
        case .keychainRead(let status):
            return "Failed to read stored API key (status \(status))."
        }
    }
}

/// Persists the SmartSpectra API key in the macOS Keychain.
///
/// Why Keychain instead of `UserDefaults` or an environment variable:
/// - `UserDefaults` is plaintext on disk and trivially readable by anything
///   with file-system access to the user's Library folder.
/// - Environment variables only exist for the lifetime of the process and
///   aren't available to a packaged, double-clicked .app unless explicitly
///   exported — which is why "works in Xcode, 401s in the shipped build" is
///   such a common symptom.
/// - Keychain is the platform-sanctioned place for credentials and is
///   encrypted at rest.
protocol CredentialStoring {
    func save(apiKey: String) throws
    func loadAPIKey() -> String?
    func clear()
}

final class KeychainCredentialStore: CredentialStoring {
    private let service: String
    private let account = "smartspectra-api-key"

    init(service: String = Bundle.main.bundleIdentifier ?? "com.composure.app") {
        self.service = service
    }

    func save(apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CredentialError.emptyKey }

        let data = Data(trimmed.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Try update first; if no existing item, add a new one.
        let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            // ThisDeviceOnly + WhenUnlocked rather than the more common
            // AfterFirstUnlock: the app already gates all access behind
            // Touch ID/passcode (AppLockService), so the key is never
            // needed while the device is locked or before first unlock —
            // no reason to also let it sync via iCloud Keychain or stay
            // readable on a machine that's merely been unlocked since boot.
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialError.keychainWrite(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CredentialError.keychainWrite(updateStatus)
        }
    }

    func loadAPIKey() -> String? {
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
        return String(data: data, encoding: .utf8)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
