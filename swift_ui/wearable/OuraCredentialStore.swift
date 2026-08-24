import Foundation
import Security

protocol OuraCredentialStoring {
    func load() -> OuraConnectionState?
    func save(_ state: OuraConnectionState) throws
    func clear()
}

/// Keychain-backed, namespaced per profile — the same idea as
/// namespacing file storage by `profile.storageRoot`, applied to
/// Keychain instead. An Oura ring is worn by one specific person, unlike
/// the SmartSpectra API key (a household device license shared across
/// every profile), so this deliberately does *not* follow
/// `KeychainCredentialStore`'s single-shared-entry pattern.
final class KeychainOuraCredentialStore: OuraCredentialStoring {
    private let service: String
    private let account: String

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(profileID: UUID, service: String = Bundle.main.bundleIdentifier ?? "com.composure.app") {
        self.service = service
        self.account = "oura-connection-\(profileID.uuidString)"
    }

    func load() -> OuraConnectionState? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? decoder.decode(OuraConnectionState.self, from: data)
    }

    func save(_ state: OuraConnectionState) throws {
        let data = try encoder.encode(state)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
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
}

final class InMemoryOuraCredentialStore: OuraCredentialStoring {
    private var state: OuraConnectionState?
    init(state: OuraConnectionState? = nil) { self.state = state }
    func load() -> OuraConnectionState? { state }
    func save(_ state: OuraConnectionState) throws { self.state = state }
    func clear() { state = nil }
}
