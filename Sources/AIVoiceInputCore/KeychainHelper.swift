import Foundation
import Security

/// SecItem 薄封装。用 legacy 文件钥匙串(**不设** `kSecUseDataProtectionKeychain`——
/// ad-hoc 签名下该 flag 令 SecItemAdd 直接 -34018,实测 FINDINGS §2.5/spike 6)。
///
/// ACL 现实(falsification ⑤,grill #28):同一 build 内 存/读/删 全 OSStatus=0;
/// **不同 cdhash 的 build 读同一项会触发系统 ACL 授权弹窗**(ad-hoc 每次重建 cdhash 变)。
/// dev 期每重建 .app 一次 Allow 是可接受摩擦;稳定 Developer ID 签名后消失(与 TCC 同根,§6 三锁一购)。
public enum KeychainHelper {
    public enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                "Keychain 错误(OSStatus=\(status))"
            }
        }
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// 幂等 upsert:先删再加(SecItemUpdate 在跨属性变更时易 -25299,删+加最稳)
    public static func save(_ value: String, service: String, account: String) throws {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        var query = baseQuery(service: service, account: account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public static func read(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func delete(service: String, account: String) -> Bool {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
