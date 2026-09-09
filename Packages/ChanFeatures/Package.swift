// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChanFeatures",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ChanFeatures", targets: ["ChanFeatures"]),
    ],
    dependencies: [
        .package(path: "../ChanCore"),
        .package(path: "../ChanAPI"),
        .package(path: "../ChanDB"),
        .package(path: "../ChanMedia"),
        .package(path: "../ChanUI"),
    ],
    targets: [
        .target(
            name: "ChanFeatures",
            dependencies: [
                .product(name: "ChanCore", package: "ChanCore"),
                .product(name: "ChanAPI", package: "ChanAPI"),
                .product(name: "ChanDB", package: "ChanDB"),
                .product(name: "ChanMedia", package: "ChanMedia"),
                .product(name: "ChanUI", package: "ChanUI"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
