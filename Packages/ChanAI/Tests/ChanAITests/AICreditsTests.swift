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
            search: AIConfiguration.SearchConfiguration(apiKey: "or", maximumResults: 10, engine: .parallelTurbo)
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
