// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RateKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "RateKit", targets: ["RateKit"])
    ],
    targets: [
        .target(name: "RateKit"),
        .testTarget(name: "RateKitTests", dependencies: ["RateKit"])
    ]
)
