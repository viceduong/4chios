// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChanAPI",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ChanAPI", targets: ["ChanAPI"]),
    ],
    dependencies: [
        .package(path: "../ChanCore"),
    ],
    targets: [
        .target(name: "ChanAPI", dependencies: [.product(name: "ChanCore", package: "ChanCore")]),
        .testTarget(name: "ChanAPITests", dependencies: ["ChanAPI"]),
    ],
    swiftLanguageVersions: [.v5]
)
