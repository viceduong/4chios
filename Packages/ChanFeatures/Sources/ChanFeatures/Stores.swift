import ChanCore
import Foundation

/// Loads and caches the board list. Database first (instant), network second.
@MainActor
public final class BoardListStore: ObservableObject {
    @Published public private(set) var boards: [Board] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    private let environment: AppEnvironment
    private var hasLoaded = false

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let cached = try? environment.database.boards(), !cached.isEmpty {
            boards = cached
        }

        await refresh()
    }

    public func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await environment.client.boards()
            try? environment.database.save(fetched)
            boards = fetched
        } catch let error as ChanError {
            if boards.isEmpty { errorMessage = error.errorDescription }
        } catch {
            if boards.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    public func filtered(query: String) -> [Board] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return boards }
        return boards.filter {
            $0.board.rawValue.localizedCaseInsensitiveContains(trimmed)
                || $0.title.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

/// Loads a board's catalog: cached OPs immediately, then a network refresh.
@MainActor
public final class CatalogStore: ObservableObject {
    public let board: BoardID

    @Published public private(set) var threads: [Post] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var lastUpdated: Date?

    private let environment: AppEnvironment
    private var hasLoaded = false

    public init(board: BoardID, environment: AppEnvironment) {
        self.board = board
        self.environment = environment
    }

    public var filterEngine: ChanFilterEngine {
        let filters = (try? environment.database.filters()) ?? []
        return ChanFilterEngine(filters: filters)
    }

    public func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let cached = try? environment.database.catalog(board: board), !cached.isEmpty {
            threads = applyFilters(cached)
        }

        await refresh()
    }

    public func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await environment.client.catalog(board)
            try? environment.database.saveCatalog(board: board, posts: fetched)
            try? environment.database.pruneThreads(board: board, keeping: Set(fetched.map(\.no)))
            try? environment.database.markCatalogSynced(board: board)
            threads = applyFilters(fetched)
            lastUpdated = Date()
        } catch let error as ChanError {
            if threads.isEmpty { errorMessage = error.errorDescription }
        } catch {
            if threads.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func applyFilters(_ posts: [Post]) -> [Post] {
        let engine = filterEngine
        guard !engine.isEmpty else { return posts }
        return posts.filter { !engine.hidesThread($0, in: board) }
    }
}

/// Loads one thread: cached posts immediately, then the full network fetch.
@MainActor
public final class ThreadStore: ObservableObject {
    public let board: BoardID
    public let op: PostNumber

    @Published public private(set) var posts: [Post] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var didReachEnd = false

    private let environment: AppEnvironment
    private var hasLoaded = false

    public init(board: BoardID, op: PostNumber, environment: AppEnvironment) {
        self.board = board
        self.op = op
        self.environment = environment
    }

    public func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let cached = try? environment.database.posts(board: board, op: op), !cached.isEmpty {
            posts = cached
        }

        await refresh()
    }

    public func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await environment.client.thread(board, op: op)
            try? environment.database.saveThread(board: board, op: op, posts: fetched)
            posts = fetched
            didReachEnd = false
        } catch let error as ChanError {
            if case .gone = error {
                didReachEnd = true
                errorMessage = "This thread is archived or gone."
            } else if posts.isEmpty {
                errorMessage = error.errorDescription
            }
        } catch {
            if posts.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    /// Fetches only posts newer than what we have, using the tail endpoint.
    public func pollForNewPosts() async {
        guard !posts.isEmpty, !didReachEnd else { return }
        do {
            let tail = try await environment.client.tail(board, op: op)
            let known = Set(posts.map(\.no))
            let fresh = tail.posts.filter { !known.contains($0.no) }
            guard !fresh.isEmpty else { return }
            try? environment.database.appendTail(board: board, op: op, posts: fresh)
            posts.append(contentsOf: fresh)
        } catch let error as ChanError {
            if case .gone = error { didReachEnd = true }
        } catch {
            // Polling failures are silent; the next tick retries.
        }
    }

    public func post(number: PostNumber) -> Post? {
        posts.first { $0.no == number }
    }

    /// Records scroll progress so the thread can be resumed later.
    public func markRead(upTo number: PostNumber) throws {
        try environment.database.setLastRead(board: board, op: op, postNumber: number)
    }
}
