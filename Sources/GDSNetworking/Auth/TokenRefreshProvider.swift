//
//  TokenRefreshProvider.swift
//  GDSNetworking
//
//  Created by Gustavo Silva.
//

import Foundation

/// A protocol that the consuming application implements to provide
/// token-refresh logic specific to its backend.
///
/// The ``AuthInterceptor`` calls ``refresh(using:)`` when a 401 is
/// detected and the current access token needs to be replaced.
///
/// ```swift
/// struct MyRefreshProvider: TokenRefreshProvider {
///     func refresh(using refreshToken: String) async throws -> AuthCredential {
///         let response = try await myAPI.refreshToken(refreshToken)
///         return AuthCredential(accessToken: response.access, refreshToken: response.refresh)
///     }
/// }
/// ```
public protocol TokenRefreshProvider: Sendable {
    /// Exchanges the current refresh token for a new credential pair.
    ///
    /// - Parameter refreshToken: The refresh token currently stored.
    /// - Returns: A new `AuthCredential` containing fresh tokens.
    /// - Throws: If the refresh fails (e.g. refresh token expired).
    func refresh(using refreshToken: String) async throws -> AuthCredential
}
