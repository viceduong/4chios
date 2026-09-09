import Foundation

/// A board as returned by `GET /boards.json`.
///
/// Decoded with `keyDecodingStrategy = .convertFromSnakeCase`, so property names
/// are camelCase and every field the API may omit is optional.
public struct Board: Codable, Hashable, Sendable, Identifiable {
    public var id: BoardID { board }

    public let board: BoardID
    public let title: String
    public let wsBoard: Bool?
    public let perPage: Int?
    public let pages: Int?
    public let bumpLimit: Int?
    public let imageLimit: Int?
    public let maxFilesize: Int?
    public let maxWebmFilesize: Int?
    public let maxWebmDuration: Int?
    public let maxCommentChars: Int?
    public let spoilers: Bool?
    public let customSpoilers: Int?
    public let userIds: Bool?
    public let countryFlags: Bool?
    public let cooldowns: Cooldowns?
    public let meta: Meta?

    public struct Cooldowns: Codable, Hashable, Sendable {
        public let threads: Int?
        public let replies: Int?
        public let images: Int?
    }

    public struct Meta: Codable, Hashable, Sendable {
        public let isArchived: Bool?
        public let isLocked: Bool?
    }

    // Convenience accessors with sane defaults.

    public var isWorkSafe: Bool { wsBoard ?? false }
    public var isArchived: Bool { meta?.isArchived ?? false }
    public var isLocked: Bool { meta?.isLocked ?? false }
    public var allowsImages: Bool { imageLimit.map { $0 != 0 } ?? true }
    public var threadCooldown: Int { cooldowns?.threads ?? 0 }
    public var replyCooldown: Int { cooldowns?.replies ?? 0 }
    public var imageCooldown: Int { cooldowns?.images ?? 0 }

    public init(
        board: BoardID,
        title: String,
        wsBoard: Bool? = nil,
        perPage: Int? = nil,
        pages: Int? = nil,
        bumpLimit: Int? = nil,
        imageLimit: Int? = nil,
        maxFilesize: Int? = nil,
        maxWebmFilesize: Int? = nil,
        maxWebmDuration: Int? = nil,
        maxCommentChars: Int? = nil,
        spoilers: Bool? = nil,
        customSpoilers: Int? = nil,
        userIds: Bool? = nil,
        countryFlags: Bool? = nil,
        cooldowns: Cooldowns? = nil,
        meta: Meta? = nil
    ) {
        self.board = board
        self.title = title
        self.wsBoard = wsBoard
        self.perPage = perPage
        self.pages = pages
        self.bumpLimit = bumpLimit
        self.imageLimit = imageLimit
        self.maxFilesize = maxFilesize
        self.maxWebmFilesize = maxWebmFilesize
        self.maxWebmDuration = maxWebmDuration
        self.maxCommentChars = maxCommentChars
        self.spoilers = spoilers
        self.customSpoilers = customSpoilers
        self.userIds = userIds
        self.countryFlags = countryFlags
        self.cooldowns = cooldowns
        self.meta = meta
    }
}

/// Envelope for `GET /boards.json`.
public struct BoardListResponse: Codable, Sendable {
    public let boards: [Board]
}

/// One page of `GET /{board}/catalog.json`.
public struct CatalogPage: Codable, Sendable {
    public let page: Int
    public let threads: [Post]
}

/// Envelope for `GET /{board}/thread/{op}.json`.
public struct ThreadResponse: Codable, Sendable {
    public let posts: [Post]
}

/// Envelope for `GET /{board}/thread/{op}-tail.json`.
public struct ThreadTailResponse: Codable, Sendable {
    public let tailId: PostNumber?
    public let tailSize: Int?
    public let posts: [Post]
}
