//
//  APIClient.swift
//  GDSNetworking
//
//  Created by Gustavo Silva.
//

import Alamofire
import Foundation

/// The central networking client for the GDSNetworking package.
///
/// `APIClient` wraps an Alamofire `Session` and provides high-level,
/// async/await methods for JSON requests, multipart uploads, and
/// plain-text responses.
///
/// ## Quick start
/// ```swift
/// let client = APIClient(configuration: .init(
///     environment: MyEnvironment.dev,
///     tokenStore: tokenStore,
///     authInterceptor: authInterceptor
/// ))
///
/// let user: User = try await client.request(UserEndpoint.profile(id: "42"))
/// ```
public final class APIClient: Sendable {

    // MARK: - Configuration

    /// All values needed to bootstrap the client.
    public struct Configuration: Sendable {
        /// The environment providing the base URL and default headers.
        public let environment: any APIEnvironment

        /// The actor-backed token store for credential persistence.
        public let tokenStore: TokenStore

        /// The interceptor handling token attachment and 401 retry.
        /// Pass `nil` if authentication is not required.
        public let authInterceptor: AuthInterceptor?

        /// Additional Alamofire interceptors (e.g. `RetryPolicy`).
        public let additionalInterceptors: [any RequestInterceptor & Sendable]

        /// Alamofire event monitors (e.g. ``APILogger``).
        public let eventMonitors: [any EventMonitor & Sendable]

        /// Retry policy for transient server errors.
        public let retryPolicy: RetryPolicy?

        /// JSON encoder used for request bodies.
        public let encoder: JSONEncoder

        /// JSON decoder used for response parsing.
        public let decoder: JSONDecoder

        /// The logging verbosity. Defaults to `.info`.
        public let logLevel: APILogLevel

        public init(
            environment: any APIEnvironment,
            tokenStore: TokenStore,
            authInterceptor: AuthInterceptor? = nil,
            additionalInterceptors: [any RequestInterceptor & Sendable] = [],
            eventMonitors: [any EventMonitor & Sendable] = [],
            retryPolicy: RetryPolicy? = nil,
            encoder: JSONEncoder = {
                let e = JSONEncoder()
                e.dateEncodingStrategy = .iso8601
                return e
            }(),
            decoder: JSONDecoder = {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return d
            }(),
            logLevel: APILogLevel = .info
        ) {
            self.environment = environment
            self.tokenStore = tokenStore
            self.authInterceptor = authInterceptor
            self.additionalInterceptors = additionalInterceptors
            self.eventMonitors = eventMonitors
            self.retryPolicy = retryPolicy
            self.encoder = encoder
            self.decoder = decoder
            self.logLevel = logLevel
        }
    }

    // MARK: - Properties

    /// The configuration used to create this client.
    public let configuration: Configuration

    /// The underlying Alamofire session.
    private let session: Session

    /// Convenience accessors.
    private var environment: any APIEnvironment { configuration.environment }
    private var encoder: JSONEncoder { configuration.encoder }
    private var decoder: JSONDecoder { configuration.decoder }

    // MARK: - Init

    /// Creates a new `APIClient`.
    ///
    /// - Parameter configuration: The ``Configuration`` bundle.
    public init(configuration: Configuration) {
        self.configuration = configuration

        // Build URL session configuration.
        let urlConfig = URLSessionConfiguration.af.default
        urlConfig.timeoutIntervalForRequest = configuration.environment.timeoutInterval

        var headers = HTTPHeaders()
        for (key, value) in configuration.environment.defaultHeaders {
            headers.add(name: key, value: value)
        }
        urlConfig.headers = headers

        // Combine interceptors.
        var interceptors: [any RequestInterceptor] = []
        if let auth = configuration.authInterceptor {
            interceptors.append(auth)
        }
        if let retry = configuration.retryPolicy {
            interceptors.append(retry)
        }
        interceptors.append(contentsOf: configuration.additionalInterceptors)
        let compositeInterceptor = Interceptor(interceptors: interceptors)

        // Event monitors.
        var monitors: [any EventMonitor] = []
        if configuration.logLevel > .none {
            monitors.append(APILogger(level: configuration.logLevel))
        }
        monitors.append(contentsOf: configuration.eventMonitors)

        // Create session.
        session = Session(
            configuration: urlConfig,
            interceptor: compositeInterceptor,
            eventMonitors: monitors
        )
    }

    // MARK: - JSON Request

    /// Performs a request to the given endpoint and decodes the JSON response.
    ///
    /// - Parameters:
    ///   - endpoint: The ``APIEndpoint`` describing the request.
    ///   - type: The `Decodable` type to decode from the response body.
    /// - Returns: The decoded value of type `R`.
    public func request<R: Decodable & Sendable>(
        _ endpoint: some APIEndpoint,
        as type: R.Type = R.self
    ) async throws -> R {
        let urlRequest = try buildURLRequest(for: endpoint)

        let dataTask = session.request(urlRequest)
            .validate(statusCode: endpoint.acceptableStatusCodes)
            .serializingDecodable(type, automaticallyCancelling: true, decoder: decoder)

        let response = await dataTask.response

        switch response.result {
        case .success:
            return try await dataTask.value
        case let .failure(afError):
            throw APIError.from(afError)
        }
    }

    // MARK: - Raw Dispatch (legacy-compatible)

