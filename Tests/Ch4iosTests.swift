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
