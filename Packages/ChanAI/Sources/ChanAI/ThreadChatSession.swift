import ChanAPI
import ChanCore
import Foundation

/// One message in a thread conversation.
public struct ChatTurn: Codable, Sendable, Equatable, Identifiable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public let id: UUID
    public let role: Role
    public let text: String
    public let sources: [AISource]
    public let usedWebSearch: Bool
    public let date: Date
    /// Tokens this turn cost, when the endpoint reported them.
    public let usage: AIUsage?
    /// The model that answered; search turns use a different one than plain ones.
    public let model: String

    public init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        sources: [AISource] = [],
        usedWebSearch: Bool = false,
        date: Date = Date(),
        usage: AIUsage? = nil,
        model: String = ""
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.sources = sources
        self.usedWebSearch = usedWebSearch
        self.date = date
        self.usage = usage
        self.model = model
    }

    public static func user(_ text: String) -> ChatTurn {
        ChatTurn(role: .user, text: text)
    }
}

/// A conversation about one thread.
///
/// The thread's text is the grounding context, so follow-up questions are
/// answered from what was actually posted rather than from the summary alone.
/// A turn can additionally be routed through a search-capable endpoint, and a
/// reply that admits it lacks current information is retried with search once.
public struct ThreadChatSession: Sendable {
    public struct Options: Sendable {
        /// Budget for the thread context carried on every turn.
        public var contextCharacterLimit: Int
        public var maximumTokens: Int

        public init(contextCharacterLimit: Int = 24_000, maximumTokens: Int = 900) {
            self.contextCharacterLimit = contextCharacterLimit
            self.maximumTokens = maximumTokens
        }
    }

    private let client: AIChatClient
    private let context: String
    private let options: Options

    public init(
        client: AIChatClient,
        posts: [Post],
        summary: ThreadSummary?,
        options: Options = Options()
    ) {
        self.client = client
        self.options = options
        self.context = Self.buildContext(
            posts: posts,
            summary: summary,
            characterLimit: options.contextCharacterLimit
        )
    }

    public var canSearch: Bool { client.canSearch }

    /// Answers a follow-up. `useWebSearch` forces search; otherwise obvious
    /// requests ("look this up", "latest…") enable it automatically, and a reply
    /// that says it cannot know is retried with search enabled.
    public func ask(
        _ question: String,
        history: [ChatTurn],
        useWebSearch: Bool = false
    ) async throws -> ChatTurn {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIChatError.decoding("Ask a question first.")
        }

        // In server-tool mode the tool is free when unused, so it is always
        // offered and the model decides for itself: no toggle to remember, and
        // no charge on turns that do not need the web.
        let alwaysOffered = client.canSearch && client.configuration.search?.mode == .serverTool
        let wantsSearch = alwaysOffered || (client.canSearch && (useWebSearch || SearchIntent.requiresWeb(trimmed)))

        // A server tool cannot be forced from the request, so an explicit
        // request becomes an instruction instead.
        let insist = alwaysOffered && useWebSearch
        let messages = self.messages(for: trimmed, history: history, insistingOnSearch: insist)

        var reply = try await client.complete(messages, searching: wantsSearch)
        var usedSearch = reply.usedWebSearch

        // When the tool was always available the model already had its chance,
        // so a retry would only spend money. Otherwise give it one more go with
        // search before accepting that it cannot answer.
        if !usedSearch, client.canSearch, !alwaysOffered, SearchIntent.needsEscalation(reply.text) {
            reply = try await client.complete(messages, searching: true)
            usedSearch = reply.usedWebSearch
        }

        return ChatTurn(
            role: .assistant,
            text: reply.text,
            sources: reply.sources,
            usedWebSearch: usedSearch,
            usage: reply.usage,
            model: reply.model
        )
    }

    // MARK: - Prompt assembly

    private func messages(
        for question: String,
        history: [ChatTurn],
        insistingOnSearch: Bool = false
    ) -> [AIChatMessage] {
        var messages: [AIChatMessage] = [AIChatMessage(role: .system, text: Self.systemPrompt(context: context))]

        // Keep the tail of the conversation; older turns add little and cost
        // tokens on every request.
        for turn in history.suffix(12) {
            messages.append(
                AIChatMessage(
                    role: turn.role == .user ? .user : .assistant,
                    text: turn.text
                )
            )
        }

        let prompt = insistingOnSearch
            ? "\(question)

(Use web search to check this before answering.)"
            : question
        messages.append(AIChatMessage(role: .user, text: prompt))
        return messages
    }

    static func systemPrompt(context: String) -> String {
        """
        You are answering follow-up questions about one imageboard thread.

        Rules:
        - Ground every claim about the thread in the transcript below. If the thread does not say it, do not imply that it does.
        - Say plainly when the thread does not contain the answer.
        - You may use outside knowledge, but make clear which parts are not from the thread.
        - Write plain prose. No post-number citations, no headings, no filler.
        - Be concise: answer the question that was asked.

        <thread>
        \(context)
        </thread>
        """
    }

    /// The OP plus the most recent posts, so a long thread still fits a budget.
    static func buildContext(posts: [Post], summary: ThreadSummary?, characterLimit: Int) -> String {
        let ordered = posts.sorted { $0.no < $1.no }
        var parts: [String] = []

        if let summary, !summary.text.isEmpty {
            parts.append("Earlier summary of this thread:\n\(summary.text)")
        }

        parts.append(ThreadTranscript.context(ordered, characterLimit: characterLimit))
        return parts.joined(separator: "\n\n")
    }
}
