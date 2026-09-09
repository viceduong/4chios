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
    ],
    targets: [
        .target(name: "ChanMedia", dependencies: [.product(name: "ChanCore", package: "ChanCore")]),
        .testTarget(name: "ChanMediaTests", dependencies: ["ChanMedia"]),
    ],
    swiftLanguageVersions: [.v5]
)
