//
//  OIDCTests.swift
//  SwiftAPIServiceTests
//
//  Created by Gustavo Silva.
//

import Foundation
import Testing
@testable import SwiftAPIService

// MARK: - OIDCConfiguration

@Test func oidcConfigurationDefaults() {
    let config = OIDCConfiguration(
        issuer: URL(string: "https://auth.example.com")!,
        clientID: "my-client",
        redirectURI: URL(string: "com.example.app://callback")!
    )

    #expect(config.issuer.absoluteString == "https://auth.example.com")
    #expect(config.clientID == "my-client")
    #expect(config.clientSecret == nil)
    #expect(config.redirectURI.absoluteString == "com.example.app://callback")
    #expect(config.scopes == ["openid"])
    #expect(config.additionalParameters.isEmpty)
    #expect(config.prefersEphemeralSession == false)
    #expect(config.callbackScheme == "com.example.app")
}

@Test func oidcConfigurationCustomValues() {
    let config = OIDCConfiguration(
        issuer: URL(string: "https://login.microsoftonline.com/tenant")!,
        clientID: "abc-123",
        clientSecret: "super-secret",
        redirectURI: URL(string: "msauth.com.example://auth")!,
        scopes: ["openid", "profile", "email", "offline_access"],
        additionalParameters: ["prompt": "login"],
        prefersEphemeralSession: true
    )

    #expect(config.clientSecret == "super-secret")
    #expect(config.scopes.count == 4)
    #expect(config.additionalParameters["prompt"] == "login")
    #expect(config.prefersEphemeralSession == true)
    #expect(config.callbackScheme == "msauth.com.example")
}

// MARK: - OIDCError

@Test func oidcErrorDescriptions() {
    let cases: [(OIDCError, String)] = [
        (.discoveryFailed("timeout"), "OIDC discovery failed: timeout"),
        (.authorizationFailed("cancelled"), "OIDC authorization failed: cancelled"),
        (.tokenExchangeFailed("bad code"), "OIDC token exchange failed: bad code"),
        (.tokenRefreshFailed("expired"), "OIDC token refresh failed: expired"),
        (.logoutFailed("network"), "OIDC logout failed: network"),
        (.missingTokens("no access"), "OIDC missing tokens: no access"),
        (.sessionNotRestored, "No persisted OIDC session found to restore."),
    ]

    for (error, expected) in cases {
        #expect(error.description == expected)
    }
}

@Test func oidcErrorConformsToError() {
    let error: any Error = OIDCError.discoveryFailed("test")
    #expect(error is OIDCError)
}

// MARK: - AuthCredential (OIDC extensions)

@Test func authCredentialBackwardCompatibility() {
    // Existing call sites that don't pass the new OIDC fields must still work.
    let credential = AuthCredential(accessToken: "at", refreshToken: "rt")

    #expect(credential.accessToken == "at")
    #expect(credential.refreshToken == "rt")
    #expect(credential.idToken == nil)
    #expect(credential.accessTokenExpirationDate == nil)
    #expect(credential.isAccessTokenExpired == false)
}

@Test func authCredentialWithOIDCFields() {
    let future = Date().addingTimeInterval(3600)
    let credential = AuthCredential(
        accessToken: "at",
        refreshToken: "rt",
        idToken: "eyJhbGciOi.eyJzdWIiOi.signature",
        accessTokenExpirationDate: future
    )

    #expect(credential.idToken == "eyJhbGciOi.eyJzdWIiOi.signature")
    #expect(credential.accessTokenExpirationDate == future)
    #expect(credential.isAccessTokenExpired == false)
}

@Test func authCredentialExpiredToken() {
    let past = Date().addingTimeInterval(-60)
    let credential = AuthCredential(
        accessToken: "at",
        refreshToken: "rt",
        accessTokenExpirationDate: past
    )

    #expect(credential.isAccessTokenExpired == true)
}

@Test func authCredentialEquality() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let a = AuthCredential(accessToken: "a", refreshToken: "r", idToken: "id", accessTokenExpirationDate: date)
    let b = AuthCredential(accessToken: "a", refreshToken: "r", idToken: "id", accessTokenExpirationDate: date)
    let c = AuthCredential(accessToken: "a", refreshToken: "r")

    #expect(a == b)
    #expect(a != c)
}

// MARK: - TokenStore (OIDC fields)

@Test func tokenStoreStoresAndLoadsOIDCFields() async {
    let keychain = KeychainService(service: "com.gds.networking.oidc-tests")
    defer { keychain.clear() }

    let expiration = Date(timeIntervalSince1970: 1_700_000_000)
    let credential = AuthCredential(
        accessToken: "access-tok",
        refreshToken: "refresh-tok",
        idToken: "id-tok-jwt",
        accessTokenExpirationDate: expiration
    )

    let store = TokenStore(keychain: keychain)
    await store.store(credential)

    let loaded = await store.credential
    #expect(loaded?.accessToken == "access-tok")
    #expect(loaded?.refreshToken == "refresh-tok")
    #expect(loaded?.idToken == "id-tok-jwt")

    // Verify expiration round-trips (compare to nearest second).
    let loadedInterval = loaded?.accessTokenExpirationDate?.timeIntervalSince1970 ?? 0
    #expect(abs(loadedInterval - expiration.timeIntervalSince1970) < 1)
}

