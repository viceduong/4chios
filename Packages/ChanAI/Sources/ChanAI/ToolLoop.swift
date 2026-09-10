import ChanAPI
import ChanCore
import Foundation

/// Search as a client-side tool.
///
/// General Compute supports function calling (verified), so the model can ask
/// for a search and the app runs it against any `SearchProviding` backend. That
/// keeps one model across summary, chat and search, instead of handing search
/// turns to a second provider.
struct ToolLoop {
    struct ToolCall: Sendable, Equatable {
        let id: String
        let name: String
        let arguments: String

        /// The `query` argument, when the model produced valid JSON.
        var query: String? {
            guard let data = arguments.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let query = (object["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (query?.isEmpty == false) ? query : nil
        }
    }

    enum Message: Sendable {
        case system(String)
        case user(String)
        case assistant(text: String, toolCalls: [ToolCall])
        case tool(id: String, name: String, content: String)
    }

    /// What one round of the loop produced.
    struct Round: Sendable {
        let text: String?
        let toolCalls: [ToolCall]
        let usage: AIUsage?
        let annotations: [AISource]
    }
}

// MARK: - Encoding

extension ToolLoop {
    /// The `web_search` function offered to the model.
    static var functionTool: FunctionTool {
        FunctionTool(
            function: .init(
                name: "web_search",
                description: "Search the web for current information the thread does not contain.",
                parameters: .init(
                    properties: [
                        "query": .init(
                            type: "string",
                            description: "The search query. Be specific."
                        ),
                    ],
                    required: ["query"]
                )
            )
        )
    }

    struct Request: Encodable {
        let model: String
        let messages: [EncodedMessage]
        let maxTokens: Int
        let temperature: Double
        let stream: Bool
        let tools: [FunctionTool]?

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature, stream, tools
            case maxTokens = "max_tokens"
        }
    }

    static func encode(_ messages: [Message]) throws -> Data {
        try JSONEncoder().encode(messages.map(EncodedMessage.init))
    }

    struct FunctionTool: Encodable {
        let type = "function"
        let function: Function

        struct Function: Encodable {
            let name: String
            let description: String
            let parameters: Parameters

            struct Parameters: Encodable {
                let type = "object"
                let properties: [String: Property]
                let required: [String]

                struct Property: Encodable {
                    let type: String
                    let description: String
                }
            }
        }
    }

    struct EncodedMessage: Encodable {
        let role: String
        let content: String?
        let toolCalls: [EncodedToolCall]?
        let toolCallId: String?
        let name: String?

        init(_ message: Message) {
            switch message {
            case let .system(text):
                role = "system"
                content = text
                toolCalls = nil
                toolCallId = nil
                name = nil
            case let .user(text):
                role = "user"
                content = text
                toolCalls = nil
                toolCallId = nil
                name = nil
            case let .assistant(text, calls):
                role = "assistant"
                content = text
                toolCalls = calls.map(EncodedToolCall.init)
                toolCallId = nil
                name = nil
            case let .tool(id, name, content):
                role = "tool"
                self.content = content
                toolCalls = nil
                toolCallId = id
                self.name = name
            }
        }

        enum CodingKeys: String, CodingKey {
            case role, content, name
            case toolCalls = "tool_calls"
            case toolCallId = "tool_call_id"
        }
    }

    struct EncodedToolCall: Encodable {
        let id: String
        let type = "function"
        let function: Function

        struct Function: Encodable {
            let name: String
            let arguments: String
        }

        init(_ call: ToolCall) {
            id = call.id
            function = Function(name: call.name, arguments: call.arguments)
        }
    }
}

// MARK: - Decoding

extension ToolLoop {
    struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let toolCalls: [RawToolCall]?
                let annotations: [Annotation]?

                enum CodingKeys: String, CodingKey {
                    case content, annotations
                    case toolCalls = "tool_calls"
                }
            }
            let message: Message
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }

        struct RawToolCall: Decodable {
            let id: String?
            let function: Function?

            struct Function: Decodable {
                let name: String?
                let arguments: String?
            }
        }

        let model: String?
        let choices: [Choice]
        let usage: Usage?

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

        var round: Round? {
            guard let choice = choices.first else { return nil }
            let calls = (choice.message.toolCalls ?? []).compactMap { raw -> ToolCall? in
                guard let name = raw.function?.name, let arguments = raw.function?.arguments else { return nil }
                return ToolCall(id: raw.id ?? UUID().uuidString, name: name, arguments: arguments)
            }
            return Round(
                text: choice.message.content,
                toolCalls: calls,
                usage: usage?.normalised,
                annotations: (choice.message.annotations ?? []).compactMap { annotation in
                    guard annotation.type == "url_citation",
                          let citation = annotation.urlCitation,
                          let url = citation.url else { return nil }
                    return AISource(title: citation.title ?? "", url: url)
                }
            )
        }
    }
}
