//
//  KeychainService.swift
//  GDSNetworking
//
//  Created by Gustavo Silva.
//

import Foundation
import Security

/// A lightweight, thread-safe Keychain wrapper for storing sensitive strings.
///
/// Uses the iOS / macOS Security framework directly — no third-party dependencies.
/// All operations are synchronous and safe to call from any thread.
public struct KeychainService: Sendable {

    /// The service identifier used to namespace stored items.
    private let service: String

    /// An optional access group for sharing items between apps / extensions.
    private let accessGroup: String?

    /// Creates a new `KeychainService`.
    ///
    /// - Parameters:
    ///   - service: A reverse-DNS identifier (e.g. `"com.myapp.api"`).
    ///   - accessGroup: An optional Keychain access group.
    public init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - Public API

    /// Saves (or updates) a string value for the given key.
    @discardableResult
    public func set(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Try to update first; insert if the item doesn't exist yet.
        if read(forKey: key) != nil {
            let query = baseQuery(for: key)
            let attributes: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            return status == errSecSuccess
        }

        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Reads the string stored under `key`, or `nil` if missing.
    public func read(forKey key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = kCFBooleanTrue!
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return string
    }

    /// Deletes the item stored under `key`.
    @discardableResult
    public func delete(forKey key: String) -> Bool {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Removes all items belonging to this service.
    @discardableResult
    public func clear() -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Private

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
