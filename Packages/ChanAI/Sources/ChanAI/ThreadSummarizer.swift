import ChanAPI
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
    /// Post numbers the summary cites as `>>N`, filtered to posts that exist.
    public let citedPosts: [PostNumber]
    public let postCount: Int
    /// 1 means it fit in a single request; more means a map-reduce pass ran.
    public let chunkCount: Int
    public let imageCount: Int
    public let generatedAt: Date

    public init(
        board: BoardID,
        op: PostNumber,
        model: String,
        text: String,
        citedPosts: [PostNumber],
        postCount: Int,
        chunkCount: Int,
        imageCount: Int,
        generatedAt: Date
    ) {
        self.board = board
        self.op = op
        self.model = model
        self.text = text
        self.citedPosts = citedPosts
        self.postCount = postCount
        self.chunkCount = chunkCount
        self.imageCount = imageCount
        self.generatedAt = generatedAt
    }
}

/// Summarizes a thread with a multimodal model.
///
/// Long threads are map-reduced: each chunk is summarized, then the partials are
/// merged, so the context window is never the limit.
public struct ThreadSummarizer: Sendable {
    public struct Options: Sendable {
        public var style: SummaryStyle
        public var includeImages: Bool
        public var maximumImages: Int
        public var chunkCharacterLimit: Int

        public init(
            style: SummaryStyle = .bullets,
            includeImages: Bool = true,
            maximumImages: Int = 6,
            chunkCharacterLimit: Int = ThreadTranscript.defaultChunkCharacterLimit
        ) {
            self.style = style
            self.includeImages = includeImages
            self.maximumImages = maximumImages
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
        images: [AIImage] = [],
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws -> ThreadSummary {
        do {
            return try await run(board: board, op: op, posts: posts, images: images, onStatus: onStatus)
        } catch is CancellationError {
            throw AIChatError.cancelled
        }
    }

    private func run(
        board: BoardID,
        op: PostNumber,
        posts: [Post],
        images: [AIImage],
        onStatus: (@Sendable (String) -> Void)?
    ) async throws -> ThreadSummary {
        guard !posts.isEmpty else {
            throw AIChatError.decoding("There are no posts to summarize yet.")
        }

        let ordered = posts.sorted { $0.no < $1.no }
        let chunks = ThreadTranscript.chunks(ordered, characterLimit: options.chunkCharacterLimit)
        let usableImages = options.includeImages ? Array(images.prefix(options.maximumImages)) : []

        onStatus?("Reading \(ordered.count) posts…")
        try Task.checkCancellation()

        let text: String
        if chunks.count == 1 {
            onStatus?(usableImages.isEmpty ? "Summarizing…" : "Summarizing with \(usableImages.count) images…")
            let prompt = singlePassPrompt(
                transcript: ThreadTranscript.render(chunks[0]),
                imagePosts: usableImages.map(\.postNumber)
            )
            text = try await client.complete([
                Self.systemMessage,
                AIChatMessage(role: .user, text: prompt, images: usableImages),
            ])
        } else {
            var partials: [String] = []
            for (index, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                onStatus?("Summarizing part \(index + 1) of \(chunks.count)…")
                partials.append(
                    try await client.complete([
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
                )
            }

            try Task.checkCancellation()
            onStatus?("Combining \(chunks.count) summaries…")
            text = try await client.complete([
                Self.systemMessage,
                AIChatMessage(
                    role: .user,
                    text: reducePrompt(
                        partials: partials,
                        imagePosts: usableImages.map(\.postNumber)
                    ),
                    images: usableImages
                ),
            ])
        }

        let known = Set(ordered.map(\.no))
        return ThreadSummary(
            board: board,
            op: op,
            model: client.configuration.model,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            citedPosts: Self.citations(in: text).filter { known.contains($0) },
            postCount: ordered.count,
            chunkCount: chunks.count,
            imageCount: usableImages.count,
            generatedAt: Date()
        )
    }

    // MARK: - Prompts

    static let systemMessage = AIChatMessage(
        role: .system,
        text: """
        You summarize anonymous imageboard threads for a reader who has not opened them.
        Rules:
        - Use only what the transcript states. Never invent facts, quotes, names, dates or numbers.
        - Cite the post each point comes from as >>N.
        - Posters are anonymous; report their claims as claims, not as facts.
        - Be concise and neutral. No filler, no disclaimers, no moralising.
        - Write in plain text. Do not use headings or bullet characters other than "-".
        """
    )

    private func singlePassPrompt(transcript: String, imagePosts: [PostNumber]) -> String {
        var prompt = """
        Summarize this thread in \(options.style.instruction).

        Cover: the topic; the main points and who makes them; any disagreement; \
        notable media; and where the thread stands now.

        Cite posts as >>N.

        """
        if !imagePosts.isEmpty {
            prompt += "The most-discussed images are attached after this message, in this post order: "
            prompt += imagePosts.map { ">>\($0.value)" }.joined(separator: ", ")
            prompt += ". Describe what they show.\n\n"
        }
        prompt += "<thread>\n\(transcript)\n</thread>"
        return prompt
    }

    private func chunkPrompt(transcript: String, index: Int, total: Int) -> String {
        """
        This is part \(index) of \(total) of one thread, in chronological order.
        Summarize what is discussed in this part in at most 6 bullets, citing posts as >>N.
        Ignore anything that only makes sense with later parts.

        <thread-part>
        \(transcript)
        </thread-part>
        """
    }

    private func reducePrompt(partials: [String], imagePosts: [PostNumber]) -> String {
        var prompt = """
        Below are summaries of consecutive parts of a single thread, in order.
        Merge them into one summary in \(options.style.instruction), keeping the >>N citations.
        Remove repetition. Keep the strongest points and any unresolved disagreement.

        """
        if !imagePosts.isEmpty {
            prompt += "The most-discussed images are attached after this message, in this post order: "
            prompt += imagePosts.map { ">>\($0.value)" }.joined(separator: ", ")
            prompt += ". Describe what they show.\n\n"
        }
        for (index, partial) in partials.enumerated() {
            prompt += "<part-\(index + 1)>\n\(partial)\n</part-\(index + 1)>\n\n"
        }
        return prompt
    }

    // MARK: - Citations

    /// Extracts `>>N` citations in first-appearance order.
    public static func citations(in text: String) -> [PostNumber] {
        guard let regex = try? NSRegularExpression(pattern: ">>\\s*(\\d+)") else { return [] }

        let subject = text as NSString
        var seen = Set<PostNumber>()
        var result: [PostNumber] = []

        for match in regex.matches(in: text, range: NSRange(location: 0, length: subject.length)) {
            guard match.numberOfRanges > 1,
                  let value = Int(subject.substring(with: match.range(at: 1))),
                  value > 0 else { continue }
            let number = PostNumber(value)
            if seen.insert(number).inserted {
                result.append(number)
            }
        }
        return result
    }
}
