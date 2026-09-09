import ChanCore
import XCTest
@testable import ChanAPI

final class ChanEndpointTests: XCTestCase {
    func testBoardsURL() {
        XCTAssertEqual(ChanEndpoint.boards.url.absoluteString, "https://a.4cdn.org/boards.json")
    }

    func testCatalogURL() {
        XCTAssertEqual(ChanEndpoint.catalog("g").url.absoluteString, "https://a.4cdn.org/g/catalog.json")
    }

    func testIndexURL() {
        XCTAssertEqual(ChanEndpoint.index("pol", page: 3).url.absoluteString, "https://a.4cdn.org/pol/3.json")
    }

    func testThreadAndTailURLs() {
        let thread = ChanEndpoint.thread("wsg", op: 1234567)
        XCTAssertEqual(thread.url.absoluteString, "https://a.4cdn.org/wsg/thread/1234567.json")

        let tail = ChanEndpoint.threadTail("wsg", op: 1234567)
        XCTAssertEqual(tail.url.absoluteString, "https://a.4cdn.org/wsg/thread/1234567-tail.json")
    }

    func testArchiveURL() {
        XCTAssertEqual(ChanEndpoint.archive("v").url.absoluteString, "https://a.4cdn.org/v/archive.json")
    }

    func testEveryEndpointUsesTheAPIHost() {
        let endpoints: [ChanEndpoint] = [
            .boards, .catalog("g"), .index("g", page: 1),
            .thread("g", op: 1), .threadTail("g", op: 1), .archive("g"),
        ]
        for endpoint in endpoints {
            XCTAssertEqual(endpoint.url.host, "a.4cdn.org", "wrong host for \(endpoint)")
        }
    }
}

final class ChanMediaURLTests: XCTestCase {
    func testThumbnailAndPreview() {
        XCTAssertEqual(
            ChanMediaURL.thumbnail(board: "g", tim: 1699999999999).absoluteString,
            "https://i.4cdn.org/g/1699999999999s.jpg"
        )
        XCTAssertEqual(
            ChanMediaURL.preview(board: "g", tim: 1699999999999).absoluteString,
            "https://i.4cdn.org/g/1699999999999m.jpg"
        )
    }

    func testFullAcceptsDotPrefixedAndBareExtensions() {
        let dotted = ChanMediaURL.full(board: "g", tim: 42, ext: ".webm")
        let bare = ChanMediaURL.full(board: "g", tim: 42, ext: "webm")
        XCTAssertEqual(dotted, bare)
        XCTAssertEqual(dotted.absoluteString, "https://i.4cdn.org/g/42.webm")
    }

    func testSpoilerImagesUseStaticHost() {
        XCTAssertEqual(
            ChanMediaURL.spoilerImage(board: "g").absoluteString,
            "https://s.4cdn.org/image/spoiler-g.png"
        )
        XCTAssertEqual(
            ChanMediaURL.customSpoilerImage(board: "g", index: 3).absoluteString,
            "https://s.4cdn.org/image/spoiler-g3.png"
        )
    }
}
