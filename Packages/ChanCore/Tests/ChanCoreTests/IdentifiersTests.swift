import XCTest
@testable import ChanCore

final class IdentifiersTests: XCTestCase {
    func testBoardIDRoundTripsAsBareString() throws {
        let board: BoardID = "g"
        let data = try JSONEncoder().encode(board)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"g\"")
        XCTAssertEqual(try JSONDecoder().decode(BoardID.self, from: data), board)
    }

    func testPostNumberRoundTripsAsBareInteger() throws {
        let post = PostNumber(123456789)
        let data = try JSONEncoder().encode(post)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "123456789")
        XCTAssertEqual(try JSONDecoder().decode(PostNumber.self, from: data), post)
    }

    func testPostNumbersAreComparable() {
        XCTAssertLessThan(PostNumber(10), PostNumber(11))
        XCTAssertEqual([PostNumber(3), PostNumber(1), PostNumber(2)].sorted().map(\.value), [1, 2, 3])
    }

    func testSchemaVersionMatchesDesign() {
        // Bump alongside every new migration; ChanDB cross-checks this value.
        XCTAssertEqual(ChanVersion.schemaVersion, 8)
    }
}
