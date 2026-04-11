//
//  TokenStore.swift
//  SwiftAPIService
//
//  Created by Gustavo Silva.
//

import Foundation

/// Holds the access and refresh token pair, with optional OIDC fields.
public struct AuthCredential: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String

    /// The OIDC ID token (JWT). `nil` when not using OIDC.
    public let idToken: String?

    /// The date at which the access token expires. `nil` if unknown.
    public let accessTokenExpirationDate: Date?

    public init(
        accessToken: String,
        refreshToken: String,
        idToken: String? = nil,
        accessTokenExpirationDate: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.accessTokenExpirationDate = accessTokenExpirationDate
    }

    /// Whether the access token has passed its expiration date.
    /// Returns `false` when no expiration date is available.
    public var isAccessTokenExpired: Bool {
        guard let expirationDate = accessTokenExpirationDate else { return false }
        return Date() >= expirationDate
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
        static let idToken = "gds_id_token"
        static let tokenExpiration = "gds_token_expiration"
    }

    // MARK: - Properties

    private let keychain: KeychainService
    private var _credential: AuthCredential?

    /// The currently stored credential, or `nil` if the user is unauthenticated.
    public var credential: AuthCredential? { _credential }

    /// Convenience accessor for the current access token.
    public var accessToken: String? { _credential?.accessToken }

    /// Convenience accessor for the current ID token.
    public var idToken: String? { _credential?.idToken }

    // MARK: - Init

    /// Creates the store and loads any previously persisted tokens.
    ///
    /// - Parameter keychain: The `KeychainService` instance to use for persistence.
    public init(keychain: KeychainService) {
        self.keychain = keychain

        // Hydrate from Keychain on launch.
        if let access = keychain.read(forKey: Keys.accessToken),
           let refresh = keychain.read(forKey: Keys.refreshToken) {
            let idToken = keychain.read(forKey: Keys.idToken)
            let expiration: Date?
            if let raw = keychain.read(forKey: Keys.tokenExpiration),
               let interval = TimeInterval(raw) {
                expiration = Date(timeIntervalSince1970: interval)
            } else {
                expiration = nil
            }
            _credential = AuthCredential(
                accessToken: access,
                refreshToken: refresh,
                idToken: idToken,
                accessTokenExpirationDate: expiration
            )
        }
    }

    // MARK: - Mutations

    /// Persists a new credential pair in both memory and the Keychain.
    public func store(_ credential: AuthCredential) {
        _credential = credential
        keychain.set(credential.accessToken, forKey: Keys.accessToken)
        keychain.set(credential.refreshToken, forKey: Keys.refreshToken)

        if let idToken = credential.idToken {
            keychain.set(idToken, forKey: Keys.idToken)
        } else {
            keychain.delete(forKey: Keys.idToken)
        }

        if let expiration = credential.accessTokenExpirationDate {
            keychain.set(String(expiration.timeIntervalSince1970), forKey: Keys.tokenExpiration)
        } else {
            keychain.delete(forKey: Keys.tokenExpiration)
        }
    }

    /// Removes all stored tokens from memory and the Keychain.
    public func clear() {
        _credential = nil
        keychain.delete(forKey: Keys.accessToken)
        keychain.delete(forKey: Keys.refreshToken)
        keychain.delete(forKey: Keys.idToken)
        keychain.delete(forKey: Keys.tokenExpiration)
    }
}
