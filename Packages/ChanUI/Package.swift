// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChanUI",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ChanUI", targets: ["ChanUI"]),
    ],
    dependencies: [
        .package(path: "../ChanCore"),
    ],
    targets: [
        .target(name: "ChanUI", dependencies: [.product(name: "ChanCore", package: "ChanCore")]),
    ],
    swiftLanguageVersions: [.v5]
)
