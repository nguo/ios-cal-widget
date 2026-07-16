import Foundation
import Security

/// Stores the long-lived Google refresh token in the Keychain, in a shared access group so
/// both the app and the widget extension can read it. Keyed by account email to support
/// multiple Google accounts.
///
/// The access group must match the `keychain-access-groups` entitlement on both targets.
/// Actual Keychain I/O requires that entitlement, so this is verified on device, not in the
/// off-device smoke check.
public struct KeychainStore {
    private let service = "com.ninbit.calwidget.refreshToken"
    private let accessGroup: String?

    /// - Parameter accessGroup: the fully-qualified shared access group
    ///   (`<AppIdentifierPrefix>com.ninbit.calwidget.tokens`). Pass nil for the default keychain.
    public init(accessGroup: String?) {
        self.accessGroup = accessGroup
    }

    public func saveRefreshToken(_ token: String, accountEmail: String) throws {
        let data = Data(token.utf8)
        var query = baseQuery(accountEmail: accountEmail)

        // Upsert: delete any existing item, then add.
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    public func refreshToken(accountEmail: String) throws -> String? {
        var query = baseQuery(accountEmail: accountEmail)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status)
        }
    }

    public func deleteRefreshToken(accountEmail: String) throws {
        let status = SecItemDelete(baseQuery(accountEmail: accountEmail) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    private func baseQuery(accountEmail: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountEmail
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

public enum KeychainError: Error, Equatable {
    case unhandled(OSStatus)
}
