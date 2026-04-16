//
//  SwiftAPIService.swift
//  SwiftAPIService
//
//  Created by Gustavo Silva.
//

// Umbrella module — re-exports SwiftAPIAuth plus whichever
// optional modules are enabled via package traits.
// Existing `import SwiftAPIService` statements continue to work
// unchanged when the default traits are enabled.
@_exported import SwiftAPIAuth

#if Networking
@_exported import SwiftAPICore
#endif

#if OIDC
@_exported import SwiftAPIOIDC
#endif
