//
//  AuthInterceptor.swift
//  SwiftAPIService
//
//  Created by Gustavo Silva.
//

import Alamofire
import Foundation

/// An Alamofire `RequestInterceptor` that:
///
/// 1. **Adapts** every request by attaching the current access token
///    as a `Bearer` authorization header.
/// 2. **Retries** requests that fail with a 401 status code by
///    refreshing the access token exactly once, then replaying the
///    original request.
///
/// Thread-safety is guaranteed by the underlying `TokenStore` actor
/// and a local lock that coalesces concurrent refresh attempts into
/// a single network call.
public final class AuthInterceptor: RequestInterceptor, @unchecked Sendable {

    // MARK: - Properties

    private let tokenStore: TokenStore
    private let refreshProvider: TokenRefreshProvider
    private let maxRetryCount: Int

    /// Guards the refresh flow so only one refresh runs at a time.
    private let lock = NSLock()
    private var isRefreshing = false
    private var pendingRetries: [(RetryResult) -> Void] = []

    // MARK: - Init

    /// Creates a new interceptor.
    ///
    /// - Parameters:
    ///   - tokenStore: The actor-based token store.
    ///   - refreshProvider: An object that knows how to call the refresh endpoint.
    ///   - maxRetryCount: Maximum number of retries per request (default `1`).
    public init(
        tokenStore: TokenStore,
        refreshProvider: TokenRefreshProvider,
        maxRetryCount: Int = 1
    ) {
        self.tokenStore = tokenStore
        self.refreshProvider = refreshProvider
        self.maxRetryCount = maxRetryCount
    }

    // MARK: - RequestAdapter

    public func adapt(
        _ urlRequest: URLRequest,
        for session: Session,
        completion: @escaping (Result<URLRequest, any Error>) -> Void
    ) {
        // Capture as nonisolated(unsafe) to satisfy Swift 6's strict
        // concurrency check — the underlying Alamofire contract
        // guarantees this closure is called exactly once.
        nonisolated(unsafe) let completion = completion
        Task {
            var request = urlRequest
            if let token = await tokenStore.accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            completion(.success(request))
        }
    }

    // MARK: - RequestRetrier

    public func retry(
        _ request: Request,
        for session: Session,
        dueTo error: any Error,
        completion: @escaping (RetryResult) -> Void
    ) {
        // Only retry on 401 and within the retry limit.
        guard let response = request.task?.response as? HTTPURLResponse,
              response.statusCode == 401,
              request.retryCount < maxRetryCount
        else {
            completion(.doNotRetry)
            return
        }

        lock.lock()

        // If a refresh is already in flight, queue this completion.
        if isRefreshing {
            pendingRetries.append(completion)
            lock.unlock()
            return
        }

        isRefreshing = true
        pendingRetries.append(completion)
        lock.unlock()

        // Perform the refresh.
        Task { [weak self] in
            guard let self else { return }

            do {
                try await refreshCredential()

                self.completeAllPending(with: .retry)
            } catch {
                await tokenStore.clear()
                self.completeAllPending(with: .doNotRetryWithError(
                    APIError(kind: .tokenRefreshFailed, details: "Token refresh failed",
                             technicalDetails: [error.localizedDescription])
                ))
            }
        }
    }

    // MARK: - Private

    /// Performs a single refresh-token exchange and stores the new credential.
    public func refreshCredential() async throws {
        guard let credential = await tokenStore.credential else {
            throw APIError(kind: .tokenRefreshFailed, details: "No refresh token available")
        }
        let newCredential = try await refreshProvider.refresh(using: credential.refreshToken)
        await tokenStore.store(newCredential)
    }

    private func completeAllPending(with result: RetryResult) {
        lock.lock()
        let completions = pendingRetries
        pendingRetries.removeAll()
        isRefreshing = false
        lock.unlock()

        for completion in completions {
            completion(result)
        }
    }
}
