import ChanCore
import Foundation
import XCTest
@testable import ChanAPI

/// Records requests and replays canned responses in order.
final class MockTransport: ChanTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ChanHTTPRequest] = []
    private var queued: [ChanHTTPResponse]

    init(responses: [ChanHTTPResponse]) {
        queued = responses
    }

    func send(_ request: ChanHTTPRequest) async throws -> ChanHTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        return queued.isEmpty ? ChanHTTPResponse(statusCode: 404) : queued.removeFirst()
    }

    var requests: [ChanHTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

final class ChanClientTests: XCTestCase {
    private func makeClient(_ responses: [ChanHTTPResponse]) -> (ChanClient, MockTransport) {
        let transport = MockTransport(responses: responses)
        let client = ChanClient(
            transport: transport,
            rateLimiter: ChanRateLimiter(minimumInterval: 0),
            cache: ChanMemoryCache()
        )
        return (client, transport)
    }

    private func json(_ string: String) -> Data {
        Data(string.utf8)
    }

    func testBoardsDecoding() async throws {
        let (client, _) = makeClient([ChanHTTPResponse(statusCode: 200, body: json(#"{"boards":[{"board":"g","title":"Technology"}]}"#))])
        let boards = try await client.boards()
        XCTAssertEqual(boards.count, 1)
        XCTAssertEqual(boards[0].board, "g")
        XCTAssertEqual(boards[0].title, "Technology")
    }

    func testCatalogFlattensPages() async throws {
        let body = json(#"[{"page":1,"threads":[{"no":1,"resto":0,"time":1700000000}]},{"page":2,"threads":[{"no":2,"resto":0,"time":1700000001}]}]"#)
        let (client, _) = makeClient([ChanHTTPResponse(statusCode: 200, body: body)])
        let posts = try await client.catalog("g")
        XCTAssertEqual(posts.map(\.no), [PostNumber(1), PostNumber(2)])
    }

    func testTailDecoding() async throws {
        let body = json(#"{"tail_id":10,"tail_size":100,"posts":[{"no":11,"resto":1,"time":1700000002}]}"#)
        let (client, _) = makeClient([ChanHTTPResponse(statusCode: 200, body: body)])
        let tail = try await client.tail("g", op: PostNumber(1))
        XCTAssertEqual(tail.tailId, PostNumber(10))
        XCTAssertEqual(tail.posts.first?.no, PostNumber(11))
    }

    func testConditionalRequestAndNotModifiedReuse() async throws {
        let first = json(#"{"boards":[{"board":"g","title":"Technology"}]}"#)
        let (client, transport) = makeClient([
            ChanHTTPResponse(statusCode: 200, headers: ["ETag": "\"abc\"", "Last-Modified": "Wed, 21 Oct 2015 07:28:00 GMT"], body: first),
            ChanHTTPResponse(statusCode: 304),
        ])

        _ = try await client.boards()
        let second = try await client.boards()

        XCTAssertEqual(second.count, 1, "304 must reuse the cached body")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[1].headers["If-None-Match"], "\"abc\"")
        XCTAssertEqual(transport.requests[1].headers["If-Modified-Since"], "Wed, 21 Oct 2015 07:28:00 GMT")
    }

    func testNotFoundMapsToGone() async {
        let (client, _) = makeClient([ChanHTTPResponse(statusCode: 404)])
        do {
            _ = try await client.thread("g", op: PostNumber(1))
            XCTFail("expected .gone")
        } catch let error as ChanError {
            XCTAssertEqual(error, .gone)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testMalformedJSONMapsToDecodingError() async {
        let (client, _) = makeClient([ChanHTTPResponse(statusCode: 200, body: json("not json"))])
        do {
            _ = try await client.boards()
            XCTFail("expected decoding error")
        } catch let error as ChanError {
            if case .decoding = error { } else { XCTFail("unexpected: \(error)") }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

final class ChanRateLimiterTests: XCTestCase {
    func testSerializesAtMinimumInterval() async {
        let limiter = ChanRateLimiter(minimumInterval: 0.05)
        let start = Date()
        for _ in 0..<4 {
            await limiter.acquire()
        }
        let elapsed = Date().timeIntervalSince(start)
        // Three gaps of 0.05s must have elapsed; allow scheduling slack.
        XCTAssertGreaterThanOrEqual(elapsed, 0.14)
    }

    func testAllWaitersComplete() async {
        let limiter = ChanRateLimiter(minimumInterval: 0.01)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask { await limiter.acquire(.prefetch) }
            }
        }
        // Reaching here without hanging is the assertion.
        XCTAssertTrue(true)
    }
}
