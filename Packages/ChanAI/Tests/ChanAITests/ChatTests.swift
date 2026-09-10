import ChanAPI
import ChanCore
import Foundation
import XCTest
@testable import ChanAI

// MARK: - Helpers (file-local: the shared ones in ChanAITests.swift are private)

private func chatResponse(
    _ text: String,
    model: String = "google/gemini-2.5-flash-lite",
    citations: [(String, String)] = []
) -> ChanHTTPResponse {
    var message: [String: Any] = ["content": text]
    if !citations.isEmpty {
        message["annotations"] = citations.map {
            ["type": "url_citation", "url_citation": ["url": $0.1, "title": $0.0]]
        }
    }
    let payload: [String: Any] = ["model": model, "choices": [["message": message]]]
    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    return ChanHTTPResponse(statusCode: 200, body: data)
}

private func chatPost(_ no: Int, op: Int = 0, comment: String, subject: String? = nil) -> Post {
    Post(
        no: PostNumber(no),
        resto: PostNumber(op),
        time: Date(timeIntervalSince1970: TimeInterval(no)),
        subject: subject,
        commentHTML: comment
    )
}

private func body(of request: ChanHTTPRequest) -> [String: Any] {
    guard let data = request.body,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
}

// MARK: - Search routing

final class AIChatSearchTests: XCTestCase {
    private func client(_ responses: [ChanHTTPResponse]) -> (AIChatClient, MockAITransport) {
        let transport = MockAITransport(responses: responses)
        let configuration = AIConfiguration(
            apiKey: "gc_primary",
            search: AIConfiguration.SearchConfiguration(apiKey: "or_search", maximumResults: 3)
        )
        return (AIChatClient(transport: transport, configuration: configuration), transport)
    }

    func testPlainTurnUsesThePrimaryEndpointWithNoPlugin() async throws {
        let (chat, transport) = client([chatResponse("plain", model: "gemma-4-31B-it")])
        let reply = try await chat.complete([AIChatMessage(role: .user, text: "hi")])

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://api.generalcompute.com/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer gc_primary")
        XCTAssertNil(body(of: request)["plugins"])
        XCTAssertFalse(reply.usedWebSearch)
    }

