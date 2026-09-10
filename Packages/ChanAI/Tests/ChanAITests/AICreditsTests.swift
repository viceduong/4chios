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
