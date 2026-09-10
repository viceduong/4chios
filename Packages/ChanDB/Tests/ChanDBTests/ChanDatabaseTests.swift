import ChanCore
import XCTest
@testable import ChanDB

final class ChanDatabaseTests: XCTestCase {
    private var database: ChanDatabase!

    override func setUpWithError() throws {
        database = try ChanDatabase(inMemory: true)
    }

    override func tearDown() {
        database = nil
    }

    // MARK: - Helpers

    private func post(
        _ no: Int,
        op: Int = 0,
        time: TimeInterval = 1_700_000_000,
        comment: String? = nil,
        subject: String? = nil,
        sticky: Bool? = nil,
        replies: Int? = nil,
        posterID: String? = nil
    ) -> Post {
        Post(
            no: PostNumber(no),
            resto: PostNumber(op),
            time: Date(timeIntervalSince1970: time),
            posterID: posterID,
            subject: subject,
            commentHTML: comment,
            replies: replies,
            lastModified: Date(timeIntervalSince1970: time),
            isSticky: sticky
        )
    }

    private func board(_ id: BoardID, _ title: String) -> Board {
        Board(board: id, title: title, wsBoard: true)
    }

    // MARK: - Boards

    func testBoardsRoundTripAndUpsert() throws {
        try database.save([board("g", "Technology"), board("v", "Video Games")])
        XCTAssertEqual(try database.boards().map(\.board), ["g", "v"])

        try database.save([board("g", "Technology (updated)")])
        let boards = try database.boards()
        XCTAssertEqual(boards.count, 2)
        XCTAssertEqual(boards.first { $0.board == "g" }?.title, "Technology (updated)")
        XCTAssertEqual(try database.boardCount(), 2)
    }

    // MARK: - Catalog and threads

    func testCatalogOrdersStickyThenBumped() throws {
        try database.saveCatalog(board: "g", posts: [
            post(1, time: 100, sticky: false),
            post(2, time: 300, sticky: false),
            post(3, time: 200, sticky: true),
        ])
        XCTAssertEqual(try database.catalog(board: "g").map(\.no), [PostNumber(3), PostNumber(2), PostNumber(1)])
    }

    func testThreadSaveAndTailAppend() throws {
        try database.saveThread(board: "g", op: 1, posts: [
            post(1, comment: "op"),
            post(2, op: 1, comment: "reply"),
        ])
        XCTAssertEqual(try database.posts(board: "g", op: 1).map(\.no), [PostNumber(1), PostNumber(2)])
        XCTAssertEqual(try database.lastPostNumber(board: "g", op: 1), PostNumber(2))

        try database.appendTail(board: "g", op: 1, posts: [post(3, op: 1, comment: "new")])
        XCTAssertEqual(try database.posts(board: "g", op: 1).map(\.no), [PostNumber(1), PostNumber(2), PostNumber(3)])
        XCTAssertEqual(try database.lastPostNumber(board: "g", op: 1), PostNumber(3))

        // A full refresh replaces the thread.
        try database.saveThread(board: "g", op: 1, posts: [post(1, comment: "op only")])
        XCTAssertEqual(try database.posts(board: "g", op: 1).map(\.no), [PostNumber(1)])
    }

    func testThreadMetadata() throws {
        try database.saveCatalog(board: "g", posts: [post(1, sticky: true, replies: 42)])
        let metadata = try XCTUnwrap(database.threadMetadata(board: "g", op: 1))
        XCTAssertEqual(metadata.replies, 42)
        XCTAssertTrue(metadata.isSticky)
        XCTAssertEqual(metadata.board, "g")
    }

    func testPruneThreadsRemovesStaleData() throws {
        try database.saveCatalog(board: "g", posts: [
            post(1, time: 100),
            post(2, time: 200),
            post(3, time: 300),
        ])
        try database.pruneThreads(board: "g", keeping: [1, 3])
        XCTAssertEqual(try database.catalog(board: "g").map(\.no), [PostNumber(3), PostNumber(1)])
    }

    // MARK: - User data

    func testBookmarks() throws {
        try database.addBookmark(board: "g", op: 1, note: "interesting")
        XCTAssertTrue(try database.isBookmarked(board: "g", op: 1))
        XCTAssertEqual(try database.bookmarks().first?.note, "interesting")

        try database.removeBookmark(board: "g", op: 1)
        XCTAssertFalse(try database.isBookmarked(board: "g", op: 1))
    }

