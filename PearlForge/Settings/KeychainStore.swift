import Foundation
import Security

/// The credentials Pearl Forge keeps. Each is its own Keychain item.
enum Credential: String, CaseIterable {
    case elevenLabsKey = "elevenlabs-api-key"
    case anthropicKey = "anthropic-api-key"
    /// Only needed when the Anthropic key is organization-scoped.
    case anthropicWorkspaceID = "anthropic-workspace-id"
}

/// Reads and writes credentials in this iPhone's Keychain. Items stay on this
/// device only (never synced to iCloud or restored onto another phone) and are
/// readable once the phone has been unlocked after a restart.
enum KeychainStore {
    private static let service = "com.solidplisskin.PearlForge"

    static func read(_ credential: Credential) -> String? {
        var query = baseQuery(credential)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func save(_ value: String, for credential: Credential) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(baseQuery(credential) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery(credential)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    static func delete(_ credential: Credential) {
        SecItemDelete(baseQuery(credential) as CFDictionary)
    }

    private static func baseQuery(_ credential: Credential) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.rawValue,
        ]
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
        return "Couldn't save to the Keychain: \(detail)"
    }
}
