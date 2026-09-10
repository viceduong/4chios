import XCTest
@testable import ChanCore

final class ChanFilterEngineTests: XCTestCase {
    private func post(
        _ no: Int,
        name: String? = "Anonymous",
        subject: String? = nil,
        comment: String = "",
        trip: String? = nil,
        capcode: String? = nil,
        posterID: String? = nil,
        country: String? = nil,
        countryName: String? = nil,
        filename: String? = nil,
        md5: String? = nil,
        fileSize: Int? = nil,
        dimensions: (width: Int, height: Int)? = nil
    ) -> Post {
        Post(
            no: PostNumber(no),
            time: Date(timeIntervalSince1970: 0),
            name: name,
            trip: trip,
            posterID: posterID,
            capcode: capcode,
            country: country,
            countryName: countryName,
            subject: subject,
            commentHTML: comment,
            tim: filename == nil ? nil : 1,
            filename: filename,
            ext: filename == nil ? nil : ".jpg",
            fileSize: fileSize,
            md5: md5,
            width: dimensions?.width,
            height: dimensions?.height
        )
    }

    private func context(_ board: BoardID = "g", workSafe: Bool = true) -> ChanFilterContext {
        ChanFilterContext(board: board, isWorkSafe: workSafe)
    }

    // MARK: - Matching modes

