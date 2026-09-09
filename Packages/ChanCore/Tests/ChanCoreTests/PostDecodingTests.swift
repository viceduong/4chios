import XCTest
@testable import ChanCore

final class PostDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testDecodesOpPostWithAttachment() throws {
        let json = """
        {
          "no": 123456, "resto": 0, "time": 1700000000,
          "name": "Anonymous", "trip": "!abc", "id": "PosterID", "capcode": "mod",
          "country": "US", "country_name": "United States", "sub": "subject",
          "com": "<b>hello</b>", "tim": 1699999999999, "filename": "image",
          "ext": ".jpg", "fsize": 4242, "md5": "abc123", "w": 1000, "h": 500,
          "tn_w": 250, "tn_h": 125, "spoiler": 1, "custom_spoiler": 2, "m_img": 1,
          "replies": 12, "images": 3, "last_modified": 1700000100,
          "sticky": 1, "closed": 0, "archived": 0, "bumplimit": 1, "imagelimit": 0,
          "unique_ips": 5, "semantic_url": "subject"
        }
        """.data(using: .utf8)!

        let post = try decoder.decode(Post.self, from: json)

        XCTAssertEqual(post.no, PostNumber(123456))
        XCTAssertTrue(post.isOP)
        XCTAssertEqual(post.name, "Anonymous")
        XCTAssertEqual(post.trip, "!abc")
        XCTAssertEqual(post.posterID, "PosterID")
        XCTAssertEqual(post.capcode, "mod")
        XCTAssertEqual(post.countryName, "United States")
        XCTAssertEqual(post.subject, "subject")
        XCTAssertEqual(post.commentHTML, "<b>hello</b>")
        XCTAssertEqual(post.time, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(post.lastModified, Date(timeIntervalSince1970: 1_700_000_100))
        XCTAssertEqual(post.replies, 12)
        XCTAssertEqual(post.uniqueIPs, 5)
        XCTAssertEqual(post.semanticURL, "subject")

        let attachment = try XCTUnwrap(post.attachment)
        XCTAssertEqual(attachment.tim, 1699999999999)
        XCTAssertEqual(attachment.ext, ".jpg")
        XCTAssertEqual(attachment.size, 4242)
        XCTAssertTrue(attachment.isSpoiler)
        XCTAssertEqual(attachment.customSpoiler, 2)
        XCTAssertTrue(attachment.hasMidSizeImage)
        XCTAssertTrue(attachment.isImage)
        XCTAssertFalse(attachment.isVideo)
        XCTAssertEqual(attachment.aspectRatio, 2, accuracy: 0.001)
    }

    func testDecodesReplyWithoutAttachment() throws {
        let json = """
        {"no": 7, "resto": 123456, "time": 1700000001, "com": "reply"}
        """.data(using: .utf8)!

        let post = try decoder.decode(Post.self, from: json)
        XCTAssertFalse(post.isOP)
        XCTAssertEqual(post.resto, PostNumber(123456))
        XCTAssertNil(post.attachment)
        XCTAssertNil(post.lastModified)
    }

    func testRoundTripsThroughJSON() throws {
        let json = """
        {"no": 9, "resto": 0, "time": 1700000000, "com": "x", "tim": 1, "filename": "f", "ext": ".webm"}
        """.data(using: .utf8)!
        let post = try decoder.decode(Post.self, from: json)

        let encoded = try JSONEncoder().encode(post)
        let decoded = try JSONDecoder().decode(Post.self, from: encoded)

        XCTAssertEqual(decoded, post)
        XCTAssertTrue(try XCTUnwrap(decoded.attachment).isVideo)
    }
}

final class BoardDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testDecodesBoardList() throws {
        let json = """
        {"boards": [
          {"board": "g", "title": "Technology", "ws_board": 1, "per_page": 50, "pages": 10,
           "bump_limit": 300, "image_limit": 150, "max_filesize": 4194304,
           "max_webm_filesize": 3145728, "max_webm_duration": 120, "max_comment_chars": 2000,
           "spoilers": 1, "custom_spoilers": 8, "user_ids": 1, "country_flags": 1,
           "cooldowns": {"threads": 600, "replies": 60, "images": 30}},
          {"board": "pol", "title": "Politically Incorrect", "ws_board": 0,
           "meta": {"is_archived": 1, "is_locked": 0}}
        ]}
        """.data(using: .utf8)!

        let response = try decoder.decode(BoardListResponse.self, from: json)
        XCTAssertEqual(response.boards.count, 2)

        let g = response.boards[0]
        XCTAssertEqual(g.board, "g")
        XCTAssertTrue(g.isWorkSafe)
        XCTAssertEqual(g.threadCooldown, 600)
        XCTAssertEqual(g.customSpoilers, 8)

        let pol = response.boards[1]
        XCTAssertFalse(pol.isWorkSafe)
        XCTAssertTrue(pol.isArchived)
        XCTAssertFalse(pol.isLocked)
        XCTAssertEqual(pol.threadCooldown, 0)
    }

    func testCatalogAndThreadEnvelopes() throws {
        let catalog = """
        [{"page": 1, "threads": [{"no": 1, "resto": 0, "time": 1700000000}]}]
        """.data(using: .utf8)!
        let pages = try decoder.decode([CatalogPage].self, from: catalog)
        XCTAssertEqual(pages.first?.threads.first?.no, PostNumber(1))

        let thread = """
        {"posts": [{"no": 1, "resto": 0, "time": 1700000000}, {"no": 2, "resto": 1, "time": 1700000001}]}
        """.data(using: .utf8)!
        let response = try decoder.decode(ThreadResponse.self, from: thread)
        XCTAssertEqual(response.posts.count, 2)

        let tail = """
        {"tail_id": 2, "tail_size": 50, "posts": [{"no": 3, "resto": 1, "time": 1700000002}]}
        """.data(using: .utf8)!
        let tailResponse = try decoder.decode(ThreadTailResponse.self, from: tail)
        XCTAssertEqual(tailResponse.tailId, PostNumber(2))
        XCTAssertEqual(tailResponse.tailSize, 50)
        XCTAssertEqual(tailResponse.posts.first?.no, PostNumber(3))
    }
}
