import Foundation
import Security

@MainActor
public protocol CredentialVault {
    func read() throws -> String?
    func write(_ token: String) throws
    func remove() throws
}

@MainActor
public struct KeychainVault: CredentialVault {
    let scope: String
    public init(endpoint: ServerEndpoint) { scope = endpoint.credentialScope }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "AI Fitness.native-session",
         kSecAttrAccount as String: scope]
    }

    public func read() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty
        else { throw VaultError.unavailable }
        return token
    }

    public func write(_ token: String) throws {
        let values: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(values) { _, value in value } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw VaultError.unavailable }
    }

    public func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.unavailable }
    }
}

public enum VaultError: Error {
    case unavailable
}
