import Foundation
import Security

struct CredentialStore {
    struct Credential: Codable, Sendable {
        let token: String
        let certificateSHA256: String?
    }
    private let service = "app.khole.mobile.connections"

    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    func read(_ id: UUID) throws -> Credential {
        var request = query(id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { throw GatewayError.missingCredential }
        return try JSONDecoder().decode(Credential.self, from: data)
    }

    func save(_ credential: Credential, for id: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        let status = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(id)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw GatewayError.refused("Could not save this connection in Keychain.")
            }
        } else if status != errSecSuccess {
            throw GatewayError.refused("Could not update this connection in Keychain.")
        }
    }

    func remove(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GatewayError.refused("Could not remove this connection from Keychain.")
        }
    }
}
