// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChanAI",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ChanAI", targets: ["ChanAI"]),
    ],
    dependencies: [
        .package(path: "../ChanCore"),
        .package(path: "../ChanAPI"),
    ],
    targets: [
        .target(
            name: "ChanAI",
            dependencies: [
                .product(name: "ChanCore", package: "ChanCore"),
                .product(name: "ChanAPI", package: "ChanAPI"),
            ]
        ),
        .testTarget(name: "ChanAITests", dependencies: ["ChanAI"]),
    ],
    swiftLanguageVersions: [.v5]
)
