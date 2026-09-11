import ChanCore
import XCTest

@testable import ChanAI

final class CatalogSummarizerTests: XCTestCase {
    private func thread(
        _ no: Int,
        subject: String? = nil,
        comment: String = "",
        replies: Int? = nil,
        images: Int? = nil,
        sticky: Bool? = nil
    ) -> Post {
        Post(
            no: PostNumber(no),
            resto: PostNumber(0),
            time: Date(timeIntervalSince1970: 0),
            subject: subject,
            commentHTML: comment,
            replies: replies,
            images: images,
            isSticky: sticky
        )
    }

    // MARK: - Digest

    func testDigestLineCarriesWhatIdentifiesAThread() {
        let line = CatalogSummarizer.digestLine(
            thread(42, subject: "GPU thread", comment: "<b>Post</b> your rigs", replies: 120, images: 33),
            openingLimit: 100
        )

        XCTAssertTrue(line.hasPrefix("#42"), line)
        XCTAssertTrue(line.contains("GPU thread"))
        XCTAssertTrue(line.contains("R:120 I:33"))
        XCTAssertTrue(line.contains("Post your rigs"), "markup is stripped")
        XCTAssertFalse(line.contains("<b>"))
    }

    func testDigestLineMarksStickyAndTruncatesTheBody() {
        let long = String(repeating: "x", count: 900)
        let line = CatalogSummarizer.digestLine(
            thread(7, comment: long, sticky: true),
            openingLimit: 50
        )

        XCTAssertTrue(line.contains("sticky"))
        XCTAssertTrue(line.count < 200, "the body is truncated, not sent whole")
    }

    func testDigestLineCollapsesNewlinesSoOneThreadIsOneLine() {
        let line = CatalogSummarizer.digestLine(
            thread(9, comment: "first<br>second<br>third"),
            openingLimit: 200
        )

        XCTAssertFalse(line.contains("\n"), "a row must stay on one line")
        XCTAssertTrue(line.contains("first second third"))
    }

    // MARK: - Chunking

    func testChunkingRespectsTheBudget() {
        let lines = (1...30).map { String(repeating: "a", count: 100) + "\($0)" }

        let chunks = CatalogSummarizer.chunks(lines, characterLimit: 500)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            let size = chunk.reduce(0) { $0 + $1.count + 1 }
            // One line over the budget is allowed only when it is alone.
            XCTAssertTrue(size <= 500 || chunk.count == 1, "part of \(size) chars")
        }
        XCTAssertEqual(chunks.flatMap { $0 }, lines, "nothing is lost or reordered")
    }

    func testASingleOversizedLineStillFormsItsOwnChunk() {
        let chunks = CatalogSummarizer.chunks([String(repeating: "z", count: 900)], characterLimit: 100)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 1)
    }

    // MARK: - Line parsing

    func testThreadLineAcceptsTheShapesAModelActuallyProduces() {
        XCTAssertEqual(CatalogSummarizer.threadLine("#12345678 - GPU prices")?.number, 12_345_678)
        XCTAssertEqual(CatalogSummarizer.threadLine("#12345678 - GPU prices")?.text, "GPU prices")
        XCTAssertEqual(CatalogSummarizer.threadLine("12345678: GPU prices")?.number, 12_345_678)
        XCTAssertEqual(CatalogSummarizer.threadLine("- #12345678 — GPU prices")?.number, 12_345_678)
        XCTAssertEqual(CatalogSummarizer.threadLine("**#12345678** - GPU")?.number, nil, "markdown bold is not a number")
        XCTAssertEqual(CatalogSummarizer.threadLine("* 12345678 - GPU prices")?.text, "GPU prices")
    }

    func testThreadLineRejectsProseAndShortNumbers() {
        XCTAssertNil(CatalogSummarizer.threadLine("The board is discussing GPUs"))
        XCTAssertNil(CatalogSummarizer.threadLine("#42 - too short to be a post number"))
        XCTAssertNil(CatalogSummarizer.threadLine("#12345678"))
        XCTAssertNil(CatalogSummarizer.threadLine("#12345678 - "))
    }

    // MARK: - Reply parsing

    func testParseSeparatesTheOverviewFromTheThreadLines() {
        let reply = """
        The board is arguing about GPU pricing again, with a long thread of benchmarks.

        THREADS:
        #10000001 - GPU price frustration
        #10000002 - benchmark results
        """

        let parsed = CatalogSummarizer.parse(reply, known: [10_000_001, 10_000_002, 10_000_003])

        XCTAssertEqual(parsed.overview, "The board is arguing about GPU pricing again, with a long thread of benchmarks.")
        XCTAssertEqual(parsed.threads.count, 2)
        XCTAssertEqual(parsed.threads[0].number, PostNumber(10_000_001))
        XCTAssertEqual(parsed.threads[0].line, "GPU price frustration")
    }

    func testParseIgnoresNumbersThatWereNeverInTheListing() {
        // The property that matters: a model cannot invent a thread.
        let reply = """
        A quiet board.

        THREADS:
        #10000001 - real thread
        #99999999 - hallucinated thread
        """

        let parsed = CatalogSummarizer.parse(reply, known: [10_000_001])

        XCTAssertEqual(parsed.threads.count, 1)
        XCTAssertEqual(parsed.threads[0].number, PostNumber(10_000_001))
    }

    func testParseDropsDuplicatesAndKeepsTheFirstLine() {
        let reply = """
        Overview.

        THREADS:
        #10000001 - first reading
        #10000001 - second reading
        """

        let parsed = CatalogSummarizer.parse(reply, known: [10_000_001])

        XCTAssertEqual(parsed.threads.count, 1)
        XCTAssertEqual(parsed.threads[0].line, "first reading")
    }

    func testParseHandlesAMissingThreadSection() {
        let parsed = CatalogSummarizer.parse("Just an overview, no list.", known: [10_000_001])

        XCTAssertEqual(parsed.overview, "Just an overview, no list.")
        XCTAssertTrue(parsed.threads.isEmpty)
    }

    func testParseDoesNotLeakThreadSectionProseIntoTheOverview() {
        let reply = """
        Overview paragraph.

        THREADS:
        #10000001 - named
        None of the others stood out.
        """

        let parsed = CatalogSummarizer.parse(reply, known: [10_000_001])

        XCTAssertEqual(parsed.overview, "Overview paragraph.")
        XCTAssertEqual(parsed.threads.count, 1)
    }

    func testParseFindsThreadLinesEvenWithoutTheLabel() {
        let reply = """
        The board is quiet.

        #10000001 - the only thread worth naming
        """

        let parsed = CatalogSummarizer.parse(reply, known: [10_000_001])

        XCTAssertEqual(parsed.overview, "The board is quiet.")
        XCTAssertEqual(parsed.threads.count, 1)
    }
}
