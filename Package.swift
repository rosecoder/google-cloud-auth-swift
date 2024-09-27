// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "google-cloud-auth",
    platforms: [
       .macOS("13.0"),
    ],
    products: [
        .library(name: "GoogleCloudAuth", targets: ["GoogleCloudAuth"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.54.0"),
        .package(url: "https://github.com/rosecoder/retryable-task.git", from: "1.1.2"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.10.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0-rc.2"),
    ],
    targets: [
        .target(
            name: "GoogleCloudAuth",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "RetryableTask", package: "retryable-task"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "JWTKit", package: "jwt-kit")
            ]
        ),
        .testTarget(name: "GoogleCloudAuthTests", dependencies: ["GoogleCloudAuth"]),
    ]
)