    func testWatchlist() throws {
        try database.addWatch(board: "g", op: 1)
        XCTAssertTrue(try database.isWatched(board: "g", op: 1))
        XCTAssertEqual(try database.watchedThreads().first?.lastSeenReply, 0)

        try database.updateWatchProgress(board: "g", op: 1, replies: 12)
        XCTAssertEqual(try database.watchedThreads().first?.lastSeenReply, 12)
    }

    func testFiltersCRUD() throws {
        let saved = try database.saveFilter(
            ChanFilter(board: "g", kind: .keyword, pattern: "spam", action: .hidePost)
        )
        XCTAssertGreaterThan(saved.id, 0)

        var filters = try database.filters()
        XCTAssertEqual(filters.count, 1)
        XCTAssertEqual(filters[0].pattern, "spam")

        try database.saveFilter(
            ChanFilter(id: saved.id, board: "g", kind: .regex, pattern: "\\d+", action: .hideThread, enabled: false)
        )
        filters = try database.filters()
        XCTAssertEqual(filters[0].kind, .regex)
        XCTAssertFalse(filters[0].enabled)

        try database.deleteFilter(id: saved.id)
        XCTAssertTrue(try database.filters().isEmpty)
    }

    func testReadState() throws {
        XCTAssertNil(try database.lastRead(board: "g", op: 1))
        try database.setLastRead(board: "g", op: 1, postNumber: 55)
        XCTAssertEqual(try database.lastRead(board: "g", op: 1), PostNumber(55))
    }

    func testMeta() throws {
        try database.setMeta("value", forKey: "key")
        XCTAssertEqual(try database.meta(forKey: "key"), "value")

        try database.markCatalogSynced(board: "g", at: Date(timeIntervalSince1970: 123))
        XCTAssertEqual(try database.lastCatalogSync(board: "g"), Date(timeIntervalSince1970: 123))
    }

    // MARK: - Search

    func testFullTextSearchFindsPosts() throws {
        try database.saveThread(board: "g", op: 1, posts: [
            post(1, comment: "the quick brown fox"),
            post(2, op: 1, comment: "jumps over the lazy dog"),
        ])

        let hits = try database.search("lazy dog")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].post.no, PostNumber(2))
        XCTAssertEqual(hits[0].board, "g")

        XCTAssertEqual(try database.search("quic").count, 1, "prefix matching should work")
        XCTAssertTrue(try database.search("nonexistentterm").isEmpty)
        XCTAssertTrue(try database.search("   ").isEmpty)
        XCTAssertEqual(try database.indexedPostCount(), 2)
    }

    func testSearchRebuild() throws {
        try database.saveThread(board: "g", op: 1, posts: [post(1, comment: "hello world")])
        try database.rebuildSearchIndex()
        XCTAssertEqual(try database.search("hello").count, 1)
    }

    func testSchemaVersionTracksCore() {
        XCTAssertEqual(ChanDatabase.schemaVersion, ChanVersion.schemaVersion)
    }

    func testMyPostsAreTracked() throws {
        XCTAssertFalse(try database.isMyPost(board: "g", number: 42))
        XCTAssertTrue(try database.myPostNumbers(board: "g").isEmpty)

        try database.recordMyPost(board: "g", number: 42, thread: 1)
        try database.recordMyPost(board: "g", number: 43, thread: 7)
        // Re-recording is idempotent.
        try database.recordMyPost(board: "g", number: 42, thread: 1)

        XCTAssertTrue(try database.isMyPost(board: "g", number: 42))
        XCTAssertEqual(try database.myPostNumbers(board: "g"), [PostNumber(42), PostNumber(43)])
        XCTAssertTrue(try database.myPostNumbers(board: "v").isEmpty)

        try database.removeMyPost(board: "g", number: 42)
        XCTAssertEqual(try database.myPostNumbers(board: "g"), [PostNumber(43)])
    }

    func testMarkAsMineUpdatesThread() throws {
        try database.markAsMine(board: "g", number: 5, thread: 2)
        XCTAssertTrue(try database.isMyPost(board: "g", number: 5))
        try database.markAsMine(board: "g", number: 5, thread: 3)
        XCTAssertEqual(try database.myPostNumbers(board: "g"), [PostNumber(5)])
    }
}
