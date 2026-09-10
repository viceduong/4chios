import Foundation

/// Which part(s) of a post a rule is matched against.
///
/// Field selection is the core of 4chan-X's filter language (`type:name,comment`):
/// a rule is only as good as the scope it searches, and matching everything
/// against the whole post is what makes naive filters useless.
public enum ChanFilterField: String, Codable, CaseIterable, Sendable, Identifiable {
    case subject
    case name
    case comment
    case filename
    case tripcode
    case capcode
    /// The per-thread poster ID (`id`).
    case posterID
    case country
    case flag
    case md5
    case fileSize
    case dimensions
    case postNumber

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .subject: return "Subject"
        case .name: return "Name"
        case .comment: return "Comment"
        case .filename: return "Filename"
        case .tripcode: return "Tripcode"
        case .capcode: return "Capcode"
        case .posterID: return "Poster ID"
        case .country: return "Country"
        case .flag: return "Flag"
        case .md5: return "File MD5"
        case .fileSize: return "File size"
        case .dimensions: return "Dimensions"
        case .postNumber: return "Post number"
        }
    }

    /// Fields that only exist on posts carrying an attachment.
    public var requiresAttachment: Bool {
        switch self {
        case .filename, .md5, .fileSize, .dimensions: return true
        default: return false
        }
    }

    /// Values that are identifiers rather than prose, where substring matching
    /// is almost never what the user means.
    public var isIdentifier: Bool {
        switch self {
        case .posterID, .tripcode, .capcode, .md5, .postNumber: return true
        default: return false
        }
    }

    /// 4chan-X's default "General" scope.
    public static let standard: [ChanFilterField] = [.subject, .name, .comment, .filename]
}

/// How the pattern is interpreted.
public enum ChanFilterMatch: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Case-insensitive literal substring.
    case keyword
    /// Regular expression. Accepts `/pattern/flags` (JS semantics: no implicit
    /// `i`) or a bare pattern (case-insensitive by default).
    case regex
    /// Case-insensitive whole-string equality. 4chan-X uses this for MD5 and
    /// unique IDs instead of a regex, because substring matching on a hash is
    /// never what anyone wants.
    case exact

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .keyword: return "Keyword"
        case .regex: return "Regex"
        case .exact: return "Exact match"
        }
    }

    /// The mode to preselect for a given field selection.
    public static func suggested(for fields: [ChanFilterField]) -> ChanFilterMatch {
        fields.isEmpty ? .keyword : (fields.allSatisfy(\.isIdentifier) ? .exact : .keyword)
    }
}

/// What happens when a rule matches.
public enum ChanFilterAction: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Collapse the post into a one-line placeholder that can be expanded. Less
    /// destructive than hiding: the thread keeps its shape.
    case stub
    /// Hide the post entirely.
    case hidePost
    /// Hide the whole thread from the catalog (evaluated against the OP).
    case hideThread
    /// Mark the post as interesting.
    case highlight

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .stub: return "Collapse (stub)"
        case .hidePost: return "Hide post"
        case .hideThread: return "Hide thread"
        case .highlight: return "Highlight"
        }
    }
}

/// Where a rule applies.
///
/// `included`/`excluded` hold board ids and/or the group names `sfw` and `nsfw`,
/// mirroring 4chan-X's `boards:` and `exclude:` options.
public struct ChanBoardScope: Codable, Hashable, Sendable {
    public var included: [String]
    public var excluded: [String]

    public init(included: [String] = [], excluded: [String] = []) {
        self.included = included
        self.excluded = excluded
    }

    public static let global = ChanBoardScope()

    public var isGlobal: Bool {
        included.isEmpty && excluded.isEmpty
    }

    public func allows(board: BoardID, isWorkSafe: Bool) -> Bool {
        let id = board.rawValue.lowercased()

        if excluded.contains(id) { return false }
        if isWorkSafe, excluded.contains("sfw") { return false }
        if !isWorkSafe, excluded.contains("nsfw") { return false }

        guard !included.isEmpty else { return true }
        if included.contains(id) { return true }
        if isWorkSafe, included.contains("sfw") { return true }
        if !isWorkSafe, included.contains("nsfw") { return true }
        return false
    }

    /// Human-readable description for the rules list.
    public var summary: String {
        if isGlobal { return "all boards" }
        var parts: [String] = []
        if !included.isEmpty { parts.append(included.joined(separator: ", ")) }
        if !excluded.isEmpty { parts.append("except " + excluded.joined(separator: ", ")) }
        return parts.isEmpty ? "all boards" : parts.joined(separator: " ")
    }
}

/// A single user rule.
public struct ChanFilter: Codable, Hashable, Sendable, Identifiable {
    public var id: Int64
    /// Fields to search. A rule matches if **any** selected field matches.
    public var fields: [ChanFilterField]
    public var match: ChanFilterMatch
    public var pattern: String
    public var scope: ChanBoardScope
    public var action: ChanFilterAction
    public var enabled: Bool
    public var createdAt: Date

    public init(
        id: Int64 = 0,
        fields: [ChanFilterField] = ChanFilterField.standard,
        match: ChanFilterMatch = .keyword,
        pattern: String,
        scope: ChanBoardScope = .global,
        action: ChanFilterAction = .hidePost,
        enabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fields = fields
        self.match = match
        self.pattern = pattern
        self.scope = scope
        self.action = action
        self.enabled = enabled
        self.createdAt = createdAt
    }

    /// One-line description used by the rules list and the stub placeholder.
    public var summary: String {
        "\(match.label) \(pattern) in \(fields.map(\.label).joined(separator: ", "))"
    }
}