    func testSearchingTurnRoutesToTheSearchEndpointWithThePlugin() async throws {
        let (chat, transport) = client([
            chatResponse("3.14.7 is current", citations: [("Python Releases", "https://python.org/downloads")]),
        ])
        let reply = try await chat.complete([AIChatMessage(role: .user, text: "latest python?")], searching: true)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer or_search")
        XCTAssertNotNil(request.headers["X-Title"])

        let plugins = try XCTUnwrap(body(of: request)["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.first?["id"] as? String, "web")
        XCTAssertEqual(plugins.first?["max_results"] as? Int, 3)

        XCTAssertEqual(body(of: request)["model"] as? String, "google/gemini-2.5-flash-lite")
        XCTAssertTrue(reply.usedWebSearch)
        XCTAssertEqual(reply.sources, [AISource(title: "Python Releases", url: "https://python.org/downloads")])
    }

    func testSearchIsUnavailableWithoutASearchKey() async throws {
        let transport = MockAITransport(responses: [chatResponse("no search")])
        let chat = AIChatClient(
            transport: transport,
            configuration: AIConfiguration(apiKey: "gc_primary", search: nil)
        )
        XCTAssertFalse(chat.canSearch)

        let reply = try await chat.complete([AIChatMessage(role: .user, text: "hi")], searching: true)
        XCTAssertFalse(reply.usedWebSearch)
        XCTAssertEqual(transport.requests.first?.url.absoluteString,
                       "https://api.generalcompute.com/v1/chat/completions")
    }

    func testDuplicateCitationsAreCollapsed() async throws {
        let (chat, _) = client([
            chatResponse("x", citations: [
                ("A", "https://example.com"),
                ("A again", "https://example.com"),
                ("B", "https://other.example"),
            ]),
        ])
        let reply = try await chat.complete([AIChatMessage(role: .user, text: "q")], searching: true)
        XCTAssertEqual(reply.sources.map(\.url), ["https://example.com", "https://other.example"])
    }
}

// MARK: - Intent

final class SearchIntentTests: XCTestCase {
    func testDetectsLookupPhrasing() {
        XCTAssertTrue(SearchIntent.requiresWeb("search for the original paper"))
        XCTAssertTrue(SearchIntent.requiresWeb("what is the latest stable version?"))
        XCTAssertTrue(SearchIntent.requiresWeb("Google the author"))
        XCTAssertTrue(SearchIntent.requiresWeb("is it true that this was debunked?"))
        XCTAssertFalse(SearchIntent.requiresWeb("what did the OP mean by that?"))
        XCTAssertFalse(SearchIntent.requiresWeb("summarise the disagreement"))
    }

    func testDetectsRepliesThatAdmitTheyCannotKnow() {
        XCTAssertTrue(SearchIntent.needsEscalation("As of my knowledge cutoff, that was not released."))
        XCTAssertTrue(SearchIntent.needsEscalation("I don't have access to real-time data."))
        XCTAssertTrue(SearchIntent.needsEscalation("I cannot browse the web."))
        XCTAssertFalse(SearchIntent.needsEscalation("The thread says the rack is quiet now."))
    }
}

// MARK: - Session

final class ThreadChatSessionTests: XCTestCase {
    private func session(
        _ responses: [ChanHTTPResponse],
        posts: [Post] = [
            chatPost(1, comment: "Just rebuilt my homelab with two Proxmox nodes.", subject: "Rate my setup"),
            chatPost(2, op: 1, comment: "Two nodes is a bad idea for quorum."),
            chatPost(3, op: 1, comment: "Fair, adding a Pi as a QDevice."),
        ],
        searchKey: String? = "or_search"
    ) -> (ThreadChatSession, MockAITransport) {
        let transport = MockAITransport(responses: responses)
        let configuration = AIConfiguration(
            apiKey: "gc_primary",
            search: searchKey.map { AIConfiguration.SearchConfiguration(apiKey: $0) }
        )
        let client = AIChatClient(transport: transport, configuration: configuration)
        return (ThreadChatSession(client: client, posts: posts, summary: nil), transport)
    }

    func testGroundsTheQuestionInTheThreadTranscript() async throws {
        let (chat, transport) = session([chatResponse("The OP added a QDevice.", model: "gemma-4-31B-it")])
        let turn = try await chat.ask("What did the OP decide?", history: [])

        let messages = try XCTUnwrap(body(of: try XCTUnwrap(transport.requests.first))["messages"] as? [[String: Any]])
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(system.contains("Just rebuilt my homelab"))
        XCTAssertTrue(system.contains("Two nodes is a bad idea for quorum"))
        XCTAssertTrue(system.contains("Ground every claim"))
        XCTAssertEqual(messages.last?["content"] as? String, "What did the OP decide?")

        XCTAssertEqual(turn.role, .assistant)
        XCTAssertEqual(turn.text, "The OP added a QDevice.")
        XCTAssertFalse(turn.usedWebSearch)
    }

    func testPriorTurnsAreReplayedInOrder() async throws {
        let (chat, transport) = session([chatResponse("Yes, the UPS one.", model: "gemma-4-31B-it")])
        let history = [
            ChatTurn.user("Who complained about noise?"),
            ChatTurn(role: .assistant, text: "A poster mentioned the UPS fan."),
        ]
        _ = try await chat.ask("Was that resolved?", history: history)

        let messages = try XCTUnwrap(body(of: try XCTUnwrap(transport.requests.first))["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 4, "system + two history turns + the question")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[2]["role"] as? String, "assistant")
        XCTAssertEqual(messages[2]["content"] as? String, "A poster mentioned the UPS fan.")
    }

    func testLookupQuestionsSearchWithoutBeingToldTo() async throws {
        let (chat, transport) = session([chatResponse("Python 3.14.7.", citations: [("Python", "https://python.org")])])
        let turn = try await chat.ask("Search for the latest Proxmox release", history: [])

        XCTAssertEqual(transport.requests.first?.url.absoluteString,
                       "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertTrue(turn.usedWebSearch)
        XCTAssertEqual(turn.sources.count, 1)
    }

    func testAReplyThatAdmitsItCannotKnowIsRetriedWithSearch() async throws {
        let (chat, transport) = session([
            chatResponse("As of my knowledge cutoff I cannot confirm that."),
            chatResponse("It was released last week.", citations: [("News", "https://news.example")]),
        ])
        let turn = try await chat.ask("Did the new version ship?", history: [])

        XCTAssertEqual(transport.requests.count, 2, "the first reply should trigger one search retry")
        XCTAssertEqual(transport.requests[1].url.absoluteString,
                       "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertTrue(turn.usedWebSearch)
        XCTAssertEqual(turn.text, "It was released last week.")
        XCTAssertEqual(turn.sources.first?.url, "https://news.example")
    }

    func testNoRetryWhenSearchIsNotConfigured() async throws {
        let (chat, transport) = session(
            [chatResponse("As of my knowledge cutoff I cannot confirm that.", model: "gemma-4-31B-it")],
            searchKey: nil
        )
        let turn = try await chat.ask("Did the new version ship?", history: [])

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertFalse(turn.usedWebSearch)
    }

    func testEmptyQuestionIsRejectedLocally() async {
        let (chat, transport) = session([chatResponse("never")])
        do {
            _ = try await chat.ask("   ", history: [])
            XCTFail("expected rejection")
        } catch let error as AIChatError {
            if case .decoding = error { } else { XCTFail("unexpected \(error)") }
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testEarlierSummaryIsCarriedIntoTheContext() async throws {
        let transport = MockAITransport(responses: [chatResponse("ok", model: "gemma-4-31B-it")])
        let client = AIChatClient(transport: transport, configuration: AIConfiguration(apiKey: "gc_primary"))
        let summary = ThreadSummary(
            board: "g", op: 1, model: "gemma-4-31B-it",
            text: "The thread is about a homelab rebuild.",
            postCount: 3, generatedAt: Date()
        )
        let chat = ThreadChatSession(
            client: client,
            posts: [chatPost(1, comment: "homelab")],
            summary: summary
        )
        _ = try await chat.ask("What is it about?", history: [])

        let messages = try XCTUnwrap(body(of: try XCTUnwrap(transport.requests.first))["messages"] as? [[String: Any]])
        XCTAssertTrue((messages.first?["content"] as? String)?.contains("The thread is about a homelab rebuild.") == true)
        _ = chat
    }
}

// MARK: - Budgeted context

final class ThreadTranscriptContextTests: XCTestCase {
    private func posts(_ count: Int, commentLength: Int) -> [Post] {
        (1...count).map { chatPost($0, op: $0 == 1 ? 0 : 1, comment: String(repeating: "w", count: commentLength)) }
    }

    func testShortThreadsAreReturnedWhole() {
        let posts = posts(3, commentLength: 20)
        XCTAssertEqual(ThreadTranscript.context(posts, characterLimit: 10_000), ThreadTranscript.render(posts))
    }

    func testLongThreadsKeepTheOPAndTheTailAndSayWhatWasDropped() {
        let posts = posts(60, commentLength: 400)
        let context = ThreadTranscript.context(posts, characterLimit: 3_000)

        XCTAssertLessThan(context.count, 3_600)
        XCTAssertTrue(context.contains(">>1"), "the OP must always survive")
        XCTAssertTrue(context.contains(">>60"), "the newest post must survive")
        XCTAssertFalse(context.contains(">>30"), "the middle should be dropped")
        XCTAssertTrue(context.contains("earlier posts omitted"), "the omission must be stated")
    }

    func testEmptyThreadYieldsAnEmptyContext() {
        XCTAssertEqual(ThreadTranscript.context([], characterLimit: 1_000), "")
    }
}
