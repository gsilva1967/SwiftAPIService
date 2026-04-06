//
//  SSEEvent.swift
//  SwiftAPIService
//

import Foundation

/// A parsed Server-Sent Event frame.
public struct SSEEvent: Sendable, Equatable {
    /// The event identifier used for reconnection continuity.
    public let id: String?

    /// The event type (`event:` field). `nil` implies the default event type.
    public let event: String?

    /// The message payload (`data:` field), with multiline data joined by `\n`.
    public let data: String

    /// Optional server-suggested reconnection delay in milliseconds (`retry:`).
    public let retry: Int?

    public init(
        id: String? = nil,
        event: String? = nil,
        data: String,
        retry: Int? = nil
    ) {
        self.id = id
        self.event = event
        self.data = data
        self.retry = retry
    }
}

public extension SSEEvent {
    /// Decodes the event `data` payload into a typed model.
    func decodeData<T: Decodable>(
        as type: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let bytes = Data(data.utf8)
        return try decoder.decode(type, from: bytes)
    }
}
