// token_hud/Support/KeychainHelper.swift
import Foundation
import Security

enum KeychainHelper {
    static let service = "com.tokenHud.sessionKey"
    static let account = "claudeSessionKey"
    private static let openAIAccount = "openAIAPIKey"

    // MARK: - Claude session key (existing interface)

    static func save(_ value: String) throws {
        try save(value, account: account)
    }

    static func load() -> String? {
        load(account: account)
    }

    // MARK: - OpenAI API key (legacy convenience)

    static func saveOpenAIKey(_ value: String) throws {
        try save(value, account: openAIAccount)
    }

    static func loadOpenAIKey() -> String? {
        load(account: openAIAccount)
    }

    // MARK: - Generic API key (per platform)

    static func saveAPIKey(_ value: String, for platformID: String) throws {
        try save(value, account: "\(platformID)APIKey")
    }

    static func loadAPIKey(for platformID: String) -> String? {
        load(account: "\(platformID)APIKey")
    }

    // MARK: - MiMo console cookie

    static func saveMiMoConsoleCookie(_ value: String) throws {
        try save(value, account: "mimoConsoleCookie")
    }

    static func loadMiMoConsoleCookie() -> String? {
        load(account: "mimoConsoleCookie")
    }

    // MARK: - Generic

    private static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData:   data,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static func load(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
