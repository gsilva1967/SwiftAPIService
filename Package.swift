// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GDSNetworking",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "GDSNetworking",
            targets: ["GDSNetworking"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.0"),
    ],
    targets: [
        .target(
            name: "GDSNetworking",
            dependencies: ["Alamofire"],
            path: "Sources/GDSNetworking"
        ),
        .testTarget(
            name: "GDSNetworkingTests",
            dependencies: ["GDSNetworking"],
            path: "Tests/GDSNetworkingTests"
        ),
    ]
)
