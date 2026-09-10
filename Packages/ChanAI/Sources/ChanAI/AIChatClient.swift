import ChanAPI
import ChanCore
import Foundation

public struct AIChatMessage: Sendable {
    public enum Role: String, Sendable {
        case system
        case user
        case assistant
    }

    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public enum AIChatError: Error, Equatable, Sendable {
    case notConfigured
    case http(status: Int, message: String)
    case decoding(String)
    case transport(String)
    case cancelled

    public var userMessage: String {
        switch self {
        case .notConfigured:
            return "Add an API key in Settings to use AI features."
        case let .http(status, message):
            if status == 401 || status == 403 { return "The AI endpoint rejected the API key." }
            if status == 402 { return "The web search endpoint is out of credit." }
            if status == 429 { return "The AI endpoint is rate limiting; try again shortly." }
            return "The AI endpoint returned \(status). \(message)"
        case let .decoding(detail):
            return "Could not read the AI response: \(detail)"
        case let .transport(detail):
            return detail
        case .cancelled:
            return "Cancelled."
        }
    }
}

/// A minimal OpenAI-compatible chat client.
///
/// It can answer from the prompt alone, or route a turn through a second,
/// search-capable endpoint (OpenRouter's `web` plugin) when a question needs
/// live information. Text only: summaries and follow-ups are built from post
/// text, so there is no image plumbing to keep working.
public struct AIChatClient: Sendable {
    private let transport: ChanTransport
    public let configuration: AIConfiguration

    public init(transport: ChanTransport = URLSessionTransport(), configuration: AIConfiguration) {
        self.transport = transport
        self.configuration = configuration
    }

    /// True when a search-capable endpoint is configured.
    public var canSearch: Bool {
        configuration.search?.isConfigured == true
    }

    /// Answers a conversation, optionally with live web results.
    ///
    /// When `searching` is true and a search endpoint is configured, the turn is
    /// sent there with the provider's search plugin enabled and any citations
    /// are returned as sources. Otherwise the plain endpoint answers.
    public func complete(_ messages: [AIChatMessage], searching: Bool = false) async throws -> AIChatReply {
        let useSearch = searching && canSearch
        let target = useSearch ? configuration.search : nil

        let baseURL = target?.baseURL ?? configuration.baseURL
        let apiKey = target?.apiKey ?? configuration.apiKey
        let model = target?.model ?? configuration.model

        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AIChatError.notConfigured
        }

        var headers = ["Content-Type": "application/json", "Accept": "application/json"]
        headers["Authorization"] = "Bearer \(apiKey)"
        if useSearch {
            // OpenRouter attributes traffic with these; harmless and helpful.
            headers["HTTP-Referer"] = "https://github.com/viceduong/4chios"
            headers["X-Title"] = "4chios"
        }

        let body = try Self.encodeRequestBody(
            messages: messages,
            model: model,
            maximumTokens: configuration.maximumTokens,
            temperature: configuration.temperature,
            search: useSearch ? target : nil
        )

        let request = ChanHTTPRequest(
            url: baseURL.appendingPathComponent("chat/completions"),
            method: "POST",
            headers: headers,
            body: body
        )

        let response: ChanHTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as ChanError {
            if case .cancelled = error { throw AIChatError.cancelled }
            throw AIChatError.transport(error.errorDescription ?? "Request failed.")
        }

        guard response.isSuccess else {
            throw AIChatError.http(
                status: response.statusCode,
                message: String(decoding: response.body.prefix(240), as: UTF8.self)
            )
        }

        do {
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: response.body)
            let choice = decoded.choices.first
            guard let text = choice?.message.content, !text.isEmpty else {
                throw AIChatError.decoding("The response contained no text.")
            }
            // With the plugin, a search always ran. With the server tool the
            // model decides, so citations are the evidence that it did.
            let sources = Self.sources(from: choice?.message.annotations ?? [])
            let searched = useSearch && (target?.mode == .plugin || !sources.isEmpty)

            return AIChatReply(
                text: text,
                sources: sources,
                model: decoded.model ?? model,
                usedWebSearch: searched,
                usage: decoded.usage?.normalised
            )
        } catch let error as AIChatError {
            throw error
        } catch {
            throw AIChatError.decoding(String(describing: error))
        }
    }

    // MARK: - Encoding

    static func encodeRequestBody(
        messages: [AIChatMessage],
        model: String,
        maximumTokens: Int,
        temperature: Double,
        search: AIConfiguration.SearchConfiguration?
    ) throws -> Data {
        let payload = ChatCompletionRequest(
            model: model,
            messages: messages.map { RequestMessage(role: $0.role.rawValue, content: $0.text) },
            maxTokens: maximumTokens,
            temperature: temperature,
            stream: false,
            plugins: search.filter { $0.mode == .plugin }
                .map { [SearchPlugin(engine: $0.engine, maxResults: $0.maximumResults)] },
            tools: search.filter { $0.mode == .serverTool }
                .map { [ServerTool(engine: $0.engine, maxResults: $0.maximumResults,
                                   maxTotalResults: $0.maximumTotalResults)] }
        )
        return try JSONEncoder().encode(payload)
    }

    static func sources(from annotations: [Annotation]) -> [AISource] {
        var seen = Set<String>()
        var sources: [AISource] = []

        for annotation in annotations where annotation.type == "url_citation" {
            guard let citation = annotation.urlCitation,
                  let url = citation.url,
                  !url.isEmpty,
                  seen.insert(url).inserted else { continue }
            sources.append(AISource(title: citation.title ?? "", url: url))
        }
        return sources
    }
}

// MARK: - Wire types

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [RequestMessage]
    let maxTokens: Int
    let temperature: Double
    let stream: Bool
    /// OpenRouter's `web` plugin path. Nil unless that mode is selected.
    let plugins: [SearchPlugin]?
    /// OpenRouter's `openrouter:web_search` server tool path.
    let tools: [ServerTool]?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, plugins, tools
        case maxTokens = "max_tokens"
    }
}

private struct RequestMessage: Encodable {
    let role: String
    let content: String
}

struct Annotation: Decodable {
    struct URLCitation: Decodable {
        let url: String?
        let title: String?
    }

    let type: String?
    let urlCitation: URLCitation?

    enum CodingKeys: String, CodingKey {
        case type
        case urlCitation = "url_citation"
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let annotations: [Annotation]?
        }
        let message: Message
    }

    let model: String?
    let choices: [Choice]
    let usage: Usage?

    /// The endpoint reports latency and throughput alongside the token counts;
    /// only the counts matter here.
    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }

        var normalised: AIUsage? {
            let prompt = promptTokens ?? 0
            let completion = completionTokens ?? 0
            guard prompt > 0 || completion > 0 else { return nil }
            return AIUsage(
                promptTokens: prompt,
                completionTokens: completion,
                totalTokens: totalTokens ?? (prompt + completion)
            )
        }
    }
}
