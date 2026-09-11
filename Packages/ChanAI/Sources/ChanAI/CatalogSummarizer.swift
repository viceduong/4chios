import ChanCore
import Foundation

/// A one-line reading of a single thread within a board digest.
public struct CatalogThreadSummary: Sendable, Codable, Equatable, Identifiable {
    public let number: PostNumber
    public let line: String

    public var id: Int { number.value }

    public init(number: PostNumber, line: String) {
        self.number = number
        self.line = line
    }
}

/// The result of reading a whole board's catalog at once.
public struct CatalogSummary: Sendable, Codable, Equatable {
    public let board: BoardID
    public let model: String
    /// What the board is about right now, as prose.
    public let overview: String
    /// Per-thread one-liners. Only the threads the model judged worth naming.
    public let threads: [CatalogThreadSummary]
    public let threadCount: Int
    /// Which threads this covered, so staleness is an exact comparison rather
    /// than a guess from the count.
    public let coveredThreads: [Int]
    public let generatedAt: Date
    /// Tokens used across every request the digest needed.
    public let usage: AIUsage?

    public init(
        board: BoardID,
        model: String,
        overview: String,
        threads: [CatalogThreadSummary],
        threadCount: Int,
        coveredThreads: [Int],
        generatedAt: Date,
        usage: AIUsage?
    ) {
        self.board = board
        self.model = model
        self.overview = overview
        self.threads = threads
        self.threadCount = threadCount
        self.coveredThreads = coveredThreads
        self.generatedAt = generatedAt
        self.usage = usage
    }
}

/// Reads a whole board's catalog and reports what is going on.
///
/// A board can hold hundreds of threads, so the raw posts can never be sent. The
/// digest is a compact row per thread - number, subject, counters, the opening of
/// the body - which is what a reader needs to recognise one. That digest is then
/// map-reduced exactly like a long thread: each part is summarized, then the
/// partials are merged into one overview plus a line per notable thread.
public struct CatalogSummarizer: Sendable {
    public struct Options: Sendable {
        public var chunkCharacterLimit: Int
        public var openingCharacterLimit: Int

        public init(chunkCharacterLimit: Int = 20_000, openingCharacterLimit: Int = 320) {
            self.chunkCharacterLimit = chunkCharacterLimit
            self.openingCharacterLimit = openingCharacterLimit
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
        threads: [Post],
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws -> CatalogSummary {
        do {
            return try await run(board: board, threads: threads, onStatus: onStatus)
        } catch is CancellationError {
            throw AIChatError.cancelled
        }
    }

    private func run(
        board: BoardID,
        threads: [Post],
        onStatus: (@Sendable (String) -> Void)?
    ) async throws -> CatalogSummary {
        guard !threads.isEmpty else {
            throw AIChatError.decoding("This board has no threads to read yet.")
        }

        let ordered = threads.sorted { $0.no < $1.no }
        let known = Set(ordered.map(\.no.value))
        let lines = ordered.map { Self.digestLine($0, openingLimit: options.openingCharacterLimit) }
        let chunks = Self.chunks(lines, characterLimit: options.chunkCharacterLimit)

        onStatus?("Reading \(ordered.count) threads…")
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
                AIChatMessage(role: .user, text: finalPrompt(listing: chunks[0].joined(separator: "\n"))),
            ])
            tally(reply.usage)
            text = reply.text
        } else {
            var partials: [String] = []
            for (index, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                onStatus?("Part \(index + 1) of \(chunks.count)…")
                let reply = try await client.complete([
                    Self.systemMessage,
                    AIChatMessage(
                        role: .user,
                        text: partPrompt(
                            listing: chunk.joined(separator: "\n"),
                            index: index + 1,
                            total: chunks.count
                        )
                    ),
                ])
                tally(reply.usage)
                partials.append(reply.text)
            }

            try Task.checkCancellation()
            onStatus?("Merging…")
            let reply = try await client.complete([
                Self.systemMessage,
                AIChatMessage(role: .user, text: mergePrompt(partials: partials, threadCount: ordered.count)),
            ])
            tally(reply.usage)
            text = reply.text
        }

        let parsed = Self.parse(text, known: known)

