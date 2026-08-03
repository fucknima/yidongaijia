import Foundation
import Security

struct SavedAijiaLogin {
    let phone: String
    let password: String
    let cameraSelector: String
}

protocol CredentialStoring: AnyObject {
    func load() -> SavedAijiaLogin?
    func isAutoConnectEnabled() -> Bool
    func setAutoConnectEnabled(_ enabled: Bool)
    func save(phone: String, password: String, cameraSelector: String) -> Bool
    func clear()
}

protocol PasswordStoring: AnyObject {
    func read() -> String?
    func write(_ password: String) -> Bool
    func clear()
}

private final class KeychainPasswordStore: PasswordStoring {
    private let service: String
    private let account: String

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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

    func write(_ password: String) -> Bool {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        switch SecItemUpdate(query as CFDictionary, attributes as CFDictionary) {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            var addQuery = query
            attributes.forEach { addQuery[$0.key] = $0.value }
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        default:
            return false
        }
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class CredentialStore: CredentialStoring {
    static let shared = CredentialStore()

    private static let service = "com.example.AijiaDirect.login"
    private static let passwordAccount = "mobile-aijia-password"

    private let defaults: UserDefaults
    private let passwordStore: PasswordStoring
    private let phoneKey = "savedLogin.phone"
    private let cameraSelectorKey = "savedLogin.cameraSelector"
    private let autoConnectKey = "savedLogin.autoConnectEnabled"

    private init() {
        defaults = .standard
        passwordStore = KeychainPasswordStore(
            service: Self.service,
            account: Self.passwordAccount
        )
    }

    init(defaults: UserDefaults, passwordStore: PasswordStoring) {
        self.defaults = defaults
        self.passwordStore = passwordStore
    }

    func load() -> SavedAijiaLogin? {
        guard let phone = defaults.string(forKey: phoneKey), !phone.isEmpty,
              let password = passwordStore.read(), !password.isEmpty else {
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
        guard passwordStore.write(password) else { return false }

        defaults.set(phone, forKey: phoneKey)
        defaults.set(cameraSelector, forKey: cameraSelectorKey)
        return true
    }

    func clear() {
        defaults.removeObject(forKey: phoneKey)
        defaults.removeObject(forKey: cameraSelectorKey)
        defaults.removeObject(forKey: autoConnectKey)

        passwordStore.clear()
    }
}
