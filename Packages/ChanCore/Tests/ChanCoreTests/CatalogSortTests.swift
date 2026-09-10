import XCTest
@testable import ChanCore

final class CatalogSortTests: XCTestCase {
    private func thread(
        _ no: Int,
        time: TimeInterval,
        bumped: TimeInterval? = nil,
        replies: Int = 0,
        images: Int = 0,
        sticky: Bool = false
    ) -> Post {
        Post(
            no: PostNumber(no),
            time: Date(timeIntervalSince1970: time),
            replies: replies,
            images: images,
            lastModified: bumped.map { Date(timeIntervalSince1970: $0) },
            isSticky: sticky
        )
    }

    /// Deliberately shuffled, and with no thread bumped more recently than its
    /// own creation except #3.
    private var catalog: [Post] {
        [
            thread(2, time: 200, bumped: 500, replies: 10, images: 1),
            thread(1, time: 100, bumped: 400, replies: 30, images: 2),
            thread(4, time: 400, bumped: 450, replies: 5, images: 9),
            thread(3, time: 300, bumped: 900, replies: 30, images: 0),
        ]
    }

    func testBumpOrderPinsStickyThenMostRecentlyBumped() {
        let posts = catalog + [thread(9, time: 50, bumped: 10, sticky: true)]
        XCTAssertEqual(CatalogSort.bumpOrder.sorted(posts).map(\.no.value), [9, 3, 2, 4, 1])
    }

    func testBumpOrderFallsBackToCreationTimeWhenNeverBumped() {
        let posts = [
            thread(1, time: 100),
            thread(2, time: 300),
            thread(3, time: 200),
        ]
        XCTAssertEqual(CatalogSort.bumpOrder.sorted(posts).map(\.no.value), [2, 3, 1])
    }

    func testNewestAndOldestUseCreationTime() {
        XCTAssertEqual(CatalogSort.newest.sorted(catalog).map(\.no.value), [4, 3, 2, 1])
        XCTAssertEqual(CatalogSort.oldest.sorted(catalog).map(\.no.value), [1, 2, 3, 4])
    }

    func testMostRepliesBreaksTiesOnPostNumber() {
        XCTAssertEqual(CatalogSort.mostReplies.sorted(catalog).map(\.no.value), [3, 1, 2, 4])
    }

    func testMostImages() {
        XCTAssertEqual(CatalogSort.mostImages.sorted(catalog).map(\.no.value), [4, 1, 2, 3])
    }

    func testEveryModeKeepsAllPosts() {
        for sort in CatalogSort.allCases {
            XCTAssertEqual(
                sort.sorted(catalog).count,
                catalog.count,
                "\(sort.rawValue) dropped threads"
            )
        }
    }

    func testSortingIsDeterministicForEqualThreads() {
        let tied = [
            thread(1, time: 100, replies: 5),
            thread(2, time: 100, replies: 5),
            thread(3, time: 100, replies: 5),
        ]
        for sort in CatalogSort.allCases {
            XCTAssertEqual(
                sort.sorted(tied).map(\.no.value),
                sort.sorted(tied.reversed()).map(\.no.value),
                "\(sort.rawValue) is order-dependent for tied threads"
            )
        }
    }

    func testLabelsAndIconsAreDefined() {
        for sort in CatalogSort.allCases {
            XCTAssertFalse(sort.label.isEmpty)
            XCTAssertFalse(sort.systemImage.isEmpty)
        }
    }

    func testRoundTripsThroughCodable() throws {
        let data = try JSONEncoder().encode(CatalogSort.mostReplies)
        XCTAssertEqual(try JSONDecoder().decode(CatalogSort.self, from: data), .mostReplies)
    }
}
