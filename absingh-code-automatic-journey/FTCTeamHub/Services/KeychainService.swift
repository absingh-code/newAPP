//
//  KeychainService.swift
//  FTCTeamHub
//
//  Minimal Keychain wrapper used to persist the logged-in user's session
//  across app launches — this is exactly what was MISSING in the previous
//  version, which is why the app appeared to "kick you out": the sign-in
//  state lived only in an in-memory @Published var with no persistence at
//  all, so restarting the app (or SwiftUI simply re-rendering the root
//  view) reset it back to the login screen every time.
//
//  Storing just a UUID string (the session's user id) in the Keychain
//  is enough: on launch, AuthenticationManager reads this value and looks
//  up the matching AppUser from SwiftData to restore the full session.
//

import Foundation
import Security

enum KeychainService {

    /// Saves (or overwrites) a string value under the given key.
    @discardableResult
    static func save(_ key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Remove any existing item first so this always behaves like an
        // "upsert" rather than failing with errSecDuplicateItem.
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Reads a previously saved string value, or nil if none exists.
    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes a saved value, if present. Safe to call even if nothing exists.
    @discardableResult
    static func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
