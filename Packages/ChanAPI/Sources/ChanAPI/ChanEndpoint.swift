import ChanCore
import Foundation

/// The hosts that serve the 4chan read API and its assets.
public enum ChanHost: String, CaseIterable, Sendable {
    /// JSON API — boards, catalogs, threads, archives.
    case api = "https://a.4cdn.org"
    /// Full media and thumbnails.
    case media = "https://i.4cdn.org"
    /// Static assets: spoiler placeholders, flags, icons.
    case staticContent = "https://s.4cdn.org"
    /// Posting endpoint (multipart form uploads).
    case posting = "https://sys.4channel.org"
    /// Captcha challenge + Pass authentication.
    case captcha = "https://sys.4chan.org"

    public var url: URL {
        // Force-unwrap is safe: these are compile-time constants.
        URL(string: rawValue)!
    }
}

/// A read-only API endpoint. URL construction lives here so it can be unit-tested
/// without touching the network.
public enum ChanEndpoint: Equatable, Sendable {
    /// `GET /boards.json` — every board with its per-board limits and flags.
    case boards
    /// `GET /{board}/catalog.json` — all OPs with a few trailing replies.
    case catalog(BoardID)
    /// `GET /{board}/{page}.json` — one index page.
    case index(BoardID, page: Int)
    /// `GET /{board}/thread/{op}.json` — the whole thread.
    case thread(BoardID, op: PostNumber)
    /// `GET /{board}/thread/{op}-tail.json` — only the posts after `tail_id`.
    case threadTail(BoardID, op: PostNumber)
    /// `GET /{board}/archive.json` — archived thread numbers.
    case archive(BoardID)

    public var host: ChanHost {
        .api
    }

    public var path: String {
        switch self {
        case .boards:
            return "/boards.json"
        case let .catalog(board):
            return "/\(board.rawValue)/catalog.json"
        case let .index(board, page):
            return "/\(board.rawValue)/\(page).json"
        case let .thread(board, op):
            return "/\(board.rawValue)/thread/\(op.value).json"
        case let .threadTail(board, op):
            return "/\(board.rawValue)/thread/\(op.value)-tail.json"
        case let .archive(board):
            return "/\(board.rawValue)/archive.json"
        }
    }

    public var url: URL {
        URL(string: path, relativeTo: host.url)!.absoluteURL
    }
}
