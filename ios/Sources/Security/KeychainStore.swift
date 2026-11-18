import Foundation
import Security

struct S3Credentials: Codable, Equatable, Sendable {
    let accessKey: String
    let secretKey: String
}

enum KeychainError: LocalizedError, Sendable {
    case status(OSStatus)
    case encode

    var errorDescription: String? {
        switch self {
        case .status(let status): return "钥匙串操作失败（\(status)）"
        case .encode: return "钥匙串数据无法编码"
        }
    }
}

struct KeychainStore: Sendable {
    static let defaultService = "cn.carljoy.tinymusic.s3"
    static let account = "default"

    let service: String

    init(service: String = Self.defaultService) {
        self.service = service
    }

    func save(_ credentials: S3Credentials, synchronizable: Bool) throws {
        delete()
        guard let data = try? JSONEncoder().encode(credentials) else {
            throw KeychainError.encode
        }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: synchronizable
                ? kSecAttrAccessibleAfterFirstUnlock
                : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = true
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess { return }

        // TestFlight/无 iCloud entitlement 的构建：synchronizable 项可能被拒。
        // 退回本机 keychain，保证 S3 凭据仍能保存和播放。
        if synchronizable {
            var local = query
            local.removeValue(forKey: kSecAttrSynchronizable as String)
            local[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let localStatus = SecItemAdd(local as CFDictionary, nil)
            if localStatus == errSecSuccess { return }
            throw KeychainError.status(localStatus)
        }
        throw KeychainError.status(status)
    }

    func load() -> S3Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return try? JSONDecoder().decode(S3Credentials.self, from: data)
        }

        // 没有 iCloud entitlement 时，synchronizable=Any 可能返回缺失权限；
        // 再查一次仅本机的 keychain。
        var localQuery = query
        localQuery.removeValue(forKey: kSecAttrSynchronizable as String)
        var localItem: CFTypeRef?
        guard SecItemCopyMatching(localQuery as CFDictionary, &localItem) == errSecSuccess,
              let localData = localItem as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(S3Credentials.self, from: localData)
    }

    func isSynchronizable() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [String: Any] else {
            return false
        }
        return attributes[kSecAttrSynchronizable as String] as? Bool ?? false
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
