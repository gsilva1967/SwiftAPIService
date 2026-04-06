//
//  APILogger.swift
//  SwiftAPIService
//
//  Created by Gustavo Silva.
//

import Alamofire
import Foundation
import os.log

/// The verbosity level for the network logger.
public enum APILogLevel: Int, Sendable, Comparable {
    /// No logging at all.
    case none = 0
    /// Logs only errors and failures.
    case errors = 1
    /// Logs request URLs and status codes.
    case info = 2
    /// Logs full request / response details including headers and bodies.
    case verbose = 3

    public static func < (lhs: APILogLevel, rhs: APILogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// An Alamofire `EventMonitor` that outputs structured log messages
/// using Apple's `os.log` subsystem.
///
/// Attach to the `Session` via ``APIClient/Configuration``.
public final class APILogger: EventMonitor, @unchecked Sendable {

    public let queue = DispatchQueue(label: "com.gds.networking.logger", qos: .utility)

    private let level: APILogLevel
    private let logger: Logger

    /// Creates a new logger.
    ///
    /// - Parameters:
    ///   - level: The desired verbosity (default `.info`).
    ///   - subsystem: The `os.log` subsystem name.
    public init(level: APILogLevel = .info, subsystem: String = "com.gds.networking") {
        self.level = level
        self.logger = Logger(subsystem: subsystem, category: "API")
    }

    // MARK: - EventMonitor

    public func requestDidResume(_ request: Request) {
        guard level >= .info else { return }
        let method = request.request?.httpMethod ?? "?"
        let url = request.request?.url?.absoluteString ?? "unknown"
        logger.info("➡️ \(method) \(url)")

        if level >= .verbose {
            if let headers = request.request?.allHTTPHeaderFields {
                logger.debug("   Headers: \(headers)")
            }
            if let body = request.request?.httpBody,
               let bodyString = String(data: body, encoding: .utf8) {
                logger.debug("   Body: \(bodyString)")
            }
        }
    }

    public func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
        let statusCode = response.response?.statusCode ?? 0
        let url = request.request?.url?.absoluteString ?? "unknown"

        switch response.result {
        case .success:
            guard level >= .info else { return }
            logger.info("✅ \(statusCode) \(url)")
        case let .failure(error):
            guard level >= .errors else { return }
            logger.error("❌ \(statusCode) \(url) — \(error.localizedDescription)")
        }

        if level >= .verbose {
            if let metrics = response.metrics {
                let duration = metrics.taskInterval.duration
                logger.debug("   Duration: \(String(format: "%.3f", duration))s")
            }
            if let data = response.data,
               let body = String(data: data, encoding: .utf8) {
                logger.debug("   Response body: \(body.prefix(1024))")
            }
        }
    }
}