    /// A lower-level dispatch method that mirrors the original Safeguard
    /// `APIService.dispatch` signature for easier migration.
    ///
    /// Prefer ``request(_:as:)`` for new code.
    public func dispatch<R: Codable & Sendable>(
        httpMethod: HTTPMethod,
        endPoint: String,
        contentType: String = "application/json",
        resultType: R.Type,
        payload: (some Encodable)? = Optional<String>.none,
        timeoutIntervalInSeconds: Int? = nil
    ) async throws -> R {
        let url = URL(string: endPoint)!
        var urlRequest = URLRequest(url: url)
        urlRequest.method = httpMethod
        urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = TimeInterval(
            timeoutIntervalInSeconds ?? Int(environment.timeoutInterval)
        )

        // Encode body if present.
        if let payload {
            urlRequest.httpBody = try encoder.encode(payload)
        }

        let dataTask = session.request(urlRequest)
            .validate(statusCode: 200..<201)
            .serializingDecodable(resultType, automaticallyCancelling: true, decoder: decoder)

        let response = await dataTask.response

        switch response.result {
        case .success:
            return try await dataTask.value
        case let .failure(afError):
            throw APIError.from(afError)
        }
    }

    // MARK: - Multipart Upload

    /// Uploads a file using multipart form data.
    ///
    /// - Parameters:
    ///   - endpoint: The ``APIEndpoint`` describing the upload target.
    ///   - fileData: The raw file bytes.
    ///   - fileName: The filename to report in the multipart body.
    ///   - mimeType: The MIME type of the file (e.g. `"image/jpeg"`).
    ///   - parameters: Additional form fields to include.
    ///   - type: The `Decodable` type to decode from the response body.
    /// - Returns: The decoded value of type `R`.
    public func upload<R: Decodable & Sendable>(
        _ endpoint: some APIEndpoint,
        fileData: Data,
        fileName: String,
        mimeType: String = "image/jpeg",
        parameters: [String: String] = [:],
        as type: R.Type = R.self
    ) async throws -> R {
        let url = endpoint.url(relativeTo: environment.baseURL)

        var headers = HTTPHeaders()
        headers.add(name: "Accept", value: "application/json")

        let dataTask = session.upload(
            multipartFormData: { multipartFormData in
                for (key, value) in parameters {
                    if let data = value.data(using: .utf8) {
                        multipartFormData.append(data, withName: key)
                    }
                }
                multipartFormData.append(fileData, withName: "file", fileName: fileName, mimeType: mimeType)
            },
            to: url,
            method: endpoint.method,
            headers: headers
        )
        .validate(statusCode: endpoint.acceptableStatusCodes)
        .serializingDecodable(type, automaticallyCancelling: true, decoder: decoder)

        let response = await dataTask.response

        switch response.result {
        case let .success(value):
            return value
        case let .failure(afError):
            throw APIError.from(afError)
        }
    }

    /// A lower-level upload method mirroring the Safeguard
    /// `APIService.dispatchUpload` signature.
    public func dispatchUpload<R: Codable & Sendable>(
        httpMethod: HTTPMethod,
        endPoint: String,
        contentType: String = "image/jpeg",
        resultType: R.Type,
        payload: Data,
        fileName: String,
        parameters: [String: String]
    ) async throws -> R {
        let headers: HTTPHeaders = [
            "Accept": "application/json",
        ]

        let dataTask = session.upload(
            multipartFormData: { multipartFormData in
                for (key, value) in parameters {
                    if let data = value.data(using: .utf8) {
                        multipartFormData.append(data, withName: key)
                    }
                }
                multipartFormData.append(payload, withName: "file", fileName: fileName, mimeType: contentType)
            },
            to: endPoint,
            method: httpMethod,
            headers: headers
        )
        .validate(statusCode: 200..<201)
        .serializingDecodable(resultType, automaticallyCancelling: true, decoder: decoder)

        let response = await dataTask.response

        switch response.result {
        case let .success(value):
            return value
        case let .failure(afError):
            throw APIError.from(afError)
        }
    }

    // MARK: - Text Response

    /// Fetches a plain-text response from the given endpoint.
    public func requestText(_ endpoint: some APIEndpoint) async throws -> String {
        let urlRequest = try buildURLRequest(for: endpoint, contentType: "text/plain")

        do {
            let value = try await session.request(urlRequest)
                .serializingString()
                .value
            return value
        } catch let afError as AFError {
            throw APIError.from(afError)
        } catch {
            throw APIError.from(error)
        }
    }

    /// A lower-level text dispatch mirroring the Safeguard
    /// `APIService.dispatchText` signature.
    public func dispatchText(
        httpMethod: HTTPMethod,
        endPoint: String,
        timeoutIntervalInSeconds: Int? = nil
    ) async throws -> String {
        let url = URL(string: endPoint)!
        var urlRequest = URLRequest(url: url)
        urlRequest.method = httpMethod
        urlRequest.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = TimeInterval(
            timeoutIntervalInSeconds ?? Int(environment.timeoutInterval)
        )

        do {
            let value = try await session.request(urlRequest)
                .serializingString()
                .value
            return value
        } catch let afError as AFError {
            throw APIError.from(afError)
        } catch {
            throw APIError.from(error)
        }
    }

    // MARK: - Private

    private func buildURLRequest(
        for endpoint: some APIEndpoint,
        contentType: String? = nil
    ) throws -> URLRequest {
        let url = endpoint.url(relativeTo: environment.baseURL)
        var urlRequest = URLRequest(url: url)
        urlRequest.method = endpoint.method
        urlRequest.timeoutInterval = environment.timeoutInterval

        // Headers
        let ct = contentType ?? endpoint.contentType
        urlRequest.setValue(ct, forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        if let endpointHeaders = endpoint.headers {
            for header in endpointHeaders {
                urlRequest.setValue(header.value, forHTTPHeaderField: header.name)
            }
        }

        // Body
        if let body = endpoint.body {
            urlRequest.httpBody = try encoder.encode(body)
        }

        return urlRequest
    }
}
