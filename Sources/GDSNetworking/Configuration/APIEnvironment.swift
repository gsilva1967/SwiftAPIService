//
//  APIEnvironment.swift
//  GDSNetworking
//
//  Created by Gustavo Silva.
//

import Foundation

/// Defines the server environment the API client connects to.
///
/// Conform to this protocol to supply environment-specific values
/// such as the base URL, default headers, API keys, and timeouts.
///
/// ```swift
/// enum MyEnvironment: APIEnvironment {
///     case dev, staging, prod
///     var baseURL: URL { ... }
/// }
/// ```
public protocol APIEnvironment: Sendable {
    /// The root URL for all API requests (e.g. `https://api.example.com`).
    var baseURL: URL { get }

    /// Headers that are automatically attached to every request
    /// (e.g. `apikey`, `apptoken`).
    var defaultHeaders: [String: String] { get }

    /// Per-request timeout interval in seconds. Defaults to `15`.
    var timeoutInterval: TimeInterval { get }
}

// MARK: - Defaults

public extension APIEnvironment {
    var defaultHeaders: [String: String] { [:] }
    var timeoutInterval: TimeInterval { 15 }
}
