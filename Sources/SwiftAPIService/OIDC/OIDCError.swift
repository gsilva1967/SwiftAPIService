//
//  OIDCError.swift
//  SwiftAPIService
//
//  Created by Gustavo Silva.
//

import Foundation

/// Errors specific to the OIDC / OAuth 2.0 authentication flow.
public enum OIDCError: Error, Sendable, CustomStringConvertible {

    /// OIDC service discovery failed (e.g. network error or invalid issuer).
    case discoveryFailed(String)

    /// The user-facing authorization flow failed or was cancelled.
    case authorizationFailed(String)

    /// The authorization-code-for-token exchange failed.
    case tokenExchangeFailed(String)

    /// A token refresh attempt failed.
    case tokenRefreshFailed(String)

    /// Logout could not be completed.
    case logoutFailed(String)

    /// Expected tokens were missing from the provider's response.
    case missingTokens(String)

    /// No persisted session was found to restore.
    case sessionNotRestored

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case let .discoveryFailed(reason):
            return "OIDC discovery failed: \(reason)"
        case let .authorizationFailed(reason):
            return "OIDC authorization failed: \(reason)"
        case let .tokenExchangeFailed(reason):
            return "OIDC token exchange failed: \(reason)"
        case let .tokenRefreshFailed(reason):
            return "OIDC token refresh failed: \(reason)"
        case let .logoutFailed(reason):
            return "OIDC logout failed: \(reason)"
        case let .missingTokens(reason):
            return "OIDC missing tokens: \(reason)"
        case .sessionNotRestored:
            return "No persisted OIDC session found to restore."
        }
    }
}
