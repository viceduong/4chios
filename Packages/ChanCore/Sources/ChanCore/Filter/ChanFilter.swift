import Foundation

/// What a rule looks at.
public enum ChanFilterKind: String, Codable, CaseIterable, Sendable {
    case keyword
    case regex
    case posterID
    case tripcode
    case capcode
    case filename

    public var label: String {
        switch self {
        case .keyword: return "Keyword"
        case .regex: return "Regex"
        case .posterID: return "Poster ID"
        case .tripcode: return "Tripcode"
        case .capcode: return "Capcode"
        case .filename: return "Filename"
        }
    }
}

/// What happens when a rule matches.
public enum ChanFilterAction: String, Codable, CaseIterable, Sendable {
    /// Hide the whole thread in the catalog (evaluated against the OP).
    case hideThread
    /// Hide just the post.
    case hidePost
    /// Mark the post as interesting.
    case highlight

    public var label: String {
        switch self {
        case .hideThread: return "Hide thread"
        case .hidePost: return "Hide post"
        case .highlight: return "Highlight"
        }
    }
}

/// A single user rule. `board == nil` means it applies everywhere.
public struct ChanFilter: Codable, Hashable, Sendable, Identifiable {
    public let id: Int64
    public let board: BoardID?
    public let kind: ChanFilterKind
    public let pattern: String
    public let action: ChanFilterAction
    public let enabled: Bool
    public let createdAt: Date

    public init(
        id: Int64 = 0,
        board: BoardID? = nil,
        kind: ChanFilterKind,
        pattern: String,
        action: ChanFilterAction,
        enabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.board = board
        self.kind = kind
        self.pattern = pattern
        self.action = action
        self.enabled = enabled
        self.createdAt = createdAt
    }
}

/// The combined verdict for one post.
public struct ChanFilterDecision: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let hide = ChanFilterDecision(rawValue: 1 << 0)
    public static let highlight = ChanFilterDecision(rawValue: 1 << 1)
}

/// Evaluates the user's rules against posts. Pure logic — no UI, no storage.
public struct ChanFilterEngine: Sendable {
    private struct Rule: Sendable {
        let filter: ChanFilter
        let regex: NSRegularExpression?
    }

    private let rules: [Rule]

    public init(filters: [ChanFilter]) {
        rules = filters
            .filter(\.enabled)
            .filter { !$0.pattern.isEmpty }
            .map { filter in
                let regex = filter.kind == .regex
                    ? try? NSRegularExpression(pattern: filter.pattern, options: [.caseInsensitive])
                    : nil
                return Rule(filter: filter, regex: regex)
            }
    }

    public var isEmpty: Bool { rules.isEmpty }

    /// Evaluates a post. The plain text of the body is parsed once and shared
    /// across all rules, so a thread with 20 rules still parses each post once.
    public func decision(for post: Post, in board: BoardID) -> ChanFilterDecision {
        guard !rules.isEmpty else { return [] }

        var decision: ChanFilterDecision = []
        var parsedText: String?

        for rule in rules {
            if let scope = rule.filter.board, scope != board { continue }

            let matches: Bool
            switch rule.filter.kind {
            case .keyword:
                matches = haystack(post, text: &parsedText)
                    .range(of: rule.filter.pattern, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            case .regex:
                guard let regex = rule.regex else { continue }
                let subject = haystack(post, text: &parsedText)
                matches = regex.firstMatch(in: subject, range: NSRange(subject.startIndex..., in: subject)) != nil
            case .posterID:
                matches = post.posterID?.caseInsensitiveCompare(rule.filter.pattern) == .orderedSame
            case .tripcode:
                matches = post.trip?.caseInsensitiveCompare(rule.filter.pattern) == .orderedSame
            case .capcode:
                matches = post.capcode?.caseInsensitiveCompare(rule.filter.pattern) == .orderedSame
            case .filename:
                matches = (post.attachment?.filename ?? "")
                    .range(of: rule.filter.pattern, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }

            guard matches else { continue }

            switch rule.filter.action {
            case .hidePost, .hideThread: decision.insert(.hide)
            case .highlight: decision.insert(.highlight)
            }
        }

        return decision
    }

    /// True when the OP of a thread should be hidden from the catalog.
    public func hidesThread(_ op: Post, in board: BoardID) -> Bool {
        decision(for: op, in: board).contains(.hide)
    }

    private func haystack(_ post: Post, text: inout String?) -> String {
        if text == nil {
            var parts: [String] = []
            if let subject = post.subject { parts.append(subject) }
            parts.append(PostHTMLParser.parse(post.commentHTML ?? "").plainText)
            if let name = post.name { parts.append(name) }
            text = parts.joined(separator: "\n")
        }
        return text ?? ""
    }
}
