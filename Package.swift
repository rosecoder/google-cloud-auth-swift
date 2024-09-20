// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "google-cloud-auth",
    platforms: [
       .macOS("12.0"),
    ],
    products: [
        .library(name: "GoogleCloudAuth", targets: ["GoogleCloudAuth"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/rosecoder/retryable-task.git", from: "1.1.2"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.54.0"),
    ],
    targets: [
        .target(
            name: "GoogleCloudAuth",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "RetryableTask", package: "retryable-task"),
            ]
        ),
        .testTarget(name: "GoogleCloudAuthTests", dependencies: ["GoogleCloudAuth"]),
    ]
)
