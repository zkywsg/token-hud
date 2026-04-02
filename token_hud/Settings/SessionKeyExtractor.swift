// token_hud/Settings/SessionKeyExtractor.swift
// Extracts claude.ai sessionKey cookie from common browsers on macOS.
// Reference: CodexBar by steipete (https://github.com/steipete/CodexBar)
import Foundation
import SQLite3

enum BrowserType: String, CaseIterable, Identifiable {
    case safari  = "Safari"
    case chrome  = "Chrome"
    case arc     = "Arc"
    case firefox = "Firefox"
    var id: String { rawValue }
}

actor SessionKeyExtractor {

    // MARK: - Public

    func extractFromBrowser(_ browser: BrowserType) async throws -> (BrowserType, String)? {
        switch browser {
        case .safari:  return try extractSafari().map  { (.safari,  $0) }
        case .chrome:  return try extractChromium(appPath: "Google/Chrome").map { (.chrome, $0) }
        case .arc:     return try extractChromium(appPath: "Arc/User Data").map  { (.arc,    $0) }
        case .firefox: return try extractFirefox().map { (.firefox, $0) }
        }
    }

    func storeInKeychain(sessionKey: String) throws {
        try KeychainHelper.save(sessionKey)
    }

    func loadFromKeychain() -> String? {
        KeychainHelper.load()
    }

    func writeConfigFile(sessionKey: String) throws {
        let configDir = ("~/.token-hud" as NSString).expandingTildeInPath
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        let configPath = "\(configDir)/config.json"

        var config: [String: Any] = [:]
        if let existing = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let json = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] {
            config = json
        }
        var services  = config["services"]  as? [String: Any] ?? [:]
        var claudePro = services["claudePro"] as? [String: Any] ?? [:]
        claudePro["sessionKey"] = sessionKey
        services["claudePro"]   = claudePro
        config["services"]      = services

        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
    }

    // MARK: - Safari

    private func extractSafari() throws -> String? {
        let path = ("~/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies" as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try findSessionKeyInBinaryFile(path: path)
    }

    // MARK: - Chromium

    private func extractChromium(appPath: String) throws -> String? {
        let cookiePath = ("~/Library/Application Support/\(appPath)/Default/Cookies" as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: cookiePath) else { return nil }

        let tmp = NSTemporaryDirectory() + UUID().uuidString + ".db"
        try FileManager.default.copyItem(atPath: cookiePath, toPath: tmp)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let rows = try sqliteQuery(
            db: tmp,
            sql: "SELECT encrypted_value FROM cookies WHERE host_key LIKE '%claude.ai%' AND name='sessionKey' LIMIT 1"
        )
        guard let encrypted = rows.first else { return nil }
        return try decryptChromiumCookie(encrypted)
    }

    // MARK: - Firefox

    private func extractFirefox() throws -> String? {
        let profilesDir = ("~/Library/Application Support/Firefox/Profiles" as NSString).expandingTildeInPath
        let fm = FileManager.default
        guard let profiles = try? fm.contentsOfDirectory(atPath: profilesDir) else { return nil }

        for profile in profiles where profile.hasSuffix(".default-release") || profile.hasSuffix(".default") {
            let cookiePath = "\(profilesDir)/\(profile)/cookies.sqlite"
            guard fm.fileExists(atPath: cookiePath) else { continue }
            let tmp = NSTemporaryDirectory() + UUID().uuidString + ".db"
            try fm.copyItem(atPath: cookiePath, toPath: tmp)
            defer { try? fm.removeItem(atPath: tmp) }
            let rows = try sqliteQuery(
                db: tmp,
                sql: "SELECT value FROM moz_cookies WHERE host LIKE '%claude.ai%' AND name='sessionKey' LIMIT 1"
            )
            if let data = rows.first, let val = String(data: data, encoding: .utf8) { return val }
        }
        return nil
    }

    // MARK: - SQLite helper

    private func sqliteQuery(db path: String, sql: String) throws -> [Data] {
        var dbPtr: OpaquePointer?
        guard sqlite3_open_v2(path, &dbPtr, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw NSError(domain: "SQLite", code: Int(sqlite3_errcode(dbPtr)),
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(dbPtr))])
        }
        defer { sqlite3_close(dbPtr) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(dbPtr, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var results: [Data] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let blob = sqlite3_column_blob(stmt, 0) {
                let len = Int(sqlite3_column_bytes(stmt, 0))
                results.append(Data(bytes: blob, count: len))
            }
        }
        return results
    }

    // MARK: - Chromium AES-128-CBC decryption

    private func decryptChromiumCookie(_ data: Data) throws -> String? {
        guard data.count > 3 else { return nil }
        let prefix = data.prefix(3)
        guard prefix == Data([0x76, 0x31, 0x30]) else {
            return String(data: data, encoding: .utf8) // unencrypted
        }
        guard let password = chromeSafeStoragePassword() else { return nil }

        // Derive AES key: PBKDF2-SHA1(password, "saltysalt", 1003 iterations, 16 bytes)
        let salt = Data("saltysalt".utf8)
        var derivedKey = Data(count: 16)
        let pbkdfResult = derivedKey.withUnsafeMutableBytes { keyPtr in
            salt.withUnsafeBytes { saltPtr in
                password.withUnsafeBytes { pwPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr.baseAddress, password.count,
                        saltPtr.baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        keyPtr.baseAddress, 16
                    )
                }
            }
        }
        guard pbkdfResult == kCCSuccess else { return nil }

        let encrypted = data.dropFirst(3)
        let iv = Data(repeating: 0x20, count: 16) // 16 space chars
        let decryptedSize = encrypted.count + kCCBlockSizeAES128
        var decrypted = Data(count: decryptedSize)
        var outLen = 0
        let cryptStatus = decrypted.withUnsafeMutableBytes { outPtr in
            encrypted.withUnsafeBytes { encPtr in
                derivedKey.withUnsafeBytes { keyPtr2 in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr2.baseAddress, 16,
                            ivPtr.baseAddress,
                            encPtr.baseAddress, encrypted.count,
                            outPtr.baseAddress, decryptedSize,
                            &outLen
                        )
                    }
                }
            }
        }
        guard cryptStatus == kCCSuccess else { return nil }
        return String(data: decrypted.prefix(outLen), encoding: .utf8)
    }

    private func chromeSafeStoragePassword() -> Data? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: "Chrome Safe Storage",
            kSecAttrAccount: "Chrome",
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    // MARK: - Binary file scan

    private func findSessionKeyInBinaryFile(path: String) throws -> String? {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let marker = Array("sk-ant-".utf8)
        var i = 0
        while i < data.count - marker.count {
            if Array(data[i..<i + marker.count]) == marker {
                var end = i
                while end < data.count && data[end] >= 0x20 && data[end] < 0x7F { end += 1 }
                if let key = String(data: data[i..<end], encoding: .utf8), key.count > 20 { return key }
            }
            i += 1
        }
        return nil
    }
}
