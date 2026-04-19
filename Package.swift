// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "github-access-vapor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GitHubAccessVapor", targets: ["GitHubAccessVapor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: Version(1,10,0)),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: Version(1,8,0)),
        .package(url: "https://github.com/vapor/swift-openapi-vapor", from: Version(1,0,0)),
        .package(url: "https://github.com/vapor/vapor.git", from: Version(4,0,0)),
        .package(url: "https://github.com/vapor/jwt.git", from: Version(5,0,0))
    ],
    targets: [
        .target(
            name: "GitHubAccessVapor",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIVapor", package: "swift-openapi-vapor"),
                .product(name: "JWT", package: "jwt")
            ],
            plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),
        .testTarget(
            name: "GitHubAccessVaporTests",
            dependencies: ["GitHubAccessVapor"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
