// token_hud/Support/KeychainHelper.swift
import Foundation
import LocalAuthentication
import Security

enum KeychainHelper {
    static let service = "com.tokenHud.sessionKey"
    static let account = "claudeSessionKey"
    private static let openAIAccount = "openAIAPIKey"
    private static let codexAdminKeyAccount = "codexOpenAIAdminKey"

    // MARK: - Claude session key (existing interface)

    static func save(_ value: String) throws {
        try save(value, account: account)
    }

    static func load() -> String? {
        load(account: account)
    }

    static func load(allowUserInteraction: Bool) -> String? {
        load(account: account, allowUserInteraction: allowUserInteraction)
    }

    static func hasClaudeSessionKey() -> Bool {
        exists(account: account)
    }

    // MARK: - OpenAI API key (legacy convenience)

    static func saveOpenAIKey(_ value: String) throws {
        try save(value, account: openAIAccount)
    }

    static func loadOpenAIKey() -> String? {
        load(account: openAIAccount)
    }

    static func loadOpenAIKey(allowUserInteraction: Bool) -> String? {
        load(account: openAIAccount, allowUserInteraction: allowUserInteraction)
    }

    static func hasLegacyOpenAIKey() -> Bool {
        exists(account: openAIAccount)
    }

    // MARK: - Codex OpenAI Admin/API extras key

    static func saveCodexAdminKey(_ value: String) throws {
        try save(value, account: codexAdminKeyAccount)
    }

    static func loadCodexAdminKey() -> String? {
        load(account: codexAdminKeyAccount)
    }

    static func loadCodexAdminKey(allowUserInteraction: Bool) -> String? {
        load(account: codexAdminKeyAccount, allowUserInteraction: allowUserInteraction)
    }

    static func hasCodexAdminKey() -> Bool {
        exists(account: codexAdminKeyAccount)
    }

    static func deleteCodexAdminKey() throws {
        try delete(account: codexAdminKeyAccount)
    }

    // MARK: - Generic API key (per platform)

    static func saveAPIKey(_ value: String, for platformID: String) throws {
        try save(value, account: "\(platformID)APIKey")
    }

    static func loadAPIKey(for platformID: String) -> String? {
        load(account: "\(platformID)APIKey")
    }

    static func loadAPIKey(for platformID: String, allowUserInteraction: Bool) -> String? {
        load(account: "\(platformID)APIKey", allowUserInteraction: allowUserInteraction)
    }

    static func hasAPIKey(for platformID: String) -> Bool {
        exists(account: "\(platformID)APIKey")
    }

    // MARK: - MiMo console cookie

    static func saveMiMoConsoleCookie(_ value: String) throws {
        try save(value, account: "mimoConsoleCookie")
    }

    static func loadMiMoConsoleCookie() -> String? {
        load(account: "mimoConsoleCookie")
    }

    static func loadMiMoConsoleCookie(allowUserInteraction: Bool) -> String? {
        load(account: "mimoConsoleCookie", allowUserInteraction: allowUserInteraction)
    }

    static func hasMiMoConsoleCookie() -> Bool {
        exists(account: "mimoConsoleCookie")
    }

    static func deleteMiMoConsoleCookie() throws {
        try delete(account: "mimoConsoleCookie")
    }

    // MARK: - Delete

    static func deleteClaudeSessionKey() throws {
        try delete(account: account)
    }

    static func deleteLegacyOpenAIKey() throws {
        try delete(account: openAIAccount)
    }

    static func deleteAPIKey(for platformID: String) throws {
        try delete(account: "\(platformID)APIKey")
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
        load(account: account, allowUserInteraction: true)
    }

    private static func load(account: String, allowUserInteraction: Bool) -> String? {
        var query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne,
        ]
        if !allowUserInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext] = context
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func exists(account: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
            kSecReturnAttributes: true,
            kSecMatchLimit:   kSecMatchLimitOne,
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    private static func delete(account: String) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
