// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftAPIService",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        // Individual modules
        .library(name: "SwiftAPICore", targets: ["SwiftAPICore"]),
        .library(name: "SwiftAPIOIDC", targets: ["SwiftAPIOIDC"]),
        // Combined — backward compatible
        .library(name: "SwiftAPIService", targets: ["SwiftAPIService"]),
    ],
    traits: [
        .default(enabledTraits: ["Networking", "OIDC"]),
        .trait(name: "Networking", description: "Alamofire-based HTTP networking client"),
        .trait(name: "OIDC", description: "OIDC authentication via AppAuth"),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.0"),
        .package(url: "https://github.com/openid/AppAuth-iOS.git", from: "1.7.0"),
    ],
    targets: [
        // Shared auth primitives (no external deps)
        .target(
            name: "SwiftAPIAuth",
            dependencies: [],
            path: "Sources/SwiftAPIAuth"
        ),
        // API networking + generic auth middleware
        .target(
            name: "SwiftAPICore",
            dependencies: ["Alamofire", "SwiftAPIAuth"],
            path: "Sources/SwiftAPICore"
        ),
        // OIDC authentication (no Alamofire)
        .target(
            name: "SwiftAPIOIDC",
            dependencies: [
                .product(name: "AppAuth", package: "AppAuth-iOS"),
                "SwiftAPIAuth",
            ],
            path: "Sources/SwiftAPIOIDC"
        ),
        // Umbrella (backward compatible)
        .target(
            name: "SwiftAPIService",
            dependencies: [
                "SwiftAPIAuth",
                .target(name: "SwiftAPICore", condition: .when(traits: ["Networking"])),
                .target(name: "SwiftAPIOIDC", condition: .when(traits: ["OIDC"])),
            ],
            path: "Sources/SwiftAPIService"
        ),
        // Tests
        .testTarget(
            name: "SwiftAPIServiceTests",
            dependencies: ["SwiftAPIService", "SwiftAPICore", "SwiftAPIOIDC"],
            path: "Tests/SwiftAPIServiceTests"
        ),
    ]
)
