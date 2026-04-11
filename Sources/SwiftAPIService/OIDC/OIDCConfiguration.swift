//
//  OIDCConfiguration.swift
//  SwiftAPIService
//
//  Created by Gustavo Silva.
//

import Foundation

/// Configuration for an OIDC / OAuth 2.0 provider.
///
/// Pass an instance to ``OIDCAuthService`` to define the identity
/// provider and client registration details.
///
/// ```swift
/// let config = OIDCConfiguration(
///     issuer: URL(string: "https://accounts.google.com")!,
///     clientID: "my-client-id",
///     redirectURI: URL(string: "com.myapp://callback")!,
///     scopes: ["openid", "profile", "email"]
/// )
/// ```
public struct OIDCConfiguration: Sendable {

    /// The OIDC issuer URL (e.g. `https://accounts.google.com`).
    /// Used for service discovery at `issuer/.well-known/openid-configuration`.
    public let issuer: URL

    /// The OAuth 2.0 client identifier registered with the provider.
    public let clientID: String

    /// The client secret, if required by the provider.
    /// Native apps typically use PKCE instead of a client secret.
    public let clientSecret: String?

    /// The redirect URI registered with the provider.
    /// Must match exactly what is configured in the provider's client settings.
    public let redirectURI: URL

    /// The OAuth 2.0 / OIDC scopes to request. Defaults to `["openid"]`.
    public let scopes: [String]

    /// Additional parameters to include in the authorization request.
    public let additionalParameters: [String: String]

    /// When `true`, the browser session does not share cookies with
    /// Safari, forcing the user to authenticate every time.
    /// Defaults to `false`.
    public let prefersEphemeralSession: Bool

    /// The URL scheme extracted from ``redirectURI``,
    /// used to register the app's custom URL callback.
    public var callbackScheme: String? {
        redirectURI.scheme
    }

    public init(
        issuer: URL,
        clientID: String,
        clientSecret: String? = nil,
        redirectURI: URL,
        scopes: [String] = ["openid"],
        additionalParameters: [String: String] = [:],
        prefersEphemeralSession: Bool = false
    ) {
        self.issuer = issuer
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.additionalParameters = additionalParameters
        self.prefersEphemeralSession = prefersEphemeralSession
    }
}
