// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChanMedia",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ChanMedia", targets: ["ChanMedia"]),
    ],
    dependencies: [
        .package(path: "../ChanCore"),
        .package(url: "https://github.com/kean/Nuke", from: "12.8.0"),
    ],
    targets: [
        .target(
            name: "ChanMedia",
            dependencies: [
                .product(name: "ChanCore", package: "ChanCore"),
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "NukeUI", package: "NukeUI"),
            ]
        ),
        .testTarget(name: "ChanMediaTests", dependencies: ["ChanMedia"]),
    ],
    swiftLanguageVersions: [.v5]
)
