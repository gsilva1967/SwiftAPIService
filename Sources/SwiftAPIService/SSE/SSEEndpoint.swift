//
//  SSEEndpoint.swift
//  SwiftAPIService
//

import Alamofire
import Foundation

/// Describes an endpoint that serves Server-Sent Events.
public protocol SSEEndpoint: APIEndpoint {
    /// Whether to automatically reconnect when the stream disconnects.
    var shouldReconnect: Bool { get }
}

public extension SSEEndpoint {
    var method: HTTPMethod { .get }
    var contentType: String { "text/event-stream" }
    var acceptableStatusCodes: Range<Int> { 200..<300 }
    var shouldReconnect: Bool { true }
}
