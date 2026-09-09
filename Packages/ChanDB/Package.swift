// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChanDB",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ChanDB", targets: ["ChanDB"]),
    ],
    dependencies: [
        .package(path: "../ChanCore"),
    ],
    targets: [
        .target(name: "ChanDB", dependencies: [.product(name: "ChanCore", package: "ChanCore")]),
        .testTarget(name: "ChanDBTests", dependencies: ["ChanDB"]),
    ],
    swiftLanguageVersions: [.v5]
)
