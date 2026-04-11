//
//  OIDCAuthService.swift
//  SwiftAPIService
//
//  Created by Gustavo Silva.
//

@preconcurrency import AppAuth
import Foundation
import os.log

/// A reusable OIDC / OAuth 2.0 authentication service built on AppAuth.
///
/// `OIDCAuthService` orchestrates the full authentication lifecycle:
/// discovery, authorization (with PKCE), token exchange, session restore,
/// and logout.  Tokens are persisted through the existing ``TokenStore``
/// and refresh is handled via ``OIDCTokenRefreshProvider`` which plugs
/// directly into ``AuthInterceptor``.
///
/// ## Quick start
/// ```swift
/// let oidcService = OIDCAuthService(
///     configuration: myOIDCConfig,
///     tokenStore: tokenStore
/// )
///
/// // Login — presents the system browser
/// let credential = try await oidcService.login(
///     presentationContext: myAnchorProvider
/// )
///
/// // Wire refresh into the networking layer
/// let interceptor = AuthInterceptor(
///     tokenStore: tokenStore,
///     refreshProvider: oidcService.tokenRefreshProvider!
/// )
/// ```
public final class OIDCAuthService: @unchecked Sendable {

    // MARK: - Properties

    /// The OIDC provider configuration.
    public let configuration: OIDCConfiguration

    /// The token store used for credential persistence.
    public let tokenStore: TokenStore

    /// The token refresh provider, available after a successful
    /// ``login(presentationContext:)`` or ``restoreSession()``.
    ///
    /// Pass this to ``AuthInterceptor`` to enable automatic 401 refresh.
    public private(set) var tokenRefreshProvider: OIDCTokenRefreshProvider?

    /// The discovered OIDC service configuration, cached after first discovery.
    private var serviceConfiguration: OIDServiceConfiguration?

    /// Strong reference to the active AppAuth browser session,
    /// preventing premature deallocation.
    @MainActor private var currentAuthorizationFlow: OIDExternalUserAgentSession?

    private let logger = Logger(subsystem: "com.gds.networking", category: "OIDC")

    // MARK: - Init

    /// Creates a new OIDC authentication service.
    ///
    /// - Parameters:
    ///   - configuration: The OIDC provider and client configuration.
    ///   - tokenStore: The actor-backed token store for credential persistence.
    public init(configuration: OIDCConfiguration, tokenStore: TokenStore) {
        self.configuration = configuration
        self.tokenStore = tokenStore
    }

    // MARK: - Login

    /// Performs the full OIDC authorization code flow with PKCE.
    ///
    /// 1. Discovers the OIDC provider's endpoints.
    /// 2. Builds an authorization request with PKCE code challenge.
    /// 3. Presents the system browser via AppAuth's external user agent.
    /// 4. Exchanges the authorization code for tokens.
    /// 5. Stores the resulting credential in ``tokenStore``.
    /// 6. Creates the ``tokenRefreshProvider``.
    ///
    /// - Parameter presentationContext: An object providing the UI anchor
    ///   for browser presentation.
    /// - Returns: The freshly obtained ``AuthCredential``.
    /// - Throws: ``OIDCError`` on any step failure.
    @discardableResult
    public func login(
        presentationContext: some OIDCPresentationContextProviding
    ) async throws -> AuthCredential {
        let serviceConfig = try await discoverConfiguration()

        let authRequest = buildAuthorizationRequest(serviceConfiguration: serviceConfig)

        let authState = try await performAuthorization(
            request: authRequest,
            presentationContext: presentationContext
        )

        let credential = try extractCredential(from: authState)
        await tokenStore.store(credential)

        tokenRefreshProvider = OIDCTokenRefreshProvider(
            serviceConfiguration: serviceConfig,
            oidcConfiguration: configuration
        )

        logger.info("OIDC login succeeded. Access token stored.")
        return credential
    }

    // MARK: - Restore Session

    /// Restores a previously authenticated session without presenting
    /// the browser.
    ///
    /// Call this on app launch to check whether valid tokens exist in
    /// the ``tokenStore``.  If tokens are found, service discovery is
    /// performed and ``tokenRefreshProvider`` is created so the
    /// networking layer can refresh transparently.
    ///
    /// - Returns: The existing ``AuthCredential``, or `nil` if no
    ///   session is stored.
    /// - Throws: ``OIDCError/discoveryFailed(_:)`` if discovery fails.
    @discardableResult
    public func restoreSession() async throws -> AuthCredential? {
        guard let credential = await tokenStore.credential else {
            logger.info("No stored session to restore.")
            return nil
        }

        let serviceConfig = try await discoverConfiguration()

        tokenRefreshProvider = OIDCTokenRefreshProvider(
            serviceConfiguration: serviceConfig,
            oidcConfiguration: configuration
        )

        logger.info("OIDC session restored from stored tokens.")
        return credential
    }

