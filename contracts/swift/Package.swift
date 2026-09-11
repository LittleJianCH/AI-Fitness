// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FitnessContractCheck",
    platforms: [.macOS(.v13)],
    products: [.library(name: "ContractClient", targets: ["ContractClient"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.6.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.7.0"),
    ],
    targets: [
        .target(
            name: "ContractClient",
            dependencies: [.product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")],
            plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),
        .testTarget(name: "ContractClientTests", dependencies: ["ContractClient"]),
    ]
)
