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
        .package(url: "https://github.com/kaishin/Gifu.git", "3.4.0"..<"4.0.0"),
        .package(url: "https://github.com/MobileVLCKit-SPM/MobileVLCKit-SPM", from: "3.7.3"),
    ],
    targets: [
        .target(
            name: "ChanMedia",
            dependencies: [
                .product(name: "ChanCore", package: "ChanCore"),
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "NukeUI", package: "Nuke"),
                .product(name: "Gifu", package: "Gifu"),
                .product(name: "MobileVLCKit", package: "MobileVLCKit-SPM"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
