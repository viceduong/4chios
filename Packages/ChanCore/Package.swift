// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChanCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ChanCore", targets: ["ChanCore"]),
    ],
    targets: [
        .target(name: "ChanCore"),
        .testTarget(name: "ChanCoreTests", dependencies: ["ChanCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
