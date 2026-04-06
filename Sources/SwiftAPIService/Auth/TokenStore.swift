//
//  TokenStore.swift
//  SwiftAPIService
//
//  Created by Gustavo Silva.
//

import Foundation

/// Holds the access and refresh token pair.
public struct AuthCredential: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String

    public init(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

/// A concurrency-safe store that persists authentication tokens in the Keychain.
///
/// Uses a Swift `actor` to guarantee thread-safe, serialised access.
/// Tokens are written to the Keychain on every mutation and loaded
/// from the Keychain when the store is created.
public actor TokenStore {

    // MARK: - Keychain keys

    private enum Keys {
        static let accessToken = "gds_access_token"
        static let refreshToken = "gds_refresh_token"
    }

    // MARK: - Properties

    private let keychain: KeychainService
    private var _credential: AuthCredential?

    /// The currently stored credential, or `nil` if the user is unauthenticated.
    public var credential: AuthCredential? { _credential }

    /// Convenience accessor for the current access token.
    public var accessToken: String? { _credential?.accessToken }

    // MARK: - Init

    /// Creates the store and loads any previously persisted tokens.
    ///
    /// - Parameter keychain: The `KeychainService` instance to use for persistence.
    public init(keychain: KeychainService) {
        self.keychain = keychain

        // Hydrate from Keychain on launch.
        if let access = keychain.read(forKey: Keys.accessToken),
           let refresh = keychain.read(forKey: Keys.refreshToken) {
            _credential = AuthCredential(accessToken: access, refreshToken: refresh)
        }
    }

    // MARK: - Mutations

    /// Persists a new credential pair in both memory and the Keychain.
    public func store(_ credential: AuthCredential) {
        _credential = credential
        keychain.set(credential.accessToken, forKey: Keys.accessToken)
        keychain.set(credential.refreshToken, forKey: Keys.refreshToken)
    }

    /// Removes all stored tokens from memory and the Keychain.
    public func clear() {
        _credential = nil
        keychain.delete(forKey: Keys.accessToken)
        keychain.delete(forKey: Keys.refreshToken)
    }
}
