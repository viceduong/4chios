import ChanAPI
import ChanCore
import Foundation

/// An image attached to a prompt, already encoded as JPEG by the platform layer.
public struct AIImage: Sendable, Equatable {
    public let postNumber: PostNumber
    public let data: Data
    public let mimeType: String

    public init(postNumber: PostNumber, data: Data, mimeType: String = "image/jpeg") {
        self.postNumber = postNumber
        self.data = data
        self.mimeType = mimeType
    }
}

public struct AIChatMessage: Sendable {
    public enum Role: String, Sendable {
        case system
        case user
        case assistant
    }

    public var role: Role
    public var text: String
    public var images: [AIImage]

    public init(role: Role, text: String, images: [AIImage] = []) {
        self.role = role
        self.text = text
        self.images = images
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
            return "Add an API key in Settings to use summaries."
        case let .http(status, message):
            if status == 401 || status == 403 { return "The AI endpoint rejected the API key." }
            if status == 429 { return "The AI endpoint is rate limiting; try again shortly." }
            return "The AI endpoint returned \(status). \(message)"
        case let .decoding(detail):
            return "Could not read the AI response: \(detail)"
        case let .transport(detail):
            return detail
        case .cancelled:
            return "Summary cancelled."
        }
    }
}

/// A minimal OpenAI-compatible chat client.
///
/// Deliberately non-streaming: a summary is a single request/response, and
/// progress is reported per chunk by the summarizer instead.
public struct AIChatClient: Sendable {
    private let transport: ChanTransport
    public let configuration: AIConfiguration

    public init(transport: ChanTransport = URLSessionTransport(), configuration: AIConfiguration) {
        self.transport = transport
        self.configuration = configuration
    }

    public func complete(_ messages: [AIChatMessage]) async throws -> String {
        guard configuration.isConfigured else { throw AIChatError.notConfigured }

        let body = try Self.encodeRequestBody(messages: messages, configuration: configuration)
        var headers = ["Content-Type": "application/json", "Accept": "application/json"]
        headers["Authorization"] = "Bearer \(configuration.apiKey)"

        let request = ChanHTTPRequest(
            url: configuration.chatCompletionsURL,
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
            guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
                throw AIChatError.decoding("The response contained no text.")
            }
            return text
        } catch let error as AIChatError {
            throw error
        } catch {
            throw AIChatError.decoding(String(describing: error))
        }
    }

    // MARK: - Encoding

    static func encodeRequestBody(messages: [AIChatMessage], configuration: AIConfiguration) throws -> Data {
        let payload = ChatCompletionRequest(
            model: configuration.model,
            messages: messages.map(RequestMessage.init),
            maxTokens: configuration.maximumTokens,
            temperature: configuration.temperature,
            stream: false
        )
        return try JSONEncoder().encode(payload)
    }
}

// MARK: - Wire types

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [RequestMessage]
    let maxTokens: Int
    let temperature: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

private struct RequestMessage: Encodable {
    let role: String
    let content: Content

    init(_ message: AIChatMessage) {
        role = message.role.rawValue
        content = message.images.isEmpty
            ? .text(message.text)
            : .parts(
                [.init(type: "text", text: message.text)]
                    + message.images.map { image in
                        .init(
                            type: "image_url",
                            imageURL: .init(url: "data:\(image.mimeType);base64,\(image.data.base64EncodedString())")
                        )
                    }
            )
    }

    /// `content` is either a bare string or an array of parts; OpenAI accepts both.
    enum Content: Encodable {
        case text(String)
        case parts([ContentPart])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .text(value):
                try container.encode(value)
            case let .parts(value):
                try container.encode(value)
            }
        }
    }

    struct ContentPart: Encodable {
        let type: String
        var text: String?
        var imageURL: ImageURL?

        enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }

        struct ImageURL: Encodable {
            let url: String
        }
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}
