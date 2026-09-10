import ChanAPI
import ChanCore
import Foundation
import XCTest
@testable import ChanAI

final class MockAITransport: ChanTransport, @unchecked Sendable {
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
        return queued.isEmpty ? ChanHTTPResponse(statusCode: 500) : queued.removeFirst()
    }

    var requests: [ChanHTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

// MARK: - Fixtures

private func completionResponse(_ text: String) -> ChanHTTPResponse {
    let payload: [String: Any] = ["choices": [["message": ["content": text]]]]
    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    return ChanHTTPResponse(statusCode: 200, body: data)
}

private func makePost(
    _ no: Int,
    op: Int = 0,
    name: String? = "Anonymous",
    subject: String? = nil,
    comment: String? = nil,
    filename: String? = nil,
    spoiler: Bool? = nil
) -> Post {
    Post(
        no: PostNumber(no),
        resto: PostNumber(op),
        time: Date(timeIntervalSince1970: TimeInterval(no)),
        name: name,
        subject: subject,
        commentHTML: comment,
        tim: filename == nil ? nil : no,
        filename: filename,
        ext: filename == nil ? nil : ".jpg",
        fileSize: filename == nil ? nil : 1024,
        width: filename == nil ? nil : 800,
        height: filename == nil ? nil : 600,
        isSpoiler: spoiler
    )
}

private func decodeBody(_ request: ChanHTTPRequest) -> [String: Any] {
    guard let body = request.body,
          let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return [:] }
    return object
}

// MARK: - Transcript

final class ThreadTranscriptTests: XCTestCase {
    func testRendersPostWithHeaderSubjectBodyAndMedia() {
        let post = makePost(
            42,
            op: 1,
            name: "Anonymous",
            subject: "Hello",
            comment: "<span class=\"quote\">&gt;greentext</span><br>body text",
            filename: "cat",
            spoiler: true
        )
        let rendered = ThreadTranscript.render(post)

        XCTAssertTrue(rendered.contains(">>42"))
        XCTAssertTrue(rendered.contains("Anonymous"))
        XCTAssertTrue(rendered.contains("Subject: Hello"))
        XCTAssertTrue(rendered.contains(">greentext"))
        XCTAssertTrue(rendered.contains("body text"))
        XCTAssertTrue(rendered.contains("[file: cat.jpg 800x600 1024 bytes spoiler]"))
    }

    func testMarksOPAndSkipsEmptyBodies() {
        let rendered = ThreadTranscript.render(makePost(1, subject: "Opening"))
        XCTAssertTrue(rendered.contains("[OP]"))
        XCTAssertFalse(rendered.contains("Subject: \n"))
    }

    func testChunksRespectTheLimit() {
        let posts = (1...40).map { makePost($0, op: 1, comment: String(repeating: "x", count: 200)) }
        let chunks = ThreadTranscript.chunks(posts, characterLimit: 1_000)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.flatMap { $0 }.count, posts.count, "chunking must not drop posts")
        for chunk in chunks {
            XCTAssertLessThanOrEqual(ThreadTranscript.render(chunk).count, 1_200)
        }
    }

    func testOversizedPostIsTruncated() {
        let post = makePost(1, op: 1, comment: String(repeating: "y", count: 20_000))
        let rendered = ThreadTranscript.render(post)
        XCTAssertLessThan(rendered.count, 7_000)
        XCTAssertTrue(rendered.hasSuffix("[truncated]"))
    }

    func testEmptyThreadYieldsNoChunks() {
        XCTAssertTrue(ThreadTranscript.chunks([]).isEmpty)
    }
}

// MARK: - Client

final class AIChatClientTests: XCTestCase {
    private func client(
        _ responses: [ChanHTTPResponse],
        configuration: AIConfiguration = AIConfiguration(apiKey: "gc_test")
    ) -> (AIChatClient, MockAITransport) {
        let transport = MockAITransport(responses: responses)
        return (AIChatClient(transport: transport, configuration: configuration), transport)
    }

    func testEncodesOpenAICompatibleRequest() async throws {
        let (chat, transport) = client([completionResponse("hello")])
        let reply = try await chat.complete([AIChatMessage(role: .user, text: "hi")])
        XCTAssertEqual(reply, "hello")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://api.generalcompute.com/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer gc_test")

        let body = decodeBody(request)
        XCTAssertEqual(body["model"] as? String, "gemma-4-31B-it")
        XCTAssertEqual(body["max_tokens"] as? Int, 1_200)
        XCTAssertEqual(body["stream"] as? Bool, false)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        // No images: content is a plain string.
        XCTAssertEqual(messages.first?["content"] as? String, "hi")
    }

