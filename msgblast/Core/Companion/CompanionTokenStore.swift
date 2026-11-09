import Foundation
import LocalAuthentication
import Security

// iMessage companion (fork-only). The HomeChat uplink token, one per Mac.
public protocol CompanionTokenStoring: Sendable {
    func read() -> String?
    /// nil deletes. Returns false when the Keychain is unavailable.
    @discardableResult func write(_ token: String?) -> Bool
}

/// A generic password in the login keychain. The fork is self-signed and has no keychain-access-groups
/// entitlement, so the data-protection keychain (which GrokBot uses) isn't available to it; the login item's
/// access is tied to the app's designated requirement, which stays the same across the fork's rebuilds.
public struct KeychainTokenStore: CompanionTokenStoring {
    private let service: String
    private static let account = "uplink-token"
    private static let unavailable: Set<OSStatus> = [errSecMissingEntitlement, errSecInteractionNotAllowed,
                                                     errSecAuthFailed, errSecNotAvailable]

    public init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "unknown") {
        service = "\(bundleIdentifier).companion-uplink"
    }

    private var query: [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: Self.account,
                kSecUseAuthenticationContext as String: context,
                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
    }

    public func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    @discardableResult
    public func write(_ token: String?) -> Bool {
        guard let token, !token.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        if Self.unavailable.contains(status) { return false }
        return status == errSecSuccess
    }
}