    func testKeywordIsCaseAndDiacriticInsensitive() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(match: .keyword, pattern: "café", action: .hidePost),
        ])
        XCTAssertTrue(engine.decision(for: post(1, comment: "let's get a CAFE"), in: context()).contains(.hide))
        XCTAssertFalse(engine.decision(for: post(2, comment: "tea"), in: context()).contains(.hide))
    }

    func testExactMatchRequiresWholeFieldValue() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(fields: [.md5], match: .exact, pattern: "abc123", action: .hidePost),
        ])
        XCTAssertTrue(engine.decision(for: post(1, filename: "a.jpg", md5: "ABC123"), in: context()).contains(.hide))
        XCTAssertFalse(
            engine.decision(for: post(2, filename: "a.jpg", md5: "abc1234"), in: context()).contains(.hide),
            "exact matching must not behave like a substring search on identifiers"
        )
    }

    func testRegexIsCaseSensitiveUnlessFlagged() throws {
        let sensitive = ChanFilterEngine(filters: [
            ChanFilter(fields: [.comment], match: .regex, pattern: "/spam/", action: .hidePost),
        ])
        XCTAssertTrue(sensitive.decision(for: post(1, comment: "spam"), in: context()).contains(.hide))
        XCTAssertFalse(sensitive.decision(for: post(2, comment: "SPAM"), in: context()).contains(.hide))

        let insensitive = ChanFilterEngine(filters: [
            ChanFilter(fields: [.comment], match: .regex, pattern: "/spam/i", action: .hidePost),
        ])
        XCTAssertTrue(insensitive.decision(for: post(3, comment: "SPAM"), in: context()).contains(.hide))
    }

    func testBareRegexDefaultsToCaseInsensitive() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(fields: [.comment], match: .regex, pattern: #"\b\d{4,}\b"#, action: .hideThread),
        ])
        XCTAssertTrue(engine.hidesThread(post(1, comment: "order 12345"), in: context()))
        XCTAssertFalse(engine.hidesThread(post(2, comment: "order 12"), in: context()))
    }

    func testMultilineRegexFlag() throws {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(fields: [.comment], match: .regex, pattern: "/^line$/m", action: .hidePost),
        ])
        XCTAssertTrue(engine.decision(for: post(1, comment: "first\nline\nlast"), in: context()).contains(.hide))
        XCTAssertFalse(engine.decision(for: post(2, comment: "first line last"), in: context()).contains(.hide))
    }

    func testInvalidRegexIsReportedNotCrashing() {
        let bad = ChanFilter(match: .regex, pattern: "([unclosed", action: .hidePost)
        let engine = ChanFilterEngine(filters: [bad])

        XCTAssertEqual(engine.invalidFilters.count, 1)
        XCTAssertFalse(engine.decision(for: post(1, comment: "anything"), in: context()).contains(.hide))
        XCTAssertNotNil(ChanFilterEngine.validate(bad))
        XCTAssertNil(ChanFilterEngine.validate(ChanFilter(match: .regex, pattern: "/ok/", action: .hidePost)))
    }

    // MARK: - Field scope

    func testOnlySelectedFieldsAreSearched() {
        let commentOnly = ChanFilterEngine(filters: [
            ChanFilter(fields: [.comment], match: .keyword, pattern: "spam", action: .hidePost),
        ])
        XCTAssertFalse(
            commentOnly.decision(for: post(1, subject: "spam", comment: "clean"), in: context()).contains(.hide),
            "a comment filter must not match the subject"
        )

        let subjectOnly = ChanFilterEngine(filters: [
            ChanFilter(fields: [.subject], match: .keyword, pattern: "spam", action: .hidePost),
        ])
        XCTAssertTrue(subjectOnly.decision(for: post(2, subject: "spam", comment: "clean"), in: context()).contains(.hide))
    }

    func testAttachmentFieldsOnlyMatchAttachmentPosts() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(fields: [.filename], match: .keyword, pattern: ".webm", action: .hidePost),
        ])
        XCTAssertTrue(engine.decision(for: post(1, filename: "clip.WEBM"), in: context()).contains(.hide))
        XCTAssertFalse(engine.decision(for: post(2, comment: "no file"), in: context()).contains(.hide))
    }

    func testAThreadWithNoMatchingFieldIsUntouched() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(fields: [.posterID], match: .exact, pattern: "ABCDEF", action: .hidePost),
        ])
        XCTAssertFalse(engine.decision(for: post(1, posterID: "ZZZZZZ"), in: context()).contains(.hide))
        XCTAssertTrue(engine.decision(for: post(2, posterID: "ABCDEF"), in: context()).contains(.hide))
    }

    func testMatchesReportWhichFieldMatched() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(fields: [.subject, .comment], match: .keyword, pattern: "needle", action: .highlight),
        ])
        let hits = engine.matches(for: post(1, comment: "a needle here"), in: context())
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.field, .comment)
    }

    // MARK: - Board scope

    func testBoardScopeIncludeExcludeAndGroups() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(
                fields: [.comment],
                match: .keyword,
                pattern: "election",
                scope: ChanBoardScope(included: ["pol"]),
                action: .hidePost
            ),
        ])
        XCTAssertTrue(engine.decision(for: post(1, comment: "election"), in: context("pol", workSafe: false)).contains(.hide))
        XCTAssertFalse(engine.decision(for: post(1, comment: "election"), in: context("g")).contains(.hide))

        let nsfwOnly = ChanFilterEngine(filters: [
            ChanFilter(
                fields: [.comment],
                match: .keyword,
                pattern: "x",
                scope: ChanBoardScope(included: ["nsfw"]),
                action: .hidePost
            ),
        ])
        XCTAssertTrue(nsfwOnly.decision(for: post(1, comment: "x"), in: context("pol", workSafe: false)).contains(.hide))
        XCTAssertFalse(nsfwOnly.decision(for: post(1, comment: "x"), in: context("g", workSafe: true)).contains(.hide))

        let excepted = ChanFilterEngine(filters: [
            ChanFilter(
                fields: [.comment],
                match: .keyword,
                pattern: "x",
                scope: ChanBoardScope(excluded: ["g"]),
                action: .hidePost
            ),
        ])
        XCTAssertFalse(excepted.decision(for: post(1, comment: "x"), in: context("g")).contains(.hide))
        XCTAssertTrue(excepted.decision(for: post(1, comment: "x"), in: context("v")).contains(.hide))

        XCTAssertEqual(ChanBoardScope.global.summary, "all boards")
        XCTAssertEqual(ChanBoardScope(included: ["g"], excluded: ["pol"]).summary, "g except pol")
    }

    // MARK: - Actions

    func testHideWinsOverStub() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(fields: [.comment], match: .keyword, pattern: "spam", action: .stub),
            ChanFilter(fields: [.comment], match: .keyword, pattern: "spam", action: .hidePost),
        ])
        let decision = engine.decision(for: post(1, comment: "spam"), in: context())
        XCTAssertTrue(decision.contains(.hide))
        XCTAssertFalse(decision.contains(.stub), "hiding is strictly stronger than collapsing")
    }

    func testStubAndHighlightCombine() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(fields: [.comment], match: .keyword, pattern: "long", action: .stub),
            ChanFilter(fields: [.comment], match: .keyword, pattern: "long", action: .highlight),
        ])
        let decision = engine.decision(for: post(1, comment: "long post"), in: context())
        XCTAssertTrue(decision.contains(.stub))
        XCTAssertTrue(decision.contains(.highlight))
    }

    func testDisabledRuleIsIgnored() {
        let engine = ChanFilterEngine(filters: [
            ChanFilter(match: .keyword, pattern: "x", action: .hidePost, enabled: false),
        ])
        XCTAssertTrue(engine.isEmpty)
        XCTAssertFalse(engine.decision(for: post(1, comment: "x"), in: context()).contains(.hide))
    }

    func testSuggestionsForIdentifierFields() {
        XCTAssertEqual(ChanFilterMatch.suggested(for: [.md5]), .exact)
        XCTAssertEqual(ChanFilterMatch.suggested(for: [.posterID, .tripcode]), .exact)
        XCTAssertEqual(ChanFilterMatch.suggested(for: [.comment]), .keyword)
        XCTAssertEqual(ChanFilterMatch.suggested(for: [.comment, .md5]), .keyword)
    }

    func testFilterRoundTripsThroughCodable() throws {
        let filter = ChanFilter(
            id: 7,
            fields: [.subject, .comment],
            match: .regex,
            pattern: "/\\d+/i",
            scope: ChanBoardScope(included: ["g"], excluded: ["pol"]),
            action: .stub,
            enabled: true
        )
        let data = try JSONEncoder().encode(filter)
        XCTAssertEqual(try JSONDecoder().decode(ChanFilter.self, from: data), filter)
    }
}
