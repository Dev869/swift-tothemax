// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RateKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "RateKit", targets: ["RateKit"])
    ],
    targets: [
        .target(name: "RateKit"),
        .testTarget(
            name: "RateKitTests",
            dependencies: ["RateKit"]
        ),
    ]
)
