import XCTest
@testable import ChanCore

final class PostGraphTests: XCTestCase {
    private func post(_ no: Int, op: Int = 0, quoting targets: [Int] = [], subject: String? = nil) -> Post {
        let comment = targets
            .map { "<a href=\"#p\($0)\" class=\"quotelink\">&gt;&gt;\($0)</a>" }
            .joined(separator: "<br>")
        return Post(
            no: PostNumber(no),
            resto: PostNumber(op),
            time: Date(timeIntervalSince1970: TimeInterval(no)),
            subject: subject,
            commentHTML: comment
        )
    }

    /// 1 (OP) ← 2 ← 4, and 1 ← 3.   2 ← 5, 4 ← 5 (multiple quotes)
    private func sampleGraph() -> PostGraph {
        var graph = PostGraph()
        graph.reset(with: [
            post(1, subject: "OP"),
            post(2, op: 1, quoting: [1]),
            post(3, op: 1, quoting: [1]),
            post(4, op: 1, quoting: [2]),
            post(5, op: 1, quoting: [2, 4]),
        ])
        return graph
    }

    func testRecordsQuotesAndBacklinks() {
        let graph = sampleGraph()
        XCTAssertEqual(graph.quoted(by: PostNumber(5)), [PostNumber(2), PostNumber(4)])
        XCTAssertEqual(graph.replies(to: PostNumber(1)), [PostNumber(2), PostNumber(3)])
        XCTAssertEqual(graph.replies(to: PostNumber(4)), [PostNumber(5)])
        XCTAssertEqual(graph.replyCount(of: PostNumber(2)), 2)
        XCTAssertTrue(graph.replies(to: PostNumber(99)).isEmpty)
    }

    func testDuplicateQuotesAreCollapsed() {
        var graph = PostGraph()
        graph.reset(with: [
            post(1, subject: "OP"),
            post(2, op: 1, quoting: [1, 1, 1]),
        ])
        XCTAssertEqual(graph.quoted(by: PostNumber(2)), [PostNumber(1)])
        XCTAssertEqual(graph.replies(to: PostNumber(1)), [PostNumber(2)])
    }

    func testOPDetection() {
        let graph = sampleGraph()
        XCTAssertEqual(graph.opNumber, PostNumber(1))
        XCTAssertTrue(graph.isOP(PostNumber(1)))
        XCTAssertFalse(graph.isOP(PostNumber(2)))
    }

    func testPreferredParentPrefersTheMostRecentQuote() {
        let graph = sampleGraph()
        XCTAssertEqual(graph.preferredParent(of: PostNumber(5)), PostNumber(4))
    }

    func testChainIsRootFirstAndCycleSafe() {
        let graph = sampleGraph()
        XCTAssertEqual(graph.chain(to: PostNumber(5)), [PostNumber(1), PostNumber(2), PostNumber(4), PostNumber(5)])
        XCTAssertEqual(graph.chain(to: PostNumber(1)), [PostNumber(1)])

        // A post quoting a later post must not loop forever.
        var cyclic = PostGraph()
        cyclic.reset(with: [
            post(1, quoting: [10]),
            post(10, op: 1, quoting: [1]),
        ])
        XCTAssertLessThanOrEqual(cyclic.chain(to: PostNumber(1)).count, 3)
    }

    func testDescendantsAndDepth() {
        let graph = sampleGraph()
        XCTAssertEqual(graph.descendants(of: PostNumber(2)), [PostNumber(4), PostNumber(5)])
        XCTAssertEqual(graph.descendants(of: PostNumber(1)), [PostNumber(2), PostNumber(3), PostNumber(4), PostNumber(5)])
        XCTAssertEqual(graph.depth(of: PostNumber(1)), 3)
        XCTAssertEqual(graph.depth(of: PostNumber(5)), 0)
    }

    func testAnnotationsMarkOPAndUserPosts() {
        let graph = sampleGraph()
        let mine: Set<PostNumber> = [PostNumber(4)]
        XCTAssertEqual(graph.annotation(for: PostNumber(1), myPosts: mine), "OP")
        XCTAssertEqual(graph.annotation(for: PostNumber(4), myPosts: mine), "You")
        XCTAssertNil(graph.annotation(for: PostNumber(3), myPosts: mine))
        XCTAssertTrue(graph.quotesUser(PostNumber(5), myPosts: mine))
        XCTAssertFalse(graph.quotesUser(PostNumber(3), myPosts: mine))
    }

    func testIncrementalInsertMatchesFullRebuild() {
        let posts = [
            post(1, subject: "OP"),
            post(2, op: 1, quoting: [1]),
            post(3, op: 1, quoting: [2]),
        ]

        var incremental = PostGraph()
        for post in posts { incremental.insert(post) }

        var full = PostGraph()
        full.reset(with: posts)

        XCTAssertEqual(incremental.backlinks, full.backlinks)
        XCTAssertEqual(incremental.quotes, full.quotes)
        XCTAssertEqual(incremental.opNumber, full.opNumber)
    }

    func testReinsertingAPostDoesNotDuplicateBacklinks() {
        var graph = PostGraph()
        let original = post(2, op: 1, quoting: [1])
        graph.reset(with: [post(1, subject: "OP"), original])
        graph.insert(original)
        graph.insert(original)
        XCTAssertEqual(graph.replies(to: PostNumber(1)), [PostNumber(2)])
    }
}