    // MARK: - Logout

    /// Clears all stored tokens and resets the service state.
    ///
    /// If the OIDC provider exposes an `end_session_endpoint` (via
    /// discovery), the returned URL can be used by the consuming app
    /// to perform RP-Initiated Logout in a browser.
    ///
    /// - Returns: The provider's end-session URL with an `id_token_hint`,
    ///   or `nil` if the provider does not support RP-Initiated Logout.
    @discardableResult
    public func logout() async -> URL? {
        let idToken = await tokenStore.idToken
        await tokenStore.clear()
        tokenRefreshProvider = nil

        // Build the RP-Initiated Logout URL if supported.
        guard let serviceConfig = serviceConfiguration,
              let endSessionEndpoint = serviceConfig.endSessionEndpoint else {
            logger.info("OIDC logout: tokens cleared (no end_session_endpoint).")
            return nil
        }

        var components = URLComponents(url: endSessionEndpoint, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        if let idToken {
            queryItems.append(URLQueryItem(name: "id_token_hint", value: idToken))
        }
        queryItems.append(URLQueryItem(
            name: "post_logout_redirect_uri",
            value: configuration.redirectURI.absoluteString
        ))
        components?.queryItems = queryItems

        let logoutURL = components?.url
        logger.info("OIDC logout: tokens cleared. End-session URL available: \(logoutURL != nil)")
        return logoutURL
    }

    // MARK: - Discovery

    /// Discovers (and caches) the OIDC provider's service configuration.
    ///
    /// - Returns: The ``OIDServiceConfiguration`` with authorization,
    ///   token, and other endpoints.
    /// - Throws: ``OIDCError/discoveryFailed(_:)`` on failure.
    public func discoverConfiguration() async throws -> OIDServiceConfiguration {
        if let cached = serviceConfiguration {
            return cached
        }

        let discovered: OIDServiceConfiguration = try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.discoverConfiguration(
                forIssuer: configuration.issuer
            ) { config, error in
                if let error {
                    continuation.resume(throwing: OIDCError.discoveryFailed(error.localizedDescription))
                } else if let config {
                    continuation.resume(returning: config)
                } else {
                    continuation.resume(throwing: OIDCError.discoveryFailed(
                        "No configuration returned for issuer: \(self.configuration.issuer)"
                    ))
                }
            }
        }

        serviceConfiguration = discovered
        logger.info("OIDC discovery completed for \(self.configuration.issuer).")
        return discovered
    }

    // MARK: - Private — Authorization Request

    private func buildAuthorizationRequest(
        serviceConfiguration: OIDServiceConfiguration
    ) -> OIDAuthorizationRequest {
        OIDAuthorizationRequest(
            configuration: serviceConfiguration,
            clientId: configuration.clientID,
            clientSecret: configuration.clientSecret,
            scopes: configuration.scopes,
            redirectURL: configuration.redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: configuration.additionalParameters.isEmpty
                ? nil
                : configuration.additionalParameters
        )
    }

    // MARK: - Private — Browser Authorization

    private func performAuthorization(
        request: OIDAuthorizationRequest,
        presentationContext: some OIDCPresentationContextProviding
    ) async throws -> OIDAuthState {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let context = presentationContext.presentingContext()
                let agent = makeExternalUserAgent(
                    from: context,
                    prefersEphemeralSession: self.configuration.prefersEphemeralSession
                )

                self.currentAuthorizationFlow = OIDAuthState.authState(
                    byPresenting: request,
                    externalUserAgent: agent
                ) { authState, error in
                    Task { @MainActor in
                        self.currentAuthorizationFlow = nil
                    }

                    if let error {
                        continuation.resume(throwing: OIDCError.authorizationFailed(error.localizedDescription))
                    } else if let authState {
                        continuation.resume(returning: authState)
                    } else {
                        continuation.resume(throwing: OIDCError.authorizationFailed(
                            "Authorization completed without a result."
                        ))
                    }
                }
            }
        }
    }

    // MARK: - Private — Credential Extraction

    private func extractCredential(from authState: OIDAuthState) throws -> AuthCredential {
        guard let tokenResponse = authState.lastTokenResponse,
              let accessToken = tokenResponse.accessToken else {
            throw OIDCError.missingTokens("Access token missing from authorization response.")
        }

        guard let refreshToken = tokenResponse.refreshToken else {
            throw OIDCError.missingTokens(
                "Refresh token missing from authorization response. "
                + "Ensure 'offline_access' scope is requested if required by your provider."
            )
        }

        return AuthCredential(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: tokenResponse.idToken,
            accessTokenExpirationDate: tokenResponse.accessTokenExpirationDate
        )
    }
}
