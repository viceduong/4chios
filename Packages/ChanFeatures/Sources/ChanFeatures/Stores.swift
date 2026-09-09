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

    // MARK: - User state

    @Published public private(set) var isBookmarked = false
    @Published public private(set) var isWatched = false

    public func refreshUserState() {
        isBookmarked = (try? environment.database.isBookmarked(board: board, op: op)) ?? false
        isWatched = (try? environment.database.isWatched(board: board, op: op)) ?? false
    }

    public func toggleBookmark() {
        if isBookmarked {
            try? environment.database.removeBookmark(board: board, op: op)
        } else {
            try? environment.database.addBookmark(board: board, op: op)
        }
        refreshUserState()
    }

    public func toggleWatch() {
        if isWatched {
            try? environment.database.removeWatch(board: board, op: op)
        } else {
            let replies = posts.first(where: { $0.isOP })?.replies ?? 0
            try? environment.database.addWatch(board: board, op: op)
            try? environment.database.updateWatchProgress(board: board, op: op, replies: replies)
        }
        refreshUserState()
    }

    /// A snapshot of the OP, used by the saved list.
    public var opPost: Post? {
        posts.first(where: { $0.isOP })
    }
}

/// A thread reference resolved into displayable content for the saved list.
public struct SavedThread: Identifiable, Hashable, Sendable {
    public var id: String { "\(board.rawValue)/\(op.value)" }
    public let board: BoardID
    public let op: PostNumber
    public let title: String
    public let replies: Int
    public let images: Int
    public let addedAt: Date
    public let note: String?
    public let isWatched: Bool
    public let unreadReplies: Int
}

/// Bookmarks and watched threads, resolved against the cached posts.
@MainActor
public final class SavedStore: ObservableObject {
    @Published public private(set) var bookmarks: [SavedThread] = []
    @Published public private(set) var watched: [SavedThread] = []

    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public func load() {
        bookmarks = ((try? environment.database.bookmarks()) ?? []).map { bookmark in
            resolve(
                board: bookmark.board,
                op: bookmark.op,
                addedAt: bookmark.addedAt,
                note: bookmark.note,
                isWatched: false,
                lastSeenReply: nil
            )
        }

        watched = ((try? environment.database.watchedThreads()) ?? []).map { watch in
            resolve(
                board: watch.board,
                op: watch.op,
                addedAt: watch.addedAt,
                note: nil,
                isWatched: true,
                lastSeenReply: watch.lastSeenReply
            )
        }
    }

    public func remove(_ thread: SavedThread) {
        if thread.isWatched {
            try? environment.database.removeWatch(board: thread.board, op: thread.op)
        } else {
            try? environment.database.removeBookmark(board: thread.board, op: thread.op)
        }
        load()
    }

    private func resolve(
        board: BoardID,
        op: PostNumber,
        addedAt: Date,
        note: String?,
        isWatched: Bool,
        lastSeenReply: Int?
    ) -> SavedThread {
        let opPost = (try? environment.database.posts(board: board, op: op))?.first(where: { $0.isOP })
        let subject = opPost?.subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = PostHTMLParser.parse(opPost?.commentHTML ?? "").plainText
        let title = (subject?.isEmpty == false ? subject : nil)
            ?? (body.isEmpty ? "Thread #\(op.value)" : String(body.prefix(80)))

        let replies = opPost?.replies ?? 0
        return SavedThread(
            board: board,
            op: op,
            title: title,
            replies: replies,
            images: opPost?.images ?? 0,
            addedAt: addedAt,
            note: note,
            isWatched: isWatched,
            unreadReplies: max(0, replies - (lastSeenReply ?? 0))
        )
    }
}
