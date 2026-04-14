//
//  AuthCredential.swift
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
