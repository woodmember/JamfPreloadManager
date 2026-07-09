import Foundation
import Security

struct KeychainStore: Sendable {
    let service: String

    func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw JamfAppError.keychain("Keychain returned an unexpected item type.")
            }
            return String(data: data, encoding: .utf8)?.trimmed.nilIfBlank
        case errSecItemNotFound:
            return nil
        default:
            throw JamfAppError.keychain(keychainMessage(status, context: "Unable to read saved credentials."))
        }
    }

    func write(account: String, value: String) throws {
        let data = Data(value.utf8)

        let query = baseQuery(account: account)
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw JamfAppError.keychain(keychainMessage(addStatus, context: "Unable to save credentials."))
            }
        default:
            throw JamfAppError.keychain(keychainMessage(updateStatus, context: "Unable to save credentials."))
        }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw JamfAppError.keychain(keychainMessage(status, context: "Unable to remove saved credentials."))
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func keychainMessage(_ status: OSStatus, context: String) -> String {
        let details = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
        return "\(context)\n\(details)"
    }
}
