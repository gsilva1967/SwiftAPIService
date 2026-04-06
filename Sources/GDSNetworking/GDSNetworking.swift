//
//  GDSNetworking.swift
//  GDSNetworking
//
//  Created by Gustavo Silva.
//

// Re-export Alamofire so consumers don't need a direct dependency
// for common types like HTTPMethod, HTTPHeaders, etc.
@_exported import Alamofire

// This file intentionally left minimal.
// All public API surface is exposed through individual source files:
//
//  Configuration/
//    - APIEnvironment
//
//  Endpoint/
//    - APIEndpoint
//
//  Client/
//    - APIClient
//
//  Auth/
//    - AuthCredential, TokenStore
//    - AuthInterceptor
//    - TokenRefreshProvider
//
//  Security/
//    - KeychainService
//
//  Errors/
//    - APIError, APIErrorSeverity
//
//  Logging/
//    - APILogger, APILogLevel
