import ChanCore
import XCTest
@testable import ChanDB

final class ChanDatabaseTests: XCTestCase {
    func testSchemaVersionTracksCore() {
        XCTAssertEqual(ChanDatabase.schemaVersion, ChanVersion.schemaVersion)
    }

    func testDefaultURLUsesApplicationSupport() throws {
        let url = try ChanDatabase.defaultURL()
        XCTAssertEqual(url.lastPathComponent, ChanDatabase.fileName)
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "ChanDB")
        XCTAssertTrue(url.path.contains("Application Support") || url.path.contains("ApplicationSupport"))
    }
}
