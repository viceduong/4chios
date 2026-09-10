import ChanCore
import Foundation

/// How the summary should read.
public enum SummaryStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case bullets
    case brief
    case arguments
    case timeline

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .bullets: return "Bullets"
        case .brief: return "Brief"
        case .arguments: return "Arguments"
        case .timeline: return "Timeline"
        }
    }

    var instruction: String {
        switch self {
        case .bullets:
            return "at most 8 bullets, most important first"
        case .brief:
            return "one short paragraph, no bullets"
        case .arguments:
            return "the positions being argued and who holds them, then any common ground"
        case .timeline:
            return "a short chronology of how the thread developed"
        }
    }
}

/// The result of summarizing one thread.
public struct ThreadSummary: Sendable, Codable, Equatable {
    public let board: BoardID
    public let op: PostNumber
    public let model: String
    public let text: String
    public let postCount: Int
    public let generatedAt: Date
    /// Tokens used across every request the summary needed. Optional so older
    /// cached summaries still decode.
    public let usage: AIUsage?

    public init(
        board: BoardID,
        op: PostNumber,
        model: String,
        text: String,
        postCount: Int,
        generatedAt: Date,
        usage: AIUsage? = nil
    ) {
        self.board = board
        self.op = op
        self.model = model
        self.text = text
        self.postCount = postCount
        self.generatedAt = generatedAt
        self.usage = usage
    }
}

/// Summarizes a thread's **text** with a chat model.
///
/// Long threads are map-reduced: each chunk is summarized, then the partials are
/// merged, so the context window is never the limit.
public struct ThreadSummarizer: Sendable {
    public struct Options: Sendable {
        public var style: SummaryStyle
        public var chunkCharacterLimit: Int

        public init(
            style: SummaryStyle = .bullets,
            chunkCharacterLimit: Int = ThreadTranscript.defaultChunkCharacterLimit
        ) {
            self.style = style
            self.chunkCharacterLimit = chunkCharacterLimit
        }
    }

    private let client: AIChatClient
    private let options: Options

    public init(client: AIChatClient, options: Options = Options()) {
        self.client = client
        self.options = options
    }

    public func summarize(
        board: BoardID,
        op: PostNumber,
        posts: [Post],
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws -> ThreadSummary {
        do {
            return try await run(board: board, op: op, posts: posts, onStatus: onStatus)
        } catch is CancellationError {
            throw AIChatError.cancelled
        }
    }

    private func run(
        board: BoardID,
        op: PostNumber,
        posts: [Post],
        onStatus: (@Sendable (String) -> Void)?
    ) async throws -> ThreadSummary {
        guard !posts.isEmpty else {
            throw AIChatError.decoding("There are no posts to summarize yet.")
        }

        let ordered = posts.sorted { $0.no < $1.no }
        let chunks = ThreadTranscript.chunks(ordered, characterLimit: options.chunkCharacterLimit)

        onStatus?("Summarizing…")
        try Task.checkCancellation()

        var spend = AIUsage.zero
        var spentAnything = false
        func tally(_ usage: AIUsage?) {
            guard let usage else { return }
            spend += usage
            spentAnything = true
        }

        let text: String
        if chunks.count == 1 {
            let reply = try await client.complete([
                Self.systemMessage,
                AIChatMessage(
                    role: .user,
                    text: singlePassPrompt(transcript: ThreadTranscript.render(chunks[0]))
                ),
            ])
            tally(reply.usage)
            text = reply.text
        } else {
            var partials: [String] = []
            for (index, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                let reply = try await client.complete([
                    Self.systemMessage,
                    AIChatMessage(
                        role: .user,
                        text: chunkPrompt(
                            transcript: ThreadTranscript.render(chunk),
                            index: index + 1,
                            total: chunks.count
                        )
                    ),
                ])
                tally(reply.usage)
                partials.append(reply.text)
            }

            try Task.checkCancellation()
            let reply = try await client.complete([
                Self.systemMessage,
                AIChatMessage(role: .user, text: reducePrompt(partials: partials)),
            ])
            tally(reply.usage)
            text = reply.text
        }

        return ThreadSummary(
            board: board,
            op: op,
            model: client.configuration.model,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            postCount: ordered.count,
            generatedAt: Date(),
            usage: spentAnything ? spend : nil
        )
    }

    // MARK: - Prompts

    static let systemMessage = AIChatMessage(
        role: .system,
        text: """
        You summarize anonymous imageboard threads for a reader who has not opened them.
        Rules:
        - Use only what the transcript states. Never invent facts, quotes, names, dates or numbers.
        - Do not cite post numbers. Write plain prose with no >> references.
        - Posters are anonymous; report their claims as claims, not as facts.
        - Be concise and neutral. No filler, no disclaimers, no moralising.
        - Write in plain text. Do not use headings or bullet characters other than "-".
        """
    )

    private func singlePassPrompt(transcript: String) -> String {
        """
        Summarize this thread in \(options.style.instruction).

        Cover: the topic; the main points and who makes them; any disagreement; \
        notable media mentioned; and where the thread stands now.

        <thread>
        \(transcript)
        </thread>
        """
    }

    private func chunkPrompt(transcript: String, index: Int, total: Int) -> String {
        """
        This is part \(index) of \(total) of one thread, in chronological order.
        Summarize what is discussed in this part in at most 6 bullets.
        Ignore anything that only makes sense with later parts.

        <thread-part>
        \(transcript)
        </thread-part>
        """
    }

    private func reducePrompt(partials: [String]) -> String {
        var prompt = """
        Below are summaries of consecutive parts of a single thread, in order.
        Merge them into one summary in \(options.style.instruction).
        Remove repetition. Keep the strongest points and any unresolved disagreement.

        """
        for (index, partial) in partials.enumerated() {
            prompt += "<part-\(index + 1)>\n\(partial)\n</part-\(index + 1)>\n\n"
        }
        return prompt
    }
}
