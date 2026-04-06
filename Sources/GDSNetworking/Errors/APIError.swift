//
//  APIError.swift
//  GDSNetworking
//
//  Created by Gustavo Silva.
//

import Alamofire
import Foundation

/// Severity levels for API errors, modeled after the Safeguard `ErrorSeverity`.
public enum APIErrorSeverity: Int, Sendable {
    case info = 1
    case warning = 2
    case error = 3
    case ignore = 4
}

/// A structured, typed error produced by the networking layer.
///
/// Maps directly from Alamofire errors, HTTP status codes,
/// decoding failures, and authentication issues.
public struct APIError: Error, Sendable, CustomStringConvertible {

    // MARK: - Kind

    /// The category of error that occurred.
    public enum Kind: Sendable {
        /// The server returned an unexpected HTTP status code.
        case httpError(statusCode: Int)
        /// The response body could not be decoded into the expected type.
        case decodingError
        /// The network request timed out.
        case timeout
        /// No network connectivity.
        case noConnection
        /// The access token is missing or the refresh failed.
        case unauthorized
        /// Token refresh failed after retry.
        case tokenRefreshFailed
        /// A server-side error (5xx).
        case serverError(statusCode: Int)
        /// The request was explicitly cancelled.
        case cancelled
        /// An error originating from Alamofire.
        case alamofireError(AFError)
        /// Any other unclassified error.
        case unknown(Error)
    }

    // MARK: - Properties

    /// The specific kind of error.
    public let kind: Kind

    /// A human-readable summary suitable for display.
    public var details: String

    /// Technical details useful for debugging / logging.
    public var technicalDetails: [String]

    /// Optional HTTP status code when applicable.
    public var statusCode: Int?

    /// The severity of this error.
    public var severity: APIErrorSeverity

    /// Timestamp when the error was created.
    public let timestamp: Date

    // MARK: - Init

    public init(
        kind: Kind,
        details: String = "An error occurred",
        technicalDetails: [String] = [],
        statusCode: Int? = nil,
        severity: APIErrorSeverity = .error
    ) {
        self.kind = kind
        self.details = details
        self.technicalDetails = technicalDetails
        self.statusCode = statusCode
        self.severity = severity
        self.timestamp = Date()
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        var parts = ["[\(severity)] \(details)"]
        if let code = statusCode {
            parts.append("HTTP \(code)")
        }
        if !technicalDetails.isEmpty {
            parts.append(contentsOf: technicalDetails)
        }
        return parts.joined(separator: " | ")
    }
}

// MARK: - Factory helpers

public extension APIError {

    /// Create an `APIError` from an `AFError`.
    static func from(_ afError: AFError) -> APIError {
        let statusCode = afError.responseCode

        if afError.isSessionTaskError,
           let urlError = afError.underlyingError as? URLError {
            switch urlError.code {
            case .timedOut:
                return APIError(
                    kind: .timeout,
                    details: "The request timed out",
                    technicalDetails: [urlError.localizedDescription],
                    statusCode: statusCode
                )
            case .notConnectedToInternet, .networkConnectionLost:
                return APIError(
                    kind: .noConnection,
                    details: "No network connection",
                    technicalDetails: [urlError.localizedDescription],
                    statusCode: statusCode
                )
            case .cancelled:
                return APIError(
                    kind: .cancelled,
                    details: "Request cancelled",
                    technicalDetails: [urlError.localizedDescription],
                    statusCode: statusCode,
                    severity: .ignore
                )
            default:
                break
            }
        }

        if afError.isResponseValidationError, let code = statusCode {
            if code == 401 {
                return APIError(
                    kind: .unauthorized,
                    details: "Authentication required",
                    technicalDetails: [afError.localizedDescription],
                    statusCode: code
                )
            }
            if (500...599).contains(code) {
                return APIError(
                    kind: .serverError(statusCode: code),
                    details: "Server error",
                    technicalDetails: [afError.localizedDescription],
                    statusCode: code
                )
            }
            return APIError(
                kind: .httpError(statusCode: code),
                details: "HTTP error",
                technicalDetails: [afError.localizedDescription],
                statusCode: code
            )
        }

        if afError.isResponseSerializationError {
            return APIError(
                kind: .decodingError,
                details: "Failed to decode response",
                technicalDetails: [afError.localizedDescription],
                statusCode: statusCode
            )
        }

        return APIError(
            kind: .alamofireError(afError),
            details: "API Error",
            technicalDetails: [afError.localizedDescription],
            statusCode: statusCode
        )
    }

    /// Create an `APIError` from a generic `Error`.
    static func from(_ error: Error, details: String = "General Error") -> APIError {
        if let apiError = error as? APIError {
            return apiError
        }
        if let afError = error as? AFError {
            return .from(afError)
        }
        return APIError(
            kind: .unknown(error),
            details: details,
            technicalDetails: [error.localizedDescription]
        )
    }
}
