import ChanCore
import ChanFeatures
import ChanUI
import XCTest
@testable import Ch4ios

final class AppInfoTests: XCTestCase {
    func testDisplayName() {
        XCTAssertEqual(AppInfo.displayName, "4chios")
    }

    func testVersionMetadataIsPresent() {
        XCTAssertFalse(AppInfo.marketingVersion.isEmpty)
        XCTAssertFalse(AppInfo.buildNumber.isEmpty)
    }

    func testBundleIdentifier() {
        XCTAssertEqual(AppInfo.bundleIdentifier, "com.viceduong.ch4ios")
    }
}

/// Compiles the whole module graph in the iOS SDK and asserts the layers are linked.
@MainActor
final class ModuleGraphTests: XCTestCase {
    func testCoreIsLinked() {
        XCTAssertEqual(ChanVersion.current, "0.10.3")
        XCTAssertEqual(ChanVersion.schemaVersion, 8)
    }

    func testDesignSystemIsLinked() {
        XCTAssertNotEqual(ChanTheme.light.background, ChanTheme.dark.background)
        XCTAssertGreaterThan(ChanSpacing.xl, ChanSpacing.l)
    }

    func testFeatureLayerIsLinked() {
        let settings = ChanSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        XCTAssertEqual(settings.fontSize, 15)
        XCTAssertEqual(settings.themeMode, .system)
        XCTAssertEqual(settings.theme(for: .dark).background, ChanTheme.dark.background)
        XCTAssertEqual(settings.theme(for: .light).background, ChanTheme.light.background)
    }

    func testFormatting() {
        XCTAssertEqual(ChanFormat.count(999), "999")
        XCTAssertEqual(ChanFormat.count(1500), "1.5k")
        XCTAssertEqual(ChanFormat.bytes(2048), "2.0 KB")
    }
}
