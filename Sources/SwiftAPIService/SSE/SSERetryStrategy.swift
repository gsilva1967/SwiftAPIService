//
//  SSERetryStrategy.swift
//  SwiftAPIService
//

import Foundation

/// Reconnection policy for SSE streams.
public struct SSERetryStrategy: Sendable, Equatable {
    /// Initial reconnect delay in milliseconds.
    public let baseDelayMilliseconds: Int

    /// Maximum reconnect delay in milliseconds.
    public let maxDelayMilliseconds: Int

    /// Optional upper bound on reconnection attempts. `nil` means unlimited attempts.
    public let maxAttempts: Int?

    /// Jitter ratio applied to reduce reconnect stampedes (`0...1`).
    public let jitterRatio: Double

    public init(
        baseDelayMilliseconds: Int = 1_000,
        maxDelayMilliseconds: Int = 30_000,
        maxAttempts: Int? = nil,
        jitterRatio: Double = 0.1
    ) {
        self.baseDelayMilliseconds = baseDelayMilliseconds
        self.maxDelayMilliseconds = maxDelayMilliseconds
        self.maxAttempts = maxAttempts
        self.jitterRatio = min(max(jitterRatio, 0), 1)
    }

    func canRetry(attempt: Int) -> Bool {
        guard let maxAttempts else { return true }
        return attempt < maxAttempts
    }

    func nextDelayNanoseconds(attempt: Int, serverRetryMilliseconds: Int?) -> UInt64 {
        let base: Int
        if let serverRetryMilliseconds, serverRetryMilliseconds >= 0 {
            base = serverRetryMilliseconds
        } else {
            let exp = min(attempt, 10)
            let raw = baseDelayMilliseconds * Int(pow(2.0, Double(exp)))
            base = min(raw, maxDelayMilliseconds)
        }

        guard jitterRatio > 0 else {
            return UInt64(max(base, 0)) * 1_000_000
        }

        let jitterMax = Int(Double(base) * jitterRatio)
        let jitter = jitterMax > 0 ? Int.random(in: 0...jitterMax) : 0
        let finalMs = min(base + jitter, maxDelayMilliseconds)
        return UInt64(max(finalMs, 0)) * 1_000_000
    }
}
