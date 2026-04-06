//
//  SSEError.swift
//  SwiftAPIService
//

import Foundation

/// Errors produced by SSE streaming operations.
public enum SSEError: Error, Sendable, CustomStringConvertible {
    case invalidResponse
    case unacceptableStatusCode(Int)
    case invalidContentType(String?)
    case invalidRetryField(String)
    case streamClosed
    case unauthorized
    case maxReconnectAttemptsReached
    case underlying(String)

    public var description: String {
        switch self {
        case .invalidResponse:
            return "The SSE endpoint returned an invalid response."
        case let .unacceptableStatusCode(code):
            return "The SSE endpoint returned an unacceptable status code: \(code)."
        case let .invalidContentType(contentType):
            return "Expected text/event-stream but got \(contentType ?? "unknown")."
        case let .invalidRetryField(value):
            return "Invalid SSE retry field: \(value)."
        case .streamClosed:
            return "The SSE stream was closed."
        case .unauthorized:
            return "Unauthorized SSE connection."
        case .maxReconnectAttemptsReached:
            return "Maximum SSE reconnect attempts reached."
        case let .underlying(message):
            return message
        }
    }
}
