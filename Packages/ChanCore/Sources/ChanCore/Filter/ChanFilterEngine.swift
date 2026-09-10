import Foundation

/// Everything the engine needs to know about where a post lives.
public struct ChanFilterContext: Sendable {
    public let board: BoardID
    public let isWorkSafe: Bool
    public let myPosts: Set<PostNumber>
    public let opNumber: PostNumber?

    public init(
        board: BoardID,
        isWorkSafe: Bool = false,
        myPosts: Set<PostNumber> = [],
        opNumber: PostNumber? = nil
    ) {
        self.board = board
        self.isWorkSafe = isWorkSafe
        self.myPosts = myPosts
        self.opNumber = opNumber
    }
}

/// The combined verdict for one post.
public struct ChanFilterDecision: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let hide = ChanFilterDecision(rawValue: 1 << 0)
    public static let stub = ChanFilterDecision(rawValue: 1 << 1)
    public static let highlight = ChanFilterDecision(rawValue: 1 << 2)
}

/// Evaluates the user's rules against posts.
///
/// Pure logic: no UI, no storage, no networking — so the whole rule language is
/// unit-tested in the fast Linux lane.
public struct ChanFilterEngine: Sendable {
    /// A rule that matched, and on which field.
    public struct Match: Sendable {
        public let filter: ChanFilter
        public let field: ChanFilterField
    }

    /// Regex evaluation is bounded so a pathological pattern cannot stall the
    /// main thread while scrolling a thread.
    private static let maximumHaystackLength = 8_192
    private static let maximumPatternLength = 512

    private struct Compiled: Sendable {
        let filter: ChanFilter
        let expression: NSRegularExpression?
        let isValid: Bool
    }

    private struct Cache {
        var comment: String?
    }

    private let compiled: [Compiled]

    /// Rules whose pattern could not be compiled, surfaced in the editor so a
    /// typo is visible instead of silently doing nothing.
    public let invalidFilters: [ChanFilter]

    public init(filters: [ChanFilter]) {
        var built: [Compiled] = []
        var invalid: [ChanFilter] = []

        for filter in filters where filter.enabled {
            let (expression, isValid) = Self.compile(filter)
            if !isValid { invalid.append(filter) }
            built.append(Compiled(filter: filter, expression: expression, isValid: isValid))
        }

        compiled = built
        invalidFilters = invalid
    }

    public var isEmpty: Bool { compiled.isEmpty }

    // MARK: - Evaluation

    /// Every rule that matches this post, with the field that matched.
    public func matches(for post: Post, in context: ChanFilterContext) -> [Match] {
        guard !compiled.isEmpty else { return [] }

        var cache = Cache()
        var hits: [Match] = []

        for entry in compiled {
            guard entry.isValid else { continue }
            guard entry.filter.scope.allows(board: context.board, isWorkSafe: context.isWorkSafe) else { continue }

            for field in entry.filter.fields {
                guard let value = value(for: field, post: post, cache: &cache) else { continue }
                guard matches(entry, value: value) else { continue }
                hits.append(Match(filter: entry.filter, field: field))
                break
            }
        }

        return hits
    }

    public func decision(for post: Post, in context: ChanFilterContext) -> ChanFilterDecision {
        let hits = matches(for: post, in: context)
        guard !hits.isEmpty else { return [] }

        var decision: ChanFilterDecision = []
        for hit in hits {
            switch hit.filter.action {
            case .hidePost, .hideThread: decision.insert(.hide)
            case .stub: decision.insert(.stub)
            case .highlight: decision.insert(.highlight)
            }
        }

        // Hiding is strictly stronger than collapsing.
        if decision.contains(.hide) { decision.remove(.stub) }
        return decision
    }

    /// True when the OP of a thread should be hidden from the catalog.
    public func hidesThread(_ op: Post, in context: ChanFilterContext) -> Bool {
        decision(for: op, in: context).contains(.hide)
    }

    // MARK: - Field extraction

    private func value(for field: ChanFilterField, post: Post, cache: inout Cache) -> String? {
        switch field {
        case .subject:
            return post.subject
        case .name:
            return post.name
        case .comment:
            if let cached = cache.comment { return cached }
            let text = PostHTMLParser.parse(post.commentHTML ?? "").plainText
            cache.comment = text
            return text
        case .filename:
            return post.attachment?.filename
        case .tripcode:
            return post.trip
        case .capcode:
            return post.capcode
        case .posterID:
            return post.posterID
        case .country:
            let parts = [post.countryName, post.country].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        case .flag:
            return post.flagName
        case .md5:
            return post.attachment?.md5
        case .fileSize:
            // Raw byte count; comparison operators are deliberately out of scope.
            return post.attachment.map { String($0.size) }
        case .dimensions:
            guard let attachment = post.attachment else { return nil }
            return "\(attachment.width)x\(attachment.height)"
        case .postNumber:
            return String(post.no.value)
        }
    }

    private func matches(_ entry: Compiled, value: String) -> Bool {
        switch entry.filter.match {
        case .keyword:
            return value.range(
                of: entry.filter.pattern,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil

        case .exact:
            return value.compare(
                entry.filter.pattern,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame

        case .regex:
            guard let expression = entry.expression else { return false }
            let haystack = value.count > Self.maximumHaystackLength
                ? String(value.prefix(Self.maximumHaystackLength))
                : value
            let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
            return expression.firstMatch(in: haystack, options: [], range: range) != nil
        }
    }

    // MARK: - Compilation

    /// Returns the compiled expression (nil for non-regex rules) and whether the
    /// rule is usable.
    static func compile(_ filter: ChanFilter) -> (NSRegularExpression?, Bool) {
        guard filter.match == .regex else { return (nil, true) }

        let trimmed = filter.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, false) }

        var source = trimmed
        var options: NSRegularExpression.Options = [.caseInsensitive]

        // `/pattern/flags` follows JavaScript semantics, where the flags are
        // authoritative: no `i` means case-sensitive.
        if source.hasPrefix("/"), let closing = source.lastIndex(of: "/"), closing != source.startIndex {
            let flags = String(source[source.index(after: closing)...])
            source = String(source[source.index(after: source.startIndex)..<closing])
            options = []
            if flags.contains("i") { options.insert(.caseInsensitive) }
            if flags.contains("m") { options.insert(.anchorsMatchLines) }
            if flags.contains("s") { options.insert(.dotMatchesLineSeparators) }
            if flags.contains("x") { options.insert(.allowCommentsAndWhitespace) }
        }

        guard !source.isEmpty, source.count <= maximumPatternLength else { return (nil, false) }

        do {
            return (try NSRegularExpression(pattern: source, options: options), true)
        } catch {
            return (nil, false)
        }
    }

    /// nil when the rule is usable, otherwise a message for the editor.
    public static func validate(_ filter: ChanFilter) -> String? {
        if filter.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a pattern to match."
        }
        if filter.fields.isEmpty {
            return "Pick at least one field to search."
        }
        if filter.match == .regex {
            let (_, isValid) = compile(filter)
            if !isValid { return "That regular expression is not valid." }
        }
        if filter.match == .exact, filter.fields.allSatisfy(\.requiresAttachment) {
            // Not an error, just a note-worthy combination; nothing to report.
            return nil
        }
        return nil
    }
}
