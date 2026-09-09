import Foundation

/// A cached response body plus the validators needed to revalidate it.
public struct ChanCacheEntry: Sendable {
    public var etag: String?
    public var lastModified: String?
    public var data: Data
    public var storedAt: Date

    public init(etag: String? = nil, lastModified: String? = nil, data: Data, storedAt: Date = Date()) {
        self.etag = etag
        self.lastModified = lastModified
        self.data = data
        self.storedAt = storedAt
    }
}

/// Storage for conditional-GET validators. The disk-backed implementation lands
/// in M4; `ChanMemoryCache` covers the session.
public protocol ChanCacheStore: Sendable {
    func entry(for url: URL) async -> ChanCacheEntry?
    func store(_ entry: ChanCacheEntry, for url: URL) async
    func removeAll() async
}

public actor ChanMemoryCache: ChanCacheStore {
    private var entries: [URL: ChanCacheEntry] = [:]
    private let limit: Int

    public init(limit: Int = 256) {
        self.limit = limit
    }

    public func entry(for url: URL) -> ChanCacheEntry? {
        entries[url]
    }

    public func store(_ entry: ChanCacheEntry, for url: URL) {
        entries[url] = entry
        if entries.count > limit {
            let overflow = entries.count - limit
            let oldest = entries.sorted { $0.value.storedAt < $1.value.storedAt }.prefix(overflow)
            for (url, _) in oldest { entries[url] = nil }
        }
    }

    public func removeAll() {
        entries.removeAll()
    }
}
