//
//  GDSNetworkingTests.swift
//  GDSNetworkingTests
//
//  Created by Gustavo Silva.
//

import Testing
@testable import GDSNetworking

@Test func keychainStoreAndRead() {
    let keychain = KeychainService(service: "com.gds.networking.tests")
    defer { keychain.clear() }

    let stored = keychain.set("test-token-123", forKey: "access")
    #expect(stored == true)

    let value = keychain.read(forKey: "access")
    #expect(value == "test-token-123")
}

@Test func keychainDelete() {
    let keychain = KeychainService(service: "com.gds.networking.tests")
    defer { keychain.clear() }

    keychain.set("value", forKey: "key")
    let deleted = keychain.delete(forKey: "key")
    #expect(deleted == true)
    #expect(keychain.read(forKey: "key") == nil)
}

@Test func apiErrorFromAFError() {
    let afError = AFError.responseValidationFailed(
        reason: .unacceptableStatusCode(code: 401)
    )
    let apiError = APIError.from(afError)
    if case .unauthorized = apiError.kind {
        #expect(apiError.statusCode == 401)
    } else {
        Issue.record("Expected .unauthorized, got \(apiError.kind)")
    }
}

@Test func apiErrorPreservesExisting() {
    let original = APIError(kind: .timeout, details: "timed out")
    let converted = APIError.from(original)
    #expect(converted.details == "timed out")
}
