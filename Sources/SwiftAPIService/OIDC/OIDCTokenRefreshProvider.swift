//
//  OIDCTokenRefreshProvider.swift
//  SwiftAPIService
//
//  Created by Gustavo Silva.
//

@preconcurrency import AppAuth
import Foundation

/// A concrete ``TokenRefreshProvider`` that uses AppAuth's
/// `OIDTokenRequest` with the `refresh_token` grant type.
///
/// Created automatically by ``OIDCAuthService`` after a successful
/// login or session restore. Pass it to ``AuthInterceptor`` so that
/// 401 retries transparently refresh the access token.
///
/// ```swift
/// let authInterceptor = AuthInterceptor(
///     tokenStore: tokenStore,
///     refreshProvider: oidcService.tokenRefreshProvider!
/// )
/// ```
public final class OIDCTokenRefreshProvider: TokenRefreshProvider, @unchecked Sendable {

    // MARK: - Properties

    private let serviceConfiguration: OIDServiceConfiguration
    private let clientID: String
    private let clientSecret: String?
    private let redirectURI: URL

    // MARK: - Init

    /// Creates a new refresh provider.
    ///
    /// - Parameters:
    ///   - serviceConfiguration: The discovered OIDC service configuration
    ///     (contains token endpoint, etc.).
    ///   - oidcConfiguration: The client-side OIDC configuration.
    init(
        serviceConfiguration: OIDServiceConfiguration,
        oidcConfiguration: OIDCConfiguration
    ) {
        self.serviceConfiguration = serviceConfiguration
        self.clientID = oidcConfiguration.clientID
        self.clientSecret = oidcConfiguration.clientSecret
        self.redirectURI = oidcConfiguration.redirectURI
    }

    // MARK: - TokenRefreshProvider

    /// Exchanges the current refresh token for a new credential pair
    /// using AppAuth's token request.
    ///
    /// - Parameter refreshToken: The refresh token currently stored.
    /// - Returns: A fresh ``AuthCredential``.
    /// - Throws: ``OIDCError/tokenRefreshFailed(_:)`` on failure.
    public func refresh(using refreshToken: String) async throws -> AuthCredential {
        let tokenRequest = OIDTokenRequest(
            configuration: serviceConfiguration,
            grantType: OIDGrantTypeRefreshToken,
            authorizationCode: nil,
            redirectURL: redirectURI,
            clientID: clientID,
            clientSecret: clientSecret,
            scope: nil,
            refreshToken: refreshToken,
            codeVerifier: nil,
            additionalParameters: nil
        )

        let tokenResponse: OIDTokenResponse = try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.perform(tokenRequest) { response, error in
                if let error {
                    continuation.resume(throwing: OIDCError.tokenRefreshFailed(error.localizedDescription))
                } else if let response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: OIDCError.tokenRefreshFailed("No response received from token endpoint."))
                }
            }
        }

        guard let accessToken = tokenResponse.accessToken else {
            throw OIDCError.missingTokens("Access token missing from refresh response.")
        }

        return AuthCredential(
            accessToken: accessToken,
            refreshToken: tokenResponse.refreshToken ?? refreshToken,
            idToken: tokenResponse.idToken,
            accessTokenExpirationDate: tokenResponse.accessTokenExpirationDate
        )
    }
}
