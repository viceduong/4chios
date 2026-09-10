import Foundation

/// How the catalog is ordered.
///
/// The API returns threads in bump order, but a reader looking for a specific
/// kind of thread — the busiest, the newest, the most image-heavy — should not
/// have to scroll the whole catalog to find it.
public enum CatalogSort: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Pinned threads first, then most recently bumped. The server's order.
    case bumpOrder
    /// Newest thread first, by creation time.
    case newest
    /// Oldest thread first, by creation time.
    case oldest
    /// Most replies first.
    case mostReplies
    /// Most attachments first.
    case mostImages

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .bumpOrder: return "Bump order"
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .mostReplies: return "Most replies"
        case .mostImages: return "Most images"
        }
    }

    public var systemImage: String {
        switch self {
        case .bumpOrder: return "flame"
        case .newest: return "arrow.up"
        case .oldest: return "arrow.down"
        case .mostReplies: return "bubble.left.and.bubble.right"
        case .mostImages: return "photo.on.rectangle"
        }
    }

    /// Orders a catalog. Ties always break on post number descending, so the
    /// result is deterministic and a live refresh cannot shuffle equal threads.
    public func sorted(_ posts: [Post]) -> [Post] {
        switch self {
        case .bumpOrder:
            return posts.sorted { lhs, rhs in
                let lhsSticky = lhs.isSticky ?? false
                let rhsSticky = rhs.isSticky ?? false
                if lhsSticky != rhsSticky { return lhsSticky }

                let lhsBump = lhs.lastModified ?? lhs.time
                let rhsBump = rhs.lastModified ?? rhs.time
                if lhsBump != rhsBump { return lhsBump > rhsBump }
                return lhs.no.value > rhs.no.value
            }

        case .newest:
            return posts.sorted { lhs, rhs in
                if lhs.time != rhs.time { return lhs.time > rhs.time }
                return lhs.no.value > rhs.no.value
            }

        case .oldest:
            return posts.sorted { lhs, rhs in
                if lhs.time != rhs.time { return lhs.time < rhs.time }
                return lhs.no.value < rhs.no.value
            }

        case .mostReplies:
            return posts.sorted { lhs, rhs in
                let lhsReplies = lhs.replies ?? 0
                let rhsReplies = rhs.replies ?? 0
                if lhsReplies != rhsReplies { return lhsReplies > rhsReplies }
                return lhs.no.value > rhs.no.value
            }

        case .mostImages:
            return posts.sorted { lhs, rhs in
                let lhsImages = lhs.images ?? 0
                let rhsImages = rhs.images ?? 0
                if lhsImages != rhsImages { return lhsImages > rhsImages }
                return lhs.no.value > rhs.no.value
            }
        }
    }
}
