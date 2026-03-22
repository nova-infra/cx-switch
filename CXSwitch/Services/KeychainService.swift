import Foundation
import Security

/// Deprecated: kept only for one-time migration of legacy registry/keychain data into SQLite.
protocol KeychainStoring {
    func saveAuthBlob(_ blob: AuthBlob, accountId: String) throws
    func loadAuthBlob(accountId: String) throws -> AuthBlob?
    func deleteAuthBlob(accountId: String) throws
}

enum KeychainServiceError: Error {
    case encodingFailed
    case decodingFailed
    case unexpectedStatus(OSStatus)
}

final class KeychainService: KeychainStoring {
    private let service: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        service: String = "com.novainfra.cx-switch.account",
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.service = service
        self.encoder = encoder
        self.decoder = decoder
    }

    func saveAuthBlob(_ blob: AuthBlob, accountId: String) throws {
        let data = try encodeBlob(blob)
        try upsert(data: data, accountId: accountId)
    }

    func loadAuthBlob(accountId: String) throws -> AuthBlob? {
        guard let data = try read(accountId: accountId) else {
            return nil
        }
        return try decodeBlob(from: data)
    }

    func deleteAuthBlob(accountId: String) throws {
        let query = baseQuery(accountId: accountId)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }

    private func baseQuery(accountId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func encodeBlob(_ blob: AuthBlob) throws -> Data {
        let jsonData = try encoder.encode(blob)
        return jsonData.base64EncodedData()
    }

    private func decodeBlob(from data: Data) throws -> AuthBlob {
        guard let jsonData = Data(base64Encoded: data) else {
            throw KeychainServiceError.decodingFailed
        }
        return try decoder.decode(AuthBlob.self, from: jsonData)
    }

    private func read(accountId: String) throws -> Data? {
        var query = baseQuery(accountId: accountId)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        if status != errSecSuccess {
            throw KeychainServiceError.unexpectedStatus(status)
        }
        return item as? Data
    }

    private func upsert(data: Data, accountId: String) throws {
        let query = baseQuery(accountId: accountId)
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }
        if status != errSecItemNotFound {
            throw KeychainServiceError.unexpectedStatus(status)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw KeychainServiceError.unexpectedStatus(addStatus)
        }
    }
}
