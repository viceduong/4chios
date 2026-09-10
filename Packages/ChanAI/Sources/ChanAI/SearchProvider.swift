import ChanAPI
import ChanCore
import Foundation

/// One search result, with the page text the model needs to reason about it.
public struct SearchResult: Sendable, Equatable, Codable {
    public let title: String
    public let url: String
    public let text: String

    public init(title: String, url: String, text: String) {
        self.title = title
        self.url = url
        self.text = text
    }
}

/// A search response plus what it cost, when the provider says.
public struct SearchResponse: Sendable, Equatable {
    public let results: [SearchResult]
    /// Providers that report a price (Exa does) let spend be measured rather
    /// than estimated.
    public let costUSD: Double?

    public init(results: [SearchResult], costUSD: Double? = nil) {
        self.results = results
        self.costUSD = costUSD
    }

    /// Compact form handed back to the model as the tool result.
    public var toolPayload: String {
        let payload = results.map { ["title": $0.title, "url": $0.url, "text": $0.text] }
        guard let data = try? JSONSerialization.data(withJSONObject: ["results": payload]),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"results":[]}"#
        }
        return json
    }
}

public enum SearchError: Error, Equatable, Sendable {
    case notConfigured
    case http(status: Int, message: String)
    case decoding(String)
    case transport(String)

    public var userMessage: String {
        switch self {
        case .notConfigured:
            return "Add a search API key in Settings."
        case let .http(status, message):
            if status == 401 || status == 403 { return "The search API rejected the key." }
            if status == 429 { return "The search API is rate limiting or out of quota." }
            return "The search API returned \(status). \(message)"
        case let .decoding(detail):
            return "Could not read the search response: \(detail)"
        case let .transport(detail):
            return detail
        }
    }
}

/// A web search backend the app calls directly, instead of renting one through
/// OpenRouter.
public protocol SearchProviding: Sendable {
    func search(_ query: String, limit: Int) async throws -> SearchResponse
}

/// Exa's own API.
///
/// Same engine and the same $0.007 list price OpenRouter resells, but the free
/// tier ($10/month after signup credit) applies here rather than to a reseller.
/// The response reports `costDollars`, so spend is measured exactly.
public struct ExaSearchProvider: SearchProviding {
    public static let defaultBaseURL = URL(string: "https://api.exa.ai")!
    /// Exa's auto mode: keyword plus neural, which is what `auto` resolves to.
    public static let listRatePerRequest = 0.007

    private let baseURL: URL
    private let apiKey: String
    private let transport: ChanTransport

    public init(
        apiKey: String,
        baseURL: URL = ExaSearchProvider.defaultBaseURL,
        transport: ChanTransport = URLSessionTransport()
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.transport = transport
    }

    public var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func search(_ query: String, limit: Int) async throws -> SearchResponse {
        guard isConfigured else { throw SearchError.notConfigured }

        let body = SearchRequest(
            query: query,
            numResults: limit,
            contents: .init(text: .init(maxCharacters: ExaSearchProvider.maximumCharactersPerResult))
        )

        let request = ChanHTTPRequest(
            url: baseURL.appendingPathComponent("search"),
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json",
                "x-api-key": apiKey,
            ],
            body: try JSONEncoder().encode(body)
        )

        let response: ChanHTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as ChanError {
            throw SearchError.transport(error.errorDescription ?? "Search request failed.")
        }

        guard response.isSuccess else {
            throw SearchError.http(
                status: response.statusCode,
                message: String(decoding: response.body.prefix(200), as: UTF8.self)
            )
        }

        do {
            let decoded = try JSONDecoder().decode(SearchResponseBody.self, from: response.body)
            return SearchResponse(
                results: decoded.results.map {
                    SearchResult(title: $0.title ?? "", url: $0.url, text: $0.text ?? "")
                },
                costUSD: decoded.costDollars?.total
            )
        } catch {
            throw SearchError.decoding(String(describing: error))
        }
    }

    /// Roughly 4,000 characters, the same order Exa returns to OpenRouter.
    static let maximumCharactersPerResult = 4_000
}

// MARK: - Wire types

private struct SearchRequest: Encodable {
    let query: String
    let numResults: Int
    let contents: Contents

    enum CodingKeys: String, CodingKey {
        case query, contents
        case numResults = "numResults"
    }

    struct Contents: Encodable {
        let text: Text

        struct Text: Encodable {
            let maxCharacters: Int
        }
    }
}

private struct SearchResponseBody: Decodable {
    struct Result: Decodable {
        let title: String?
        let url: String
        let text: String?
    }

    struct CostDollars: Decodable {
        let total: Double?
    }

    let results: [Result]
    let costDollars: CostDollars?
}
