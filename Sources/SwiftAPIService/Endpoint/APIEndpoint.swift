//
//  APIEndpoint.swift
//  SwiftAPIService
//
//  Created by Gustavo Silva.
//

import Alamofire
import Foundation

/// Describes a single API endpoint.
///
/// Conform to this protocol (typically via an `enum`) to define the
/// path, HTTP method, headers, query parameters, and body for each
/// request your application needs.
///
/// ```swift
/// enum UserEndpoint: APIEndpoint {
///     case profile(id: String)
///     case updateProfile(User)
///
///     var path: String {
///         switch self {
///         case .profile(let id): "/users/\(id)"
///         case .updateProfile:   "/users/profile"
///         }
///     }
///     ...
/// }
/// ```
public protocol APIEndpoint: Sendable {
    /// The URL path relative to the environment's `baseURL` (e.g. `"/users/profile"`).
    var path: String { get }

    /// The HTTP method for this endpoint. Defaults to `.get`.
    var method: HTTPMethod { get }

    /// Additional headers specific to this endpoint.
    /// Merged on top of the environment's `defaultHeaders`.
    var headers: HTTPHeaders? { get }

    /// The `Content-Type` header value. Defaults to `"application/json"`.
    var contentType: String { get }

    /// URL query items appended to the request URL.
    var queryItems: [URLQueryItem]? { get }

    /// An encodable body payload. Return `nil` for GET requests.
    var body: (any Encodable & Sendable)? { get }

    /// Valid HTTP status codes for response validation.
    /// Defaults to `200..<300`.
    var acceptableStatusCodes: Range<Int> { get }
}

// MARK: - Defaults

public extension APIEndpoint {
    var method: HTTPMethod { .get }
    var headers: HTTPHeaders? { nil }
    var contentType: String { "application/json" }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var acceptableStatusCodes: Range<Int> { 200..<300 }
}

// MARK: - URL Construction

public extension APIEndpoint {

    /// Builds the full `URL` by appending `path` and `queryItems` to the environment's base URL.
    func url(relativeTo baseURL: URL) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            fatalError("[SwiftAPIService] Unable to construct URL for path: \(path)")
        }
        return url
    }
}
