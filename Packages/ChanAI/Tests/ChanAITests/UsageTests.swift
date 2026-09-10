import ChanAPI
import ChanCore
import Foundation
import XCTest
@testable import ChanAI

private func response(text: String, model: String, usage: [String: Int]?) -> ChanHTTPResponse {
    var payload: [String: Any] = [
        "model": model,
        "choices": [["message": ["content": text]]],
    ]
    if let usage {
        payload["usage"] = [
            "prompt_tokens": usage["prompt"] ?? 0,
            "completion_tokens": usage["completion"] ?? 0,
            "total_tokens": usage["total"] ?? 0,
            // The endpoint also reports latency and throughput here.
            "total_latency": 0.8,
            "completion_tokens_per_sec": 19.8,
        ]
    }
    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    return ChanHTTPResponse(statusCode: 200, body: data)
}

final class AIUsageTests: XCTestCase {
    func testUsageAddsUp() {
        let a = AIUsage(promptTokens: 10, completionTokens: 4, totalTokens: 14)
        let b = AIUsage(promptTokens: 1, completionTokens: 2, totalTokens: 3)
        XCTAssertEqual(a + b, AIUsage(promptTokens: 11, completionTokens: 6, totalTokens: 17))
    }

    func testPricedModelCostsAreComputed() {
        let usage = AIUsage(promptTokens: 1_000_000, completionTokens: 1_000_000, totalTokens: 2_000_000)
        let cost = AIPricing.estimatedCost(usage, model: "deepseek-v3.2")
        XCTAssertEqual(try XCTUnwrap(cost), 0.25 + 0.38, accuracy: 0.0001)
    }

    func testUnpricedModelsReturnNoEstimate() {
        let usage = AIUsage(promptTokens: 500, completionTokens: 500, totalTokens: 1_000)
        XCTAssertNil(
            AIPricing.estimatedCost(usage, model: "gemma-4-31B-it"),
            "Gemma's price is not published, so no dollar figure should be invented"
        )
        XCTAssertNil(AIPricing.rate(for: "gemma-4-31B-it"))
    }

    func testCostFormatting() {
        XCTAssertEqual(AIPricing.format(0), "$0.00")
        XCTAssertEqual(AIPricing.format(0.0031), "$0.0031")
        XCTAssertEqual(AIPricing.format(1.239), "$1.24")
    }
}

final class AIUsageReportingTests: XCTestCase {
    func testClientSurfacesUsageFromTheResponse() async throws {
        let transport = MockAITransport(responses: [
            response(text: "hi", model: "gemma-4-31B-it", usage: ["prompt": 16, "completion": 1, "total": 17]),
        ])
        let client = AIChatClient(transport: transport, configuration: AIConfiguration(apiKey: "gc_test"))
        let reply = try await client.complete([AIChatMessage(role: .user, text: "hi")])

        XCTAssertEqual(reply.usage, AIUsage(promptTokens: 16, completionTokens: 1, totalTokens: 17))
    }

    func testMissingUsageIsTolerated() async throws {
        let transport = MockAITransport(responses: [response(text: "hi", model: "m", usage: nil)])
        let client = AIChatClient(transport: transport, configuration: AIConfiguration(apiKey: "gc_test"))
        let reply = try await client.complete([AIChatMessage(role: .user, text: "hi")])
        XCTAssertNil(reply.usage)
    }

    func testSummaryAggregatesUsageAcrossEveryChunk() async throws {
        let posts = (1...30).map { index in
            Post(
                no: PostNumber(index),
                resto: PostNumber(index == 1 ? 0 : 1),
                time: Date(timeIntervalSince1970: TimeInterval(index)),
                commentHTML: String(repeating: "w", count: 300)
            )
        }
        let limit = 400
        let chunks = ThreadTranscript.chunks(posts, characterLimit: limit).count

        // One response per chunk plus the reduce pass, each reporting 100 tokens.
        let responses = (0...chunks).map { index in
            response(text: "part \(index)", model: "gemma-4-31B-it",
                     usage: ["prompt": 60, "completion": 40, "total": 100])
        }
        let transport = MockAITransport(responses: responses)
        let client = AIChatClient(transport: transport, configuration: AIConfiguration(apiKey: "gc_test"))
        let summarizer = ThreadSummarizer(
            client: client,
            options: ThreadSummarizer.Options(chunkCharacterLimit: limit)
        )

        let summary = try await summarizer.summarize(board: "g", op: 1, posts: posts)

        XCTAssertEqual(transport.requests.count, chunks + 1)
        XCTAssertEqual(summary.usage?.totalTokens, (chunks + 1) * 100,
                       "every request the summary needed must be counted")
    }

    func testReplyWithoutUsageLeavesTheSummaryUncounted() async throws {
        let transport = MockAITransport(responses: [response(text: "ok", model: "m", usage: nil)])
        let client = AIChatClient(transport: transport, configuration: AIConfiguration(apiKey: "gc_test"))
        let summary = try await ThreadSummarizer(client: client).summarize(
            board: "g", op: 1,
            posts: [Post(no: 1, time: Date(), commentHTML: "x")]
        )
        XCTAssertNil(summary.usage)
    }

    func testChatTurnRecordsTheModelThatAnswered() async throws {
        let transport = MockAITransport(responses: [
            response(text: "answered", model: "google/gemini-2.5-flash-lite",
                     usage: ["prompt": 10, "completion": 5, "total": 15]),
        ])
        let configuration = AIConfiguration(
            apiKey: "gc_primary",
            search: AIConfiguration.SearchConfiguration(apiKey: "or_search", mode: .plugin)
        )
        let client = AIChatClient(transport: transport, configuration: configuration)
        let session = ThreadChatSession(
            client: client,
            posts: [Post(no: 1, time: Date(), commentHTML: "x")],
            summary: nil
        )

        let turn = try await session.ask("latest news?", history: [])

        XCTAssertEqual(turn.model, "google/gemini-2.5-flash-lite")
        XCTAssertEqual(turn.usage?.totalTokens, 15)
        XCTAssertTrue(turn.usedWebSearch)
    }

    func testCachedSummariesWithoutUsageStillDecode() throws {
        // A summary written before usage tracking existed must not be discarded.
        let legacy = """
        {"board":"g","op":1,"model":"gemma-4-31B-it","text":"old","postCount":3,
         "generatedAt":770000000}
        """
        let decoded = try JSONDecoder().decode(ThreadSummary.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.text, "old")
        XCTAssertNil(decoded.usage)
    }
}
