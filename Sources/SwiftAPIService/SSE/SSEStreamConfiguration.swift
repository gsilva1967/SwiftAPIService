//
//  SSEStreamConfiguration.swift
//  SwiftAPIService
//

import Foundation

/// Runtime configuration for an SSE stream.
public struct SSEStreamConfiguration: Sendable, Equatable {
    /// Reconnection policy.
    public let retryStrategy: SSERetryStrategy

    /// Initial last event ID to send in `Last-Event-ID` header.
    public let lastEventID: String?

    /// Whether to validate that response content type is `text/event-stream`.
    public let validateContentType: Bool

    /// Request timeout used for establishing each connection.
    public let requestTimeout: TimeInterval?

    /// Number of unauthorized refresh retries before failing.
    public let unauthorizedRefreshRetryLimit: Int

    public init(
        retryStrategy: SSERetryStrategy = SSERetryStrategy(),
        lastEventID: String? = nil,
        validateContentType: Bool = true,
        requestTimeout: TimeInterval? = nil,
        unauthorizedRefreshRetryLimit: Int = 1
    ) {
        self.retryStrategy = retryStrategy
        self.lastEventID = lastEventID
        self.validateContentType = validateContentType
        self.requestTimeout = requestTimeout
        self.unauthorizedRefreshRetryLimit = max(unauthorizedRefreshRetryLimit, 0)
    }
}

struct SSEParser {
    private struct PendingEvent {
        var id: String?
        var event: String?
        var dataLines: [String] = []
        var retry: Int?
        var hasAnyField: Bool = false
    }

    private var pending = PendingEvent()

    mutating func consume(line: String) throws -> SSEEvent? {
        if line.isEmpty {
            return flushEvent()
        }

        if line.hasPrefix(":") {
            return nil
        }

        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let rawField = parts.first else { return nil }
        let field = String(rawField)
        let value = normalizeFieldValue(parts.count > 1 ? String(parts[1]) : "")

        switch field {
        case "event":
            pending.event = value
            pending.hasAnyField = true
        case "data":
            pending.dataLines.append(value)
            pending.hasAnyField = true
        case "id":
            pending.id = value
            pending.hasAnyField = true
        case "retry":
            if value.isEmpty {
                break
            }
            guard let parsed = Int(value), parsed >= 0 else {
                throw SSEError.invalidRetryField(value)
            }
            pending.retry = parsed
            pending.hasAnyField = true
        default:
            break
        }

        return nil
    }

    mutating func finish() -> SSEEvent? {
        flushEvent()
    }

    private mutating func flushEvent() -> SSEEvent? {
        guard pending.hasAnyField else { return nil }
        let event = SSEEvent(
            id: pending.id,
            event: pending.event,
            data: pending.dataLines.joined(separator: "\n"),
            retry: pending.retry
        )
        pending = PendingEvent()
        return event
    }

    private func normalizeFieldValue(_ raw: String) -> String {
        if raw.hasPrefix(" ") {
            return String(raw.dropFirst())
        }
        return raw
    }
}

actor SSEConnection {
    typealias RequestBuilder = @Sendable (_ lastEventID: String?) async throws -> URLRequest
    typealias RefreshAction = @Sendable () async -> Bool

    private let requestBuilder: RequestBuilder
    private let refreshAuth: RefreshAction?
    private let configuration: SSEStreamConfiguration
    private let shouldReconnect: Bool
    private let session: URLSession

    init(
        requestBuilder: @escaping RequestBuilder,
        refreshAuth: RefreshAction?,
        configuration: SSEStreamConfiguration,
        shouldReconnect: Bool,
        session: URLSession = .shared
    ) {
        self.requestBuilder = requestBuilder
        self.refreshAuth = refreshAuth
        self.configuration = configuration
        self.shouldReconnect = shouldReconnect
        self.session = session
    }

    nonisolated func makeStream() -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.run(continuation: continuation)
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func run(continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation) async {
        var reconnectAttempt = 0
        var unauthorizedRefreshAttempts = 0
        var lastEventID = configuration.lastEventID
        var lastServerRetryMs: Int?

        while !Task.isCancelled {
            do {
                var request = try await requestBuilder(lastEventID)
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                if let lastEventID {
                    request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
                }
                if let timeout = configuration.requestTimeout {
                    request.timeoutInterval = timeout
                }

                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw SSEError.invalidResponse
                }

                if http.statusCode == 401 {
                    let didRefresh = await attemptRefreshIfPossible(currentCount: unauthorizedRefreshAttempts)
                    if didRefresh {
                        unauthorizedRefreshAttempts += 1
                        continue
                    }
                    throw SSEError.unauthorized
                }

                guard (200..<300).contains(http.statusCode) else {
                    throw SSEError.unacceptableStatusCode(http.statusCode)
                }

                if configuration.validateContentType {
                    let contentType = http.value(forHTTPHeaderField: "Content-Type")
                    if let contentType, !contentType.lowercased().contains("text/event-stream") {
                        throw SSEError.invalidContentType(contentType)
                    }
                }

                reconnectAttempt = 0
                unauthorizedRefreshAttempts = 0
                var parser = SSEParser()

                for try await line in bytes.lines {
                    if Task.isCancelled {
                        throw CancellationError()
                    }
                    if let event = try parser.consume(line: line) {
                        if let id = event.id, !id.isEmpty {
                            lastEventID = id
                        }
                        if let retry = event.retry {
                            lastServerRetryMs = retry
                        }
                        continuation.yield(event)
                    }
                }

                if let trailing = parser.finish() {
                    if let id = trailing.id, !id.isEmpty {
                        lastEventID = id
                    }
                    if let retry = trailing.retry {
                        lastServerRetryMs = retry
                    }
                    continuation.yield(trailing)
                }

                if !shouldReconnect {
                    continuation.finish(throwing: SSEError.streamClosed)
                    return
                }
            } catch is CancellationError {
                continuation.finish()
                return
            } catch {
                guard shouldReconnect else {
                    continuation.finish(throwing: error)
                    return
                }

                guard configuration.retryStrategy.canRetry(attempt: reconnectAttempt) else {
                    continuation.finish(throwing: SSEError.maxReconnectAttemptsReached)
                    return
                }

                let delay = configuration.retryStrategy.nextDelayNanoseconds(
                    attempt: reconnectAttempt,
                    serverRetryMilliseconds: lastServerRetryMs
                )
                reconnectAttempt += 1
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    continuation.finish()
                    return
                }
            }
        }

        continuation.finish()
    }

    private func attemptRefreshIfPossible(currentCount: Int) async -> Bool {
        guard currentCount < configuration.unauthorizedRefreshRetryLimit else {
            return false
        }
        guard let refreshAuth else {
            return false
        }
        return await refreshAuth()
    }
}
