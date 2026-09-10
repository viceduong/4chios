import ChanAPI
import ChanAI
import Foundation
import XCTest
@testable import ChanAI

final class AICreditsTests: XCTestCase {
    private func client(_ responses: [ChanHTTPResponse]) -> (AICreditsClient, MockAITransport) {
        let transport = MockAITransport(responses: responses)
        return (AICreditsClient(transport: transport), transport)
    }

    private func creditsBody(credits: Double, usage: Double) -> Data {
        let payload: [String: Any] = ["data": ["total_credits": credits, "total_usage": usage]]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    func testParsesOpenRouterCreditsResponse() async throws {
        let (credits, transport) = client([
            ChanHTTPResponse(statusCode: 200, body: creditsBody(credits: 227, usage: 227.122772584)),
        ])
        let result = try await credits.credits(
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            apiKey: "or_key"
        )

        XCTAssertEqual(result.granted, 227, accuracy: 0.0001)
        XCTAssertEqual(result.used, 227.122772584, accuracy: 0.0001)
        XCTAssertEqual(result.remaining, -0.122772584, accuracy: 0.0001)
        XCTAssertTrue(result.isOverdrawn, "usage above the grant is an overdrawn balance")
        XCTAssertEqual(result.formattedRemaining, "-$0.12")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://openrouter.ai/api/v1/credits")
        XCTAssertEqual(request.headers["Authorization"], "Bearer or_key")
    }

    func testHealthyBalanceIsNotOverdrawn() async throws {
        let (credits, _) = client([
            ChanHTTPResponse(statusCode: 200, body: creditsBody(credits: 10, usage: 2.5)),
        ])
        let result = try await credits.credits(
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            apiKey: "or_key"
        )
        XCTAssertFalse(result.isOverdrawn)
        XCTAssertEqual(result.formattedRemaining, "$7.50")
    }

    func testMissingDataIsReported() async {
        let (credits, _) = client([ChanHTTPResponse(statusCode: 200, body: Data(#"{"data":null}"#.utf8))])
        do {
            _ = try await credits.credits(baseURL: URL(string: "https://openrouter.ai/api/v1")!, apiKey: "k")
            XCTFail("expected a decoding error")
        } catch let error as AIChatError {
            if case .decoding = error { } else { XCTFail("unexpected \(error)") }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testUnconfiguredKeyIsRejectedBeforeAnyRequest() async {
        let (credits, transport) = client([ChanHTTPResponse(statusCode: 200)])
        do {
            _ = try await credits.credits(baseURL: URL(string: "https://openrouter.ai/api/v1")!, apiKey: "  ")
            XCTFail("expected .notConfigured")
        } catch let error as AIChatError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testFormatting() {
        XCTAssertEqual(AICredits.format(0), "$0.00")
        XCTAssertEqual(AICredits.format(0.0031), "$0.0031")
        XCTAssertEqual(AICredits.format(-0.0031), "-$0.0031")
        XCTAssertEqual(AICredits.format(227.122), "$227.12")
    }
}

final class AISearchEngineTests: XCTestCase {
    private func pluginJSON(_ engine: AISearchEngine, maxResults: Int) throws -> [String: Any] {
        let data = try JSONEncoder().encode(SearchPlugin(engine: engine, maxResults: maxResults))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testExaAutoSendsNoEngineBecauseItIsTheProviderDefault() throws {
        let json = try pluginJSON(.exaAuto, maxResults: 10)
        XCTAssertEqual(json["id"] as? String, "web")
        XCTAssertEqual(json["max_results"] as? Int, 10)
        XCTAssertNil(json["engine"], "exa auto is the plugin default, so the key is omitted")
        XCTAssertNil(json["mode"])
    }

    func testParallelTurboEncodesEngineAndMode() throws {
        let json = try pluginJSON(.parallelTurbo, maxResults: 10)
        XCTAssertEqual(json["engine"] as? String, "parallel")
        XCTAssertEqual(json["mode"] as? String, "turbo")
    }

    func testParallelBasicAndPerplexity() throws {
        XCTAssertEqual(try pluginJSON(.parallelBasic, maxResults: 5)["mode"] as? String, "basic")
        XCTAssertEqual(try pluginJSON(.perplexity, maxResults: 5)["engine"] as? String, "perplexity")
        XCTAssertNil(try pluginJSON(.perplexity, maxResults: 5)["mode"])
    }

    func testTenResultsIsTheDefaultBecauseTheFeeIsFlat() {
        let configuration = AIConfiguration.SearchConfiguration(apiKey: "k")
        XCTAssertEqual(configuration.maximumResults, 10, "up to ten results cost the same as two")
        XCTAssertEqual(configuration.engine, .exaAuto)
    }

    func testCostLabelsMatchOpenRoutersPublishedRates() {
        XCTAssertEqual(AISearchEngine.exaAuto.costPerRequest, 0.007, accuracy: 0.0001)
        XCTAssertEqual(AISearchEngine.parallelTurbo.costPerRequest, 0.001, accuracy: 0.0001)
        XCTAssertEqual(AISearchEngine.exaAuto.costLabel, "$7 per 1,000 searches")
        XCTAssertEqual(AISearchEngine.parallelTurbo.costLabel, "$1 per 1,000 searches")
    }

    func testSearchingTurnSendsTheChosenEngine() async throws {
        let payload: [String: Any] = ["model": "m", "choices": [["message": ["content": "ok"]]]]
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let transport = MockAITransport(responses: [ChanHTTPResponse(statusCode: 200, body: body)])
        let configuration = AIConfiguration(
            apiKey: "gc",
            search: AIConfiguration.SearchConfiguration(
                apiKey: "or", maximumResults: 10, engine: .parallelTurbo, mode: .plugin
            )
        )
        let client = AIChatClient(transport: transport, configuration: configuration)
        _ = try await client.complete([AIChatMessage(role: .user, text: "q")], searching: true)

        let request = try XCTUnwrap(transport.requests.first)
        let decoded = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]
        )
        let plugins = try XCTUnwrap(decoded["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.first?["engine"] as? String, "parallel")
        XCTAssertEqual(plugins.first?["mode"] as? String, "turbo")
        XCTAssertEqual(plugins.first?["max_results"] as? Int, 10)
    }
}

final class AISearchModeTests: XCTestCase {
    private func body(_ configuration: AIConfiguration) async throws -> [String: Any] {
        let payload: [String: Any] = ["model": "m", "choices": [["message": ["content": "ok"]]],
                                      "usage": ["prompt_tokens": 5, "completion_tokens": 1]]
        let transport = MockAITransport(responses: [
            ChanHTTPResponse(statusCode: 200, body: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()),
        ])
        let client = AIChatClient(transport: transport, configuration: configuration)
        _ = try await client.complete([AIChatMessage(role: .user, text: "q")], searching: true)
        let request = try XCTUnwrap(transport.requests.first)
        return try XCTUnwrap(
            try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]
        )
    }

    private func configuration(_ mode: AISearchMode) -> AIConfiguration {
        AIConfiguration(
            apiKey: "gc",
            search: AIConfiguration.SearchConfiguration(
                apiKey: "or", maximumResults: 10, maximumTotalResults: 20,
                engine: .parallelTurbo, mode: mode
            )
        )
    }

    func testServerToolModeSendsToolsAndNoPlugin() async throws {
        let payload = try await body(configuration(.serverTool))

        XCTAssertNil(payload["plugins"], "the plugin must not be sent in server-tool mode")
        let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0]["type"] as? String, "openrouter:web_search")

        let parameters = try XCTUnwrap(tools[0]["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["engine"] as? String, "parallel")
        XCTAssertEqual(parameters["max_results"] as? Int, 10)
        XCTAssertEqual(parameters["max_total_results"] as? Int, 20)
    }

    func testPluginModeSendsPluginsAndNoTools() async throws {
        let payload = try await body(configuration(.plugin))

        XCTAssertNil(payload["tools"], "the server tool must not be sent in plugin mode")
        let plugins = try XCTUnwrap(payload["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.first?["id"] as? String, "web")
        XCTAssertEqual(plugins.first?["engine"] as? String, "parallel")
    }

    func testServerToolModeDoesNotClaimASearchWhenNothingWasCited() async throws {
        // "What is 2+2" style: the model answers without searching.
        let payload: [String: Any] = ["model": "m", "choices": [["message": ["content": "4"]]]]
        let transport = MockAITransport(responses: [
            ChanHTTPResponse(statusCode: 200, body: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()),
        ])
        let client = AIChatClient(transport: transport, configuration: configuration(.serverTool))
        let reply = try await client.complete([AIChatMessage(role: .user, text: "2+2?")], searching: true)

        XCTAssertFalse(reply.usedWebSearch, "no citations means no search was run")
        XCTAssertTrue(reply.sources.isEmpty)
    }

    func testServerToolModeReportsASearchWhenCited() async throws {
        let payload: [String: Any] = [
            "model": "m",
            "choices": [["message": [
                "content": "Python 3.14.7",
                "annotations": [["type": "url_citation",
                                 "url_citation": ["url": "https://python.org", "title": "Python"]]],
            ]]],
        ]
        let transport = MockAITransport(responses: [
            ChanHTTPResponse(statusCode: 200, body: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()),
        ])
        let client = AIChatClient(transport: transport, configuration: configuration(.serverTool))
        let reply = try await client.complete([AIChatMessage(role: .user, text: "python?")], searching: true)

        XCTAssertTrue(reply.usedWebSearch)
        XCTAssertEqual(reply.sources.first?.url, "https://python.org")
    }

    func testServerToolIsTheDefault() {
        let configuration = AIConfiguration.SearchConfiguration(apiKey: "k")
        XCTAssertEqual(configuration.mode, .serverTool,
                       "the model-decides path is free on turns that do not search")
        XCTAssertEqual(configuration.maximumTotalResults, 20)
    }

    func testAPlainTurnSendsNeitherPluginNorTool() async throws {
        let payload: [String: Any] = ["model": "m", "choices": [["message": ["content": "ok"]]]]
        let transport = MockAITransport(responses: [
            ChanHTTPResponse(statusCode: 200, body: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()),
        ])
        let client = AIChatClient(transport: transport, configuration: configuration(.serverTool))
        _ = try await client.complete([AIChatMessage(role: .user, text: "hi")], searching: false)

        let request = try XCTUnwrap(transport.requests.first)
        let decoded = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]
        )
        XCTAssertNil(decoded["tools"])
        XCTAssertNil(decoded["plugins"])
        XCTAssertEqual(request.url.absoluteString, "https://api.generalcompute.com/v1/chat/completions",
                       "a turn without search goes to the primary endpoint")
    }
}


final class AlwaysOfferedSearchTests: XCTestCase {
    private func session(
        _ responses: [ChanHTTPResponse],
        mode: AISearchMode
    ) -> (ThreadChatSession, MockAITransport) {
        let transport = MockAITransport(responses: responses)
        let configuration = AIConfiguration(
            apiKey: "gc_primary",
            search: AIConfiguration.SearchConfiguration(apiKey: "or_search", mode: mode)
        )
        let client = AIChatClient(transport: transport, configuration: configuration)
        return (
            ThreadChatSession(
                client: client,
                posts: [Post(no: 1, time: Date(), commentHTML: "thread body")],
                summary: nil
            ),
            transport
        )
    }

    private func answer(_ text: String) -> ChanHTTPResponse {
        let payload: [String: Any] = ["model": "m", "choices": [["message": ["content": text]]]]
        return ChanHTTPResponse(
            statusCode: 200,
            body: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        )
    }

    private func answerWithSource(_ text: String, url: String) -> ChanHTTPResponse {
        let message: [String: Any] = [
            "content": text,
            "annotations": [["type": "url_citation", "url_citation": ["url": url, "title": "Source"]]],
        ]
        let payload: [String: Any] = ["model": "m", "choices": [["message": message]]]
        return ChanHTTPResponse(
            statusCode: 200,
            body: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        )
    }

    private func decoded(_ request: ChanHTTPRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]) ?? [:]
    }

    func testServerToolIsOfferedEvenWithoutTogglingSearchOn() async throws {
        let (chat, transport) = session([answer("The thread says so.")], mode: .serverTool)
        _ = try await chat.ask("What did the OP mean?", history: [])

        let payload = decoded(try XCTUnwrap(transport.requests.first))
        XCTAssertNotNil(payload["tools"], "the costless-when-unused tool should always be available")
        XCTAssertNil(payload["plugins"])
    }

    func testPluginModeStillRequiresAnExplicitRequest() async throws {
        let (chat, transport) = session([answer("The thread says so.")], mode: .plugin)
        _ = try await chat.ask("What did the OP mean?", history: [])

        let payload = decoded(try XCTUnwrap(transport.requests.first))
        XCTAssertNil(payload["plugins"], "the plugin is not attached for an ordinary question")
        XCTAssertNil(payload["tools"])
    }

    func testPluginModeAttachesThePluginWhenAsked() async throws {
        let (chat, transport) = session([answer("Looked it up.")], mode: .plugin)
        _ = try await chat.ask("What did the OP mean?", history: [], useWebSearch: true)

        let payload = decoded(try XCTUnwrap(transport.requests.first))
        XCTAssertNotNil(payload["plugins"])
    }

    func testInsistingTurnsIntoAnInstructionInServerToolMode() async throws {
        let (chat, transport) = session([answer("Checked.")], mode: .serverTool)
        _ = try await chat.ask("Is that claim true?", history: [], useWebSearch: true)

        let payload = decoded(try XCTUnwrap(transport.requests.first))
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        let prompt = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(
            prompt.contains("Use web search"),
            "a server tool cannot be forced from the request, so it is asked for in the prompt"
        )
    }

    func testNoEscalationRetryWhenSearchWasAlwaysAvailable() async throws {
        // The model already had the tool and chose not to use it; retrying would
        // only spend money to hear the same answer.
        let (chat, transport) = session(
            [answer("The provided thread does not contain that information.")],
            mode: .serverTool
        )
        _ = try await chat.ask("What is the price?", history: [])

        XCTAssertEqual(transport.requests.count, 1)
    }

    func testEscalationStillHappensInPluginModeWhenSearchWasNotEnabled() async throws {
        let (chat, transport) = session(
            [
                answer("As of my knowledge cutoff I cannot confirm that."),
                answerWithSource("It shipped last week.", url: "https://news.example"),
            ],
            mode: .plugin
        )
        let turn = try await chat.ask("Did it ship?", history: [])

        XCTAssertEqual(transport.requests.count, 2, "the plugin path still escalates")
        XCTAssertTrue(turn.usedWebSearch)
    }

    func testTurboIsTheDefaultEngineBecauseItIsSevenTimesCheaper() {
        XCTAssertEqual(AIConfiguration.SearchConfiguration(apiKey: "k").engine, .parallelTurbo)
    }
}
