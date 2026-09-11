import XCTest
@testable import ChanCore

final class PostSearchTests: XCTestCase {
    private func post(
        _ no: Int,
        subject: String? = nil,
        comment: String? = nil,
        filename: String? = nil
    ) -> Post {
        Post(
            no: PostNumber(no),
            time: Date(timeIntervalSince1970: 0),
            subject: subject,
            commentHTML: comment,
            tim: filename == nil ? nil : no,
            filename: filename,
            ext: filename == nil ? nil : ".jpg"
        )
    }

    func testMatchesSubjectBodyAndFilename() {
        let subject = post(1, subject: "Rate my setup")
        let body = post(2, comment: "the UPS is loud")
        let file = post(3, filename: "rack-photo.jpg")

        XCTAssertTrue(PostSearch.matches(subject, query: "rate"))
        XCTAssertTrue(PostSearch.matches(body, query: "ups"))
        XCTAssertTrue(PostSearch.matches(file, query: "rack-photo"))
        XCTAssertFalse(PostSearch.matches(subject, query: "banana"))
    }

    func testIgnoresCaseAndDiacritics() {
        XCTAssertTrue(PostSearch.matches(post(1, comment: "Café"), query: "cafe"))
        XCTAssertTrue(PostSearch.matches(post(2, comment: "QUORUM"), query: "quorum"))
    }

    func testSearchesTheRenderedTextNotTheMarkup() {
        // A query for a tag name must not match, but the text inside it must.
        let markup = post(1, comment: "<span class=\"quote\">&gt;implying</span><br>actual text")
        XCTAssertTrue(PostSearch.matches(markup, query: "implying"))
        XCTAssertTrue(PostSearch.matches(markup, query: "actual text"))
        XCTAssertFalse(PostSearch.matches(markup, query: "span"))
    }

    func testEmptyQueryNeverMatches() {
        XCTAssertFalse(PostSearch.matches(post(1, comment: "anything"), query: ""))
        XCTAssertFalse(PostSearch.matches(post(1, comment: "anything"), query: "   "))
        XCTAssertTrue(PostSearch.matches(in: [post(1, comment: "x")], query: "").isEmpty)
    }

    func testMatchesInOrderReturnsPostNumbers() {
        let posts = [
            post(10, comment: "quorum warning"),
            post(11, comment: "something else"),
            post(12, subject: "Quorum"),
        ]
        XCTAssertEqual(PostSearch.matches(in: posts, query: "quorum"), [PostNumber(10), PostNumber(12)])
    }
}
