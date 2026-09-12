// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FitnessIOS",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "FitnessCore", targets: ["FitnessCore"])],
    dependencies: [
        .package(path: "../contracts/swift"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", exact: "1.0.2"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.7.0"),
        .package(url: "https://github.com/apple/swift-http-types", exact: "1.5.1"),
    ],
    targets: [
        .target(
            name: "FitnessCore",
            dependencies: [
                .product(name: "ContractClient", package: "swift"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(name: "FitnessCoreTests", dependencies: ["FitnessCore"]),
    ]
)
