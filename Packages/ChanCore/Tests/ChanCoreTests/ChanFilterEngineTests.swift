import XCTest
@testable import ChanCore

final class ChanFilterEngineTests: XCTestCase {
    private func post(
        _ no: Int,
        comment: String = "",
        subject: String? = nil,
        posterID: String? = nil,
        trip: String? = nil,
        capcode: String? = nil,
        filename: String? = nil
    ) -> Post {
        Post(
            no: PostNumber(no),
            time: Date(timeIntervalSince1970: 0),
            trip: trip,
            posterID: posterID,
            capcode: capcode,
            subject: subject,
            commentHTML: comment,
            tim: filename == nil ? nil : 1,
            filename: filename,
            ext: filename == nil ? nil : ".jpg"
        )
    }

    func testEmptyEngineReturnsNoDecision() {
        let engine = ChanFilterEngine(filters: [])
        XCTAssertEqual(engine.decision(for: post(1, comment: "anything"), in: "g"), [])
        XCTAssertTrue(engine.isEmpty)
    }

    func testKeywordIsCaseAndDiacriticInsensitive() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(kind: .keyword, pattern: "café", action: .hidePost),
        ])
        XCTAssertTrue(engine.decision(for: post(1, comment: "let's get a CAFE"), in: "g").contains(.hide))
        XCTAssertFalse(engine.decision(for: post(2, comment: "tea"), in: "g").contains(.hide))
    }

    func testKeywordIgnoresHTMLMarkup() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(kind: .keyword, pattern: "spam", action: .hidePost),
        ])
        XCTAssertTrue(engine.decision(for: post(1, comment: "<b>spam</b> link"), in: "g").contains(.hide))
    }

    func testRegexMatching() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(kind: .regex, pattern: #"\b\d{3,}\b"#, action: .hideThread),
        ])
        XCTAssertTrue(engine.hidesThread(post(1, comment: "order 12345"), in: "g"))
        XCTAssertFalse(engine.hidesThread(post(2, comment: "order 12"), in: "g"))
    }

    func testInvalidRegexNeverMatches() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(kind: .regex, pattern: "([unclosed", action: .hidePost),
        ])
        XCTAssertFalse(engine.decision(for: post(1, comment: "anything"), in: "g").contains(.hide))
    }

    func testPosterIDTripcodeCapcodeAndFilename() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(kind: .posterID, pattern: "ABC123", action: .hidePost),
            ChanFilter(kind: .tripcode, pattern: "!secret", action: .highlight),
            ChanFilter(kind: .capcode, pattern: "mod", action: .highlight),
            ChanFilter(kind: .filename, pattern: ".webm", action: .hidePost),
        ])

        let hidden = engine.decision(for: post(1, posterID: "abc123"), in: "g")
        XCTAssertTrue(hidden.contains(.hide))

        let highlighted = engine.decision(for: post(2, trip: "!secret", capcode: "mod"), in: "g")
        XCTAssertTrue(highlighted.contains(.highlight))

        XCTAssertTrue(engine.decision(for: post(3, filename: "clip.WEBM"), in: "g").contains(.hide))
    }

    func testBoardScopeIsRespected() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(board: "pol", kind: .keyword, pattern: "election", action: .hidePost),
        ])
        XCTAssertTrue(engine.decision(for: post(1, comment: "election"), in: "pol").contains(.hide))
        XCTAssertFalse(engine.decision(for: post(1, comment: "election"), in: "g").contains(.hide))
    }

    func testDisabledRuleIsIgnored() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(kind: .keyword, pattern: "x", action: .hidePost, enabled: false),
        ])
        XCTAssertFalse(engine.decision(for: post(1, comment: "x"), in: "g").contains(.hide))
    }

    func testFilterRoundTripsThroughCodable() throws {
        let filter = ChanFilter(id: 7, board: "g", kind: .regex, pattern: "\\d+", action: .hideThread, enabled: true)
        let data = try JSONEncoder().encode(filter)
        XCTAssertEqual(try JSONDecoder().decode(ChanFilter.self, from: data), filter)
    }
}
