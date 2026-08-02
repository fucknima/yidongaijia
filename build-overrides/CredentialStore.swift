import Foundation
import Security

struct SavedAijiaLogin {
    let phone: String
    let password: String
    let cameraSelector: String
}

final class CredentialStore {
    static let shared = CredentialStore()

    private let service = "com.example.AijiaDirect.login"
    private let passwordAccount = "mobile-aijia-password"
    private let defaults = UserDefaults.standard
    private let phoneKey = "savedLogin.phone"
    private let cameraSelectorKey = "savedLogin.cameraSelector"
    private let autoConnectKey = "savedLogin.autoConnectEnabled"

    private init() {}

    func load() -> SavedAijiaLogin? {
        guard let phone = defaults.string(forKey: phoneKey), !phone.isEmpty,
              let password = readPassword(), !password.isEmpty else {
            return nil
        }
        return SavedAijiaLogin(
            phone: phone,
            password: password,
            cameraSelector: defaults.string(forKey: cameraSelectorKey) ?? ""
        )
    }

    func isAutoConnectEnabled() -> Bool {
        // Existing installs predate this flag and should keep their current
        // auto-login behavior until the user explicitly logs out.
        guard defaults.object(forKey: autoConnectKey) != nil else { return true }
        return defaults.bool(forKey: autoConnectKey)
    }

    func setAutoConnectEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: autoConnectKey)
    }

    @discardableResult
    func save(phone: String, password: String, cameraSelector: String) -> Bool {
        guard !phone.isEmpty, !password.isEmpty else { return false }

        defaults.set(phone, forKey: phoneKey)
        defaults.set(cameraSelector, forKey: cameraSelectorKey)
        return writePassword(password)
    }

    func clear() {
        defaults.removeObject(forKey: phoneKey)
        defaults.removeObject(forKey: cameraSelectorKey)
        defaults.removeObject(forKey: autoConnectKey)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func readPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func writePassword(_ password: String) -> Bool {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }
}

