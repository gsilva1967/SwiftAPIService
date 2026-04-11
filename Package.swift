// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftAPIService",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "SwiftAPIService",
            targets: ["SwiftAPIService"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.0"),
        .package(url: "https://github.com/openid/AppAuth-iOS.git", from: "1.7.0"),
    ],
    targets: [
        .target(
            name: "SwiftAPIService",
            dependencies: [
                "Alamofire",
                .product(name: "AppAuth", package: "AppAuth-iOS"),
            ],
            path: "Sources/SwiftAPIService"
        ),
        .testTarget(
            name: "SwiftAPIServiceTests",
            dependencies: ["SwiftAPIService"],
            path: "Tests/SwiftAPIServiceTests"
        ),
    ]
)
