// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "github-access-vapor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GitHubAccessVapor", targets: ["GitHubAccessVapor"]),
        .library(name: "GitHubAccessVaporTesting", targets: ["GitHubAccessVaporTesting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: Version(1,10,0)),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: Version(1,8,0)),
        .package(url: "https://github.com/vapor/swift-openapi-vapor", from: Version(1,0,0)),
        .package(url: "https://github.com/vapor/vapor.git", from: Version(4,0,0)),
        .package(url: "https://github.com/vapor/jwt.git", from: Version(5,0,0)),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: Version(1,0,0)),
        .package(url: "https://github.com/apple/swift-crypto.git", Version(3,0,0)..<Version(5,0,0)),
        // Platform-neutral GitHub App models shared with the clients. Pinned to a branch until the
        // models are released; switch to a version requirement then.
        .package(url: "https://github.com/NVMNovem/github-access-api.git", from: "1.0.1")
    ],
    targets: [
        .target(
            name: "GitHubAccessVapor",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIVapor", package: "swift-openapi-vapor"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "GitHubAccessModels", package: "github-access-api")
            ],
            plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),
        .target(
            name: "GitHubAccessVaporTesting",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "GitHubAccessModels", package: "github-access-api")
            ]
        ),
        .testTarget(
            name: "GitHubAccessVaporTests",
            dependencies: [
                "GitHubAccessVapor",
                "GitHubAccessVaporTesting",
                .product(name: "VaporTesting", package: "vapor")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