@Test func tokenStoreHydratesOIDCFieldsFromKeychain() async {
    let keychain = KeychainService(service: "com.gds.networking.oidc-hydrate")
    defer { keychain.clear() }

    let expiration = Date(timeIntervalSince1970: 1_700_000_000)
    let credential = AuthCredential(
        accessToken: "hydrate-at",
        refreshToken: "hydrate-rt",
        idToken: "hydrate-id",
        accessTokenExpirationDate: expiration
    )

    // Store via one TokenStore instance.
    let store1 = TokenStore(keychain: keychain)
    await store1.store(credential)

    // Create a fresh TokenStore — should hydrate from Keychain.
    let store2 = TokenStore(keychain: keychain)
    let hydrated = await store2.credential

    #expect(hydrated?.accessToken == "hydrate-at")
    #expect(hydrated?.refreshToken == "hydrate-rt")
    #expect(hydrated?.idToken == "hydrate-id")
    #expect(hydrated?.accessTokenExpirationDate != nil)
}

@Test func tokenStoreClearRemovesOIDCFields() async {
    let keychain = KeychainService(service: "com.gds.networking.oidc-clear")
    defer { keychain.clear() }

    let store = TokenStore(keychain: keychain)
    await store.store(AuthCredential(
        accessToken: "a",
        refreshToken: "r",
        idToken: "id",
        accessTokenExpirationDate: Date()
    ))
    await store.clear()

    #expect(await store.credential == nil)
    #expect(await store.accessToken == nil)
    #expect(await store.idToken == nil)

    // Verify Keychain is clean.
    #expect(keychain.read(forKey: "gds_id_token") == nil)
    #expect(keychain.read(forKey: "gds_token_expiration") == nil)
}

@Test func tokenStoreWithoutOIDCFieldsHydratesGracefully() async {
    let keychain = KeychainService(service: "com.gds.networking.oidc-legacy")
    defer { keychain.clear() }

    // Simulate a legacy store that only has access + refresh tokens.
    keychain.set("legacy-at", forKey: "gds_access_token")
    keychain.set("legacy-rt", forKey: "gds_refresh_token")

    let store = TokenStore(keychain: keychain)
    let credential = await store.credential

    #expect(credential?.accessToken == "legacy-at")
    #expect(credential?.refreshToken == "legacy-rt")
    #expect(credential?.idToken == nil)
    #expect(credential?.accessTokenExpirationDate == nil)
    #expect(credential?.isAccessTokenExpired == false)
}

// MARK: - OIDCAuthService (unit-testable paths)

@Test func oidcAuthServiceRestoreSessionReturnsNilWhenEmpty() async throws {
    let keychain = KeychainService(service: "com.gds.networking.oidc-restore")
    defer { keychain.clear() }

    let store = TokenStore(keychain: keychain)
    let config = OIDCConfiguration(
        issuer: URL(string: "https://auth.example.com")!,
        clientID: "test",
        redirectURI: URL(string: "com.test://cb")!
    )

    let service = OIDCAuthService(configuration: config, tokenStore: store)
    let result = try await service.restoreSession()

    #expect(result == nil)
    #expect(service.tokenRefreshProvider == nil)
}

@Test func oidcAuthServiceLogoutClearsTokens() async {
    let keychain = KeychainService(service: "com.gds.networking.oidc-logout")
    defer { keychain.clear() }

    let store = TokenStore(keychain: keychain)
    await store.store(AuthCredential(
        accessToken: "a",
        refreshToken: "r",
        idToken: "id"
    ))

    let config = OIDCConfiguration(
        issuer: URL(string: "https://auth.example.com")!,
        clientID: "test",
        redirectURI: URL(string: "com.test://cb")!
    )
    let service = OIDCAuthService(configuration: config, tokenStore: store)

    let logoutURL = await service.logout()

    #expect(logoutURL == nil) // No discovery performed, so no end_session_endpoint.
    #expect(await store.credential == nil)
    #expect(await store.accessToken == nil)
    #expect(await store.idToken == nil)
}

@Test func oidcAuthServiceInitDoesNotMutateStore() async {
    let keychain = KeychainService(service: "com.gds.networking.oidc-init")
    defer { keychain.clear() }

    let store = TokenStore(keychain: keychain)
    await store.store(AuthCredential(accessToken: "pre", refreshToken: "pre-r"))

    let config = OIDCConfiguration(
        issuer: URL(string: "https://auth.example.com")!,
        clientID: "test",
        redirectURI: URL(string: "com.test://cb")!
    )
    _ = OIDCAuthService(configuration: config, tokenStore: store)

    // Creating the service must not alter existing tokens.
    #expect(await store.accessToken == "pre")
}
