import ChanAPI
import ChanAI
import ChanCore
import Foundation
import XCTest
@testable import ChanAI

/// A search backend that records queries and replays canned results.
final class MockSearchProvider: SearchProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var responses: [Result<SearchResponse, SearchError>]

    init(responses: [Result<SearchResponse, SearchError>]) {
        self.responses = responses
    }

    func search(_ query: String, limit: Int) async throws -> SearchResponse {
        lock.lock()
        recorded.append(query)
        let next = responses.isEmpty
            ? .success(SearchResponse(results: []))
            : responses.removeFirst()
        lock.unlock()
        return try next.get()
    }

    var queries: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

private func exaBody(results: [(String, String, String)], cost: Double?) -> Data {
    var payload: [String: Any] = [
        "results": results.map { ["title": $0.0, "url": $0.1, "text": $0.2] },
    ]
    if let cost { payload["costDollars"] = ["total": cost] }
    return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
}

final class ExaSearchProviderTests: XCTestCase {
    func testSendsTheDocumentedRequestShape() async throws {
        let transport = MockAITransport(responses: [
            ChanHTTPResponse(statusCode: 200, body: exaBody(results: [("T", "https://e.com", "body")], cost: 0.007)),
        ])
        let provider = ExaSearchProvider(apiKey: "47c16847-test", transport: transport)
        let response = try await provider.search("proxmox release", limit: 8)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://api.exa.ai/search")
        XCTAssertEqual(request.headers["x-api-key"], "47c16847-test")

        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]
        )
        XCTAssertEqual(body["query"] as? String, "proxmox release")
        XCTAssertEqual(body["numResults"] as? Int, 8)
        let contents = try XCTUnwrap(body["contents"] as? [String: Any])
        let text = try XCTUnwrap(contents["text"] as? [String: Any])
        XCTAssertEqual(text["maxCharacters"] as? Int, 4_000)

        XCTAssertEqual(response.results.count, 1)
        XCTAssertEqual(response.results.first?.url, "https://e.com")
        XCTAssertEqual(response.costUSD, 0.007, "Exa reports the cost, so spend is measured not estimated")
    }

    func testMissingCostIsTolerated() async throws {
        let transport = MockAITransport(responses: [
            ChanHTTPResponse(statusCode: 200, body: exaBody(results: [("T", "https://e.com", "b")], cost: nil)),
        ])
        let provider = ExaSearchProvider(apiKey: "k", transport: transport)
        let response = try await provider.search("q", limit: 3)
        XCTAssertNil(response.costUSD)
    }

    func testRejectedKeyIsSurfacedClearly() async {
        let transport = MockAITransport(responses: [ChanHTTPResponse(statusCode: 401, body: Data("nope".utf8))])
        let provider = ExaSearchProvider(apiKey: "bad", transport: transport)
        do {
            _ = try await provider.search("q", limit: 3)
            XCTFail("expected an http error")
        } catch let error as SearchError {
            XCTAssertEqual(error, .http(status: 401, message: "nope"))
            XCTAssertEqual(error.userMessage, "The search API rejected the key.")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testUnconfiguredKeyNeverReachesTheNetwork() async {
        let transport = MockAITransport(responses: [])
        let provider = ExaSearchProvider(apiKey: "  ", transport: transport)
        do {
            _ = try await provider.search("q", limit: 3)
            XCTFail("expected notConfigured")
        } catch let error as SearchError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testToolPayloadIsJSONTheModelCanRead() {
        let response = SearchResponse(
            results: [SearchResult(title: "Title", url: "https://e.com", text: "some text")],
            costUSD: 0.007
        )
        let payload = try? JSONSerialization.jsonObject(with: Data(response.toolPayload.utf8))
        let object = payload as? [String: Any]
        let results = object?["results"] as? [[String: Any]]
        XCTAssertEqual(results?.first?["url"] as? String, "https://e.com")
        XCTAssertEqual(results?.first?["text"] as? String, "some text")
    }
}

final class ToolLoopTests: XCTestCase {
    private func toolCallRound(query: String, id: String = "call_1") -> ChanHTTPResponse {
        let message: [String: Any] = [
            "content": NSNull(),
            "tool_calls": [["id": id, "type": "function",
                            "function": ["name": "web_search",
                                         "arguments": "{\"query\":\"\(query)\"}"]]],
        ]
        let payload: [String: Any] = [
            "model": "gemma-4-31B-it",
            "choices": [["message": message, "finish_reason": "tool_calls"]],
            "usage": ["prompt_tokens": 100, "completion_tokens": 10, "total_tokens": 110],
        ]
        return ChanHTTPResponse(statusCode: 200, body: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data())
    }

    private func finalRound(_ text: String) -> ChanHTTPResponse {
        let payload: [String: Any] = [
            "model": "gemma-4-31B-it",
            "choices": [["message": ["content": text], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 300, "completion_tokens": 40, "total_tokens": 340],
        ]
        return ChanHTTPResponse(statusCode: 200, body: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data())
    }

    private func client(_ responses: [ChanHTTPResponse]) -> (AIChatClient, MockAITransport) {
        let transport = MockAITransport(responses: responses)
        return (AIChatClient(transport: transport, configuration: AIConfiguration(apiKey: "gc_key")), transport)
    }

    private func searched(_ cost: Double?, url: String = "https://python.org") -> Result<SearchResponse, SearchError> {
        .success(
            SearchResponse(
                results: [SearchResult(title: "Python", url: url, text: "3.14.7 is current")],
                costUSD: cost
            )
        )
    }

    func testModelAsksThenAnswersWithTheResultFedBack() async throws {
        let (chat, transport) = client([toolCallRound(query: "latest python"), finalRound("Python 3.14.7.")])
        let provider = MockSearchProvider(responses: [searched(0.007)])

        let reply = try await chat.completeWithTools(
            [AIChatMessage(role: .user, text: "What is the latest Python?")],
            provider: provider,
            maximumResults: 8
        )

        XCTAssertEqual(provider.queries, ["latest python"], "the model's own query is what gets searched")
        XCTAssertEqual(reply.text, "Python 3.14.7.")
        XCTAssertTrue(reply.usedWebSearch)
        XCTAssertEqual(reply.searchCostUSD, 0.007, "cost is measured from the provider")
        XCTAssertEqual(reply.sources.first?.url, "https://python.org")
        XCTAssertEqual(reply.usage?.totalTokens, 450, "usage accumulates across both rounds")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testTheToolResultIsSentBackAsAToolMessage() async throws {
        let (chat, transport) = client([toolCallRound(query: "q"), finalRound("done")])
        let provider = MockSearchProvider(responses: [searched(0.007)])
        _ = try await chat.completeWithTools(
            [AIChatMessage(role: .user, text: "hi")],
            provider: provider,
            maximumResults: 8
        )

        let second = try XCTUnwrap(transport.requests.last)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: second.body ?? Data()) as? [String: Any]
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.last?["role"] as? String, "tool")
        XCTAssertEqual(messages.last?["tool_call_id"] as? String, "call_1")
        XCTAssertTrue((messages.last?["content"] as? String)?.contains("3.14.7") == true)

        // The assistant turn carrying the call must be replayed verbatim.
        let assistant = messages[messages.count - 2]
        XCTAssertEqual(assistant["role"] as? String, "assistant")
        XCTAssertNotNil(assistant["tool_calls"])
    }

    func testNoSearchMeansASingleRequest() async throws {
        let (chat, transport) = client([finalRound("The thread answers that itself.")])
        let provider = MockSearchProvider(responses: [])

        let reply = try await chat.completeWithTools(
            [AIChatMessage(role: .user, text: "What did the OP mean?")],
            provider: provider,
            maximumResults: 8
        )

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertTrue(provider.queries.isEmpty)
        XCTAssertFalse(reply.usedWebSearch)
        XCTAssertNil(reply.searchCostUSD)
    }

    func testAFailedSearchIsReportedToTheModelAndStillAnswers() async throws {
        let (chat, _) = client([toolCallRound(query: "q"), finalRound("I could not search, but the thread says X.")])
        let provider = MockSearchProvider(responses: [
            .failure(.http(status: 429, message: "slow down")),
        ])

        let reply = try await chat.completeWithTools(
            [AIChatMessage(role: .user, text: "hi")],
            provider: provider,
            maximumResults: 8
        )

        XCTAssertTrue(reply.text.contains("could not search"))
        XCTAssertNil(reply.searchCostUSD)
    }

    func testMultipleSearchesInOneRoundAreAllExecuted() async throws {
        let message: [String: Any] = [
            "content": NSNull(),
            "tool_calls": [
                ["id": "a", "type": "function",
                 "function": ["name": "web_search", "arguments": "{\"query\":\"first\"}"]],
                ["id": "b", "type": "function",
                 "function": ["name": "web_search", "arguments": "{\"query\":\"second\"}"]],
            ],
        ]
        let payload: [String: Any] = ["model": "m", "choices": [["message": message, "finish_reason": "tool_calls"]]]
        let (chat, _) = client([
            ChanHTTPResponse(statusCode: 200, body: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()),
            finalRound("Compared."),
        ])
        let provider = MockSearchProvider(responses: [searched(0.007, url: "https://a.example"),
                                                      searched(0.007, url: "https://b.example")])

        let reply = try await chat.completeWithTools(
            [AIChatMessage(role: .user, text: "compare")],
            provider: provider,
            maximumResults: 8
        )

        XCTAssertEqual(provider.queries, ["first", "second"])
        XCTAssertEqual(reply.searchCostUSD ?? 0, 0.014, accuracy: 0.0001)
        XCTAssertEqual(Set(reply.sources.map(\.url)), ["https://a.example", "https://b.example"])
    }

    func testTheLoopIsBounded() async throws {
        // A model that only ever asks for searches must not run forever.
        let (chat, transport) = client(Array(repeating: toolCallRound(query: "again"), count: 6))
        let provider = MockSearchProvider(responses: [])
        let configuration = AIConfiguration(apiKey: "gc_key")
        _ = configuration

        do {
            _ = try await chat.completeWithTools(
                [AIChatMessage(role: .user, text: "hi")],
                provider: provider,
                maximumResults: 8,
                maximumRounds: 3
            )
            XCTFail("expected the loop to give up")
        } catch let error as AIChatError {
            if case .decoding = error { } else { XCTFail("unexpected \(error)") }
        }

        XCTAssertEqual(transport.requests.count, 3, "one request per permitted round")
    }

    func testSearchIsAlwaysOfferedWhenADirectProviderIsConfigured() async throws {
        let transport = MockAITransport(responses: [finalRound("Answered from the thread."), finalRound("Answered from the thread.")])
        let configuration = AIConfiguration(
            apiKey: "gc_key",
            directSearch: AIConfiguration.DirectSearchConfiguration(apiKey: "exa_key")
        )
        XCTAssertTrue(configuration.hasAnySearch)
        let client = AIChatClient(transport: transport, configuration: configuration)

        let posts = [Post(no: 1, time: Date(), commentHTML: "thread body")]
        let session = ThreadChatSession(client: client, posts: posts, summary: nil)

        // No globe toggle, no trigger words, and the tool is still offered.
        _ = try await session.ask("What did the OP mean?", history: [])

        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: transport.requests.first?.body ?? Data()) as? [String: Any]
        )
        XCTAssertNotNil(body["tools"], "offering a free-when-unused tool costs nothing")
        XCTAssertNil(body["plugins"])
    }
}
