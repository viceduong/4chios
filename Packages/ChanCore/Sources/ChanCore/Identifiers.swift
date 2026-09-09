import Foundation

/// A 4chan board identifier, e.g. `g`, `pol`, `wsg`.
///
/// Encoded as a bare string so it can be used directly in API paths and JSON payloads.
public struct BoardID: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: BoardID, rhs: BoardID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension BoardID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension BoardID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

/// A 4chan post number. Unique per board, monotonically increasing.
///
/// Encoded as a bare integer, matching the API.
public struct PostNumber: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public var description: String { String(value) }

    public static func < (lhs: PostNumber, rhs: PostNumber) -> Bool {
        lhs.value < rhs.value
    }
}

extension PostNumber: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension PostNumber: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(value)
    }
}
