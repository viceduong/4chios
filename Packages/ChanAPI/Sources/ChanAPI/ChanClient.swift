import ChanCore
import Foundation

/// The read-only 4chan API client.
///
/// Every request is rate-limited, conditionally cached, and decoded into
/// `ChanCore` models. No other layer is allowed to construct a 4chan URL.
public struct ChanClient: Sendable {
    private let transport: ChanTransport
    private let rateLimiter: ChanRateLimiter
    private let cache: ChanCacheStore?

    public init(
        transport: ChanTransport = URLSessionTransport(),
        rateLimiter: ChanRateLimiter = ChanRateLimiter(),
        cache: ChanCacheStore? = ChanMemoryCache()
    ) {
        self.transport = transport
        self.rateLimiter = rateLimiter
        self.cache = cache
    }

    // MARK: - Endpoints

    /// Every board with its limits and flags.
    public func boards() async throws -> [Board] {
        let data = try await data(for: .boards, priority: .userInitiated)
        return try decode(BoardListResponse.self, from: data).boards
    }

    /// All OP posts for a board, flattened across catalog pages.
    public func catalog(_ board: BoardID) async throws -> [Post] {
        let data = try await data(for: .catalog(board), priority: .userInitiated)
        return try decode([CatalogPage].self, from: data).flatMap(\.threads)
    }

    /// One index page.
    public func index(_ board: BoardID, page: Int) async throws -> [Post] {
        let data = try await data(for: .index(board, page: page), priority: .userInitiated)
        struct Page: Decodable { let threads: [Post] }
        return try decode(Page.self, from: data).threads
    }

    /// A full thread.
    public func thread(_ board: BoardID, op: PostNumber) async throws -> [Post] {
        let data = try await data(for: .thread(board, op: op), priority: .userInitiated)
        return try decode(ThreadResponse.self, from: data).posts
    }

    /// Only the posts after the client's last known `tail_id`.
    public func tail(_ board: BoardID, op: PostNumber) async throws -> ThreadTailResponse {
        let data = try await data(for: .threadTail(board, op: op), priority: .threadPoll)
        return try decode(ThreadTailResponse.self, from: data)
    }

    /// Archived thread numbers for a board.
    public func archive(_ board: BoardID) async throws -> [PostNumber] {
        let data = try await data(for: .archive(board), priority: .background)
        return try decode([Int].self, from: data).map(PostNumber.init)
    }

    // MARK: - Transport

    private func data(for endpoint: ChanEndpoint, priority: ChanRateLimiter.Priority) async throws -> Data {
        let url = endpoint.url
        var headers = ["Accept": "application/json"]
        var cached: ChanCacheEntry?

        if let cache {
            cached = await cache.entry(for: url)
            if let etag = cached?.etag { headers["If-None-Match"] = etag }
            if let modified = cached?.lastModified { headers["If-Modified-Since"] = modified }
        }

        await rateLimiter.acquire(priority)

        let response = try await transport.send(ChanHTTPRequest(url: url, headers: headers))

        if response.isNotModified {
            guard let cached else { throw ChanError.notModified }
            return cached.data
        }

        guard response.isSuccess else {
            switch response.statusCode {
            case 404: throw ChanError.gone
            case 429: throw ChanError.rateLimited(retryAfter: 5)
            default: throw ChanError.http(status: response.statusCode, endpoint: endpoint.path)
            }
        }

        if let cache {
            await cache.store(
                ChanCacheEntry(
                    etag: response.header("ETag"),
                    lastModified: response.header("Last-Modified"),
                    data: response.body
                ),
                for: url
            )
        }

        return response.body
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            throw ChanError.decoding(String(describing: error))
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