        return CatalogSummary(
            board: board,
            model: client.configuration.model,
            overview: parsed.overview,
            threads: parsed.threads,
            threadCount: ordered.count,
            coveredThreads: ordered.map(\.no.value),
            generatedAt: Date(),
            usage: spentAnything ? spend : nil
        )
    }

    // MARK: - Digest

    /// One compact row per thread. Counters and the opening of the body are what
    /// make a thread recognisable without sending the whole post.
    static func digestLine(_ post: Post, openingLimit: Int) -> String {
        var parts: [String] = ["#\(post.no.value)"]

        if let subject = post.subject?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
            parts.append(subject)
        }

        var counters: [String] = []
        if let replies = post.replies { counters.append("R:\(replies)") }
        if let images = post.images { counters.append("I:\(images)") }
        if post.isSticky == true { counters.append("sticky") }
        if post.isClosed == true { counters.append("closed") }
        if !counters.isEmpty { parts.append(counters.joined(separator: " ")) }

        let body = PostHTMLParser.parse(post.commentHTML ?? "").plainText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if !body.isEmpty {
            parts.append(String(body.prefix(openingLimit)))
        }

        return parts.joined(separator: " | ")
    }

    /// Groups rows into parts under a character budget. A single row that exceeds
    /// the budget still forms its own part rather than being dropped.
    static func chunks(_ lines: [String], characterLimit: Int) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        var size = 0

        for line in lines {
            let cost = line.count + 1
            if !current.isEmpty, size + cost > characterLimit {
                result.append(current)
                current = []
                size = 0
            }
            current.append(line)
            size += cost
        }
        if !current.isEmpty { result.append(current) }

        return result
    }

    // MARK: - Prompts

    static let systemMessage = AIChatMessage(
        role: .system,
        text: """
        You read anonymous imageboard catalogs and tell a reader what is on the board.
        Rules:
        - Use only what the listing states. Never invent facts, quotes, names or numbers.
        - Cite a thread only by the number given in the listing, never a number you were not given.
        - Posters are anonymous; report their claims as claims, not as facts.
        - Be concise and neutral. No filler, no disclaimers, no moralising.
        - Write plain text. No headings other than the one label asked for.
        """
    )

    private func partPrompt(listing: String, index: Int, total: Int) -> String {
        """
        This is part \(index) of \(total) of one board's catalog listing, each line one thread.
        Say what is being posted about in this part, in at most 5 bullets.
        Ignore anything that only makes sense with later parts.

        <catalog-part>
        \(listing)
        </catalog-part>
        """
    }

    private func mergePrompt(partials: [String], threadCount: Int) -> String {
        var prompt = """
        Below are readings of consecutive parts of one board's catalog, in order.
        There are \(threadCount) threads in total.

        Write two things:
        1. An overview of what the board is about right now, in 3 to 5 sentences.
        2. Then a line reading exactly THREADS: and after it, one line per thread worth
           naming, in the form #12345678 - at most 12 words. Use only thread numbers that
           appear below. Omit threads that are not worth naming. If none are, omit the
           section entirely.

        """
        for (index, partial) in partials.enumerated() {
            prompt += "<part-\(index + 1)>\n\(partial)\n</part-\(index + 1)>\n\n"
        }
        return prompt
    }

    private func finalPrompt(listing: String) -> String {
        """
        This is one board's catalog, one line per thread.

        Write two things:
        1. An overview of what the board is about right now, in 3 to 5 sentences.
        2. Then a line reading exactly THREADS: and after it, one line per thread worth
           naming, in the form #12345678 - at most 12 words. Use only the thread numbers
           in the listing. Omit threads that are not worth naming. If none are, omit the
           section entirely.

        <catalog>
        \(listing)
        </catalog>
        """
    }

    // MARK: - Parsing

    /// Splits the reply into the overview and the per-thread lines.
    ///
    /// Best effort by design. A line that does not parse is dropped, and a number
    /// that was never in the listing is ignored, so the model cannot invent a
    /// thread that does not exist.
    static func parse(_ text: String, known: Set<Int>) -> (overview: String, threads: [CatalogThreadSummary]) {
        var overviewLines: [String] = []
        var found: [CatalogThreadSummary] = []
        var seen: Set<Int> = []
        var inThreadSection = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.uppercased().hasPrefix("THREADS") {
                inThreadSection = true
                continue
            }

            if let match = threadLine(line), known.contains(match.number) {
                inThreadSection = true
                if seen.insert(match.number).inserted {
                    found.append(CatalogThreadSummary(number: PostNumber(match.number), line: match.text))
                }
                continue
            }

            if !inThreadSection {
                overviewLines.append(String(rawLine))
            }
        }

        return (
            overviewLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            found
        )
    }

    /// Matches `#12345678 - something` and the near misses models produce:
    /// a missing hash, a colon instead of a dash, a leading bullet.
    static func threadLine(_ line: String) -> (number: Int, text: String)? {
        var remainder = Substring(line)

        // A bullet would otherwise stop the number from being found first.
        while let first = remainder.first, first == "-" || first == "*" || first == "•" {
            remainder = remainder.dropFirst().drop { $0 == " " }
        }

        if remainder.hasPrefix("#") { remainder = remainder.dropFirst() }

        let digits = remainder.prefix { $0.isNumber }
        guard digits.count >= 3, let number = Int(digits) else { return nil }

        var rest = remainder.dropFirst(digits.count).drop { $0 == " " }
        guard let separator = rest.first, "-–—:".contains(separator) else { return nil }

        rest = rest.dropFirst().drop { $0 == " " || $0 == "-" }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        return (number, text)
    }
}
