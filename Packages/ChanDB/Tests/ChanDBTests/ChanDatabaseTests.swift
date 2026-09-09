import ChanCore
import XCTest
@testable import ChanDB

final class ChanDatabaseTests: XCTestCase {
    func testSchemaVersionTracksCore() {
        XCTAssertEqual(ChanDatabase.schemaVersion, ChanVersion.schemaVersion)
    }

    func testDefaultURLLivesInChanDBDirectory() throws {
        let url = try ChanDatabase.defaultURL()
        XCTAssertEqual(url.lastPathComponent, ChanDatabase.fileName)
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "ChanDB")
        // The directory must exist after `defaultURL()` returns.
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }
}
