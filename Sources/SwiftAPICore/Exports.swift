//
//  Exports.swift
//  SwiftAPICore
//
//  Created by Gustavo Silva.
//

// Re-export Alamofire so consumers don't need a direct dependency
// for common types like HTTPMethod, HTTPHeaders, etc.
@_exported import Alamofire

// Re-export SwiftAPIAuth so consumers automatically get access to
// TokenStore, AuthCredential, KeychainService, and TokenRefreshProvider.
@_exported import SwiftAPIAuth