    func testUnconfiguredKeyIsRejectedBeforeAnyRequest() async {
        let (chat, transport) = client([completionResponse("never")], configuration: AIConfiguration(apiKey: ""))
        do {
            _ = try await chat.complete([AIChatMessage(role: .user, text: "hi")])
            XCTFail("expected .notConfigured")
        } catch let error as AIChatError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testUnauthorizedIsSurfaced() async {
        let (chat, _) = client([ChanHTTPResponse(statusCode: 401, body: Data("nope".utf8))])
        do {
            _ = try await chat.complete([AIChatMessage(role: .user, text: "hi")])
            XCTFail("expected .http")
        } catch let error as AIChatError {
            XCTAssertEqual(error, .http(status: 401, message: "nope"))
            XCTAssertEqual(error.userMessage, "The AI endpoint rejected the API key.")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testEmptyChoicesAreReported() async {
        let (chat, _) = client([ChanHTTPResponse(statusCode: 200, body: Data(#"{"choices":[]}"#.utf8))])
        do {
            _ = try await chat.complete([AIChatMessage(role: .user, text: "hi")])
            XCTFail("expected .decoding")
        } catch let error as AIChatError {
            if case .decoding = error { } else { XCTFail("unexpected \(error)") }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}

// MARK: - Summarizer

final class ThreadSummarizerTests: XCTestCase {
    private func summarizer(
        _ responses: [ChanHTTPResponse],
        options: ThreadSummarizer.Options = ThreadSummarizer.Options()
    ) -> (ThreadSummarizer, MockAITransport) {
        let transport = MockAITransport(responses: responses)
        let client = AIChatClient(transport: transport, configuration: AIConfiguration(apiKey: "gc_test"))
        return (ThreadSummarizer(client: client, options: options), transport)
    }

    private func thread(_ count: Int, commentLength: Int = 40) -> [Post] {
        (1...count).map { index in
            makePost(
                index,
                op: index == 1 ? 0 : 1,
                subject: index == 1 ? "Opening post" : nil,
                comment: String(repeating: "w", count: commentLength)
            )
        }
    }

    func testSinglePassSummaryReturnsProse() async throws {
        let (summarizer, transport) = summarizer([
            completionResponse("The thread argues about beans."),
        ])

        let summary = try await summarizer.summarize(board: "g", op: 1, posts: thread(5))

        XCTAssertEqual(transport.requests.count, 1, "a short thread must be a single request")
        XCTAssertEqual(summary.postCount, 5)
        XCTAssertEqual(summary.model, "gemma-4-31B-it")
        XCTAssertEqual(summary.text, "The thread argues about beans.")
    }

    func testPromptForbidsCitations() async throws {
        let (summarizer, transport) = summarizer([completionResponse("ok")])
        _ = try await summarizer.summarize(board: "g", op: 1, posts: thread(3))

        let messages = try XCTUnwrap(decodeBody(try XCTUnwrap(transport.requests.first))["messages"] as? [[String: Any]])
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        let prompt = try XCTUnwrap(messages.last?["content"] as? String)

        XCTAssertTrue(system.contains("Do not cite post numbers"))
        XCTAssertFalse(prompt.contains("Cite posts"), "the user prompt must not ask for citations")
    }

    func testLongThreadIsMapReducedInOrder() async throws {
        // Derive the expected chunk count from the same chunker the summarizer
        // uses, so the test cannot drift out of sync with the character limit.
        let posts = thread(30, commentLength: 300)
        let limit = 400
        let expectedChunks = ThreadTranscript.chunks(posts, characterLimit: limit).count
        XCTAssertGreaterThan(expectedChunks, 1, "fixture must actually need a reduce pass")

        let responses = (1...expectedChunks).map { completionResponse("part \($0) >>\($0)") }
            + [completionResponse("merged >>2 and >>1")]

        let (summarizer, transport) = summarizer(
            responses,
            options: ThreadSummarizer.Options(chunkCharacterLimit: limit)
        )

        let summary = try await summarizer.summarize(board: "g", op: 1, posts: posts)

        XCTAssertEqual(transport.requests.count, expectedChunks + 1, "one request per chunk plus the reduce pass")
        XCTAssertEqual(summary.text, "merged >>2 and >>1")

        let lastBody = decodeBody(try XCTUnwrap(transport.requests.last))
        let messages = try XCTUnwrap(lastBody["messages"] as? [[String: Any]])
        let finalPrompt = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(finalPrompt.contains("<part-1>"))
        XCTAssertTrue(finalPrompt.contains("<part-\(expectedChunks)>"))
    }

    func testStatusesAreReported() async throws {
        let (summarizer, _) = summarizer([completionResponse("ok")])
        let recorder = StatusRecorder()
        _ = try await summarizer.summarize(board: "g", op: 1, posts: thread(3)) { recorder.append($0) }
        XCTAssertEqual(recorder.values, ["Summarizing…"], "phases must not expose the map-reduce seams")
    }

    func testEmptyThreadIsRejectedLocally() async {
        let (summarizer, transport) = summarizer([completionResponse("never")])
        do {
            _ = try await summarizer.summarize(board: "g", op: 1, posts: [])
            XCTFail("expected .decoding")
        } catch let error as AIChatError {
            if case .decoding = error { } else { XCTFail("unexpected \(error)") }
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testStyleChangesThePrompt() async throws {
        let (summarizer, transport) = summarizer(
            [completionResponse("ok")],
            options: ThreadSummarizer.Options(style: .timeline)
        )
        _ = try await summarizer.summarize(board: "g", op: 1, posts: thread(3))
        let messages = try XCTUnwrap(decodeBody(try XCTUnwrap(transport.requests.first))["messages"] as? [[String: Any]])
        XCTAssertTrue((messages.last?["content"] as? String)?.contains("chronology") == true)
    }
}

final class StatusRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
