import ChanAPI
import ChanCore
import Foundation

/// Downloads a thread's media for offline viewing.
///
/// Deliberately explicit: text is cached automatically as you read, but media
/// can run to hundreds of megabytes, so it only happens when asked for and the
/// reader chooses what kind. Already-saved files are skipped, so an interrupted
/// run resumes by simply running again.
@MainActor
public final class MediaDownloader: ObservableObject {
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case all
        case photos
        case videos

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .all: return "Everything"
            case .photos: return "Photos and GIFs"
            case .videos: return "Videos only"
            }
        }

        func includes(_ kind: MediaKind) -> Bool {
            switch self {
            case .all: return true
            case .photos: return kind == .image || kind == .gif
            case .videos: return kind == .video
            }
        }
    }

    public struct Progress: Equatable {
        public var total = 0
        public var completed = 0
        public var failed = 0
        public var bytes = 0
        public var isRunning = false

        public var fraction: Double {
            total == 0 ? 0 : Double(completed + failed) / Double(total)
        }

        public var summary: String {
            if failed > 0 {
                return "\(completed) of \(total) saved, \(failed) failed"
            }
            return "\(completed) of \(total) saved"
        }
    }

    @Published public private(set) var progress = Progress()

    /// How many files are fetched at once. 4chan's API asks for one request a
    /// second, but media is served from a CDN; three at a time is quick without
    /// being rude.
    private static let batchSize = 3

    private var task: Task<Void, Never>?

    public init() {}

    public var isRunning: Bool { progress.isRunning }

    /// What a given kind of download would fetch, so the reader can decide
    /// before spending the space. Computed once when the menu opens rather than
    /// on every render, since it reads the database.
    public struct Plan: Identifiable, Sendable {
        public let kind: Kind
        public let count: Int
        public let bytes: Int

        public var id: String { kind.rawValue }
        public var isEmpty: Bool { count == 0 }
        public var label: String { "\(kind.label) - \(count) files, \(ChanFormat.bytes(bytes))" }
    }

    public func plans(board: BoardID, posts: [Post], environment: AppEnvironment) -> [Plan] {
        let alreadySaved = (try? environment.database.savedMediaTimestamps(board: board)) ?? []
        return Kind.allCases.map { kind in
            let pending = attachments(in: posts, kind: kind).filter { !alreadySaved.contains($0.tim) }
            return Plan(kind: kind, count: pending.count, bytes: pending.reduce(0) { $0 + $1.fsize })
        }
    }

    public func start(board: BoardID, posts: [Post], kind: Kind, environment: AppEnvironment) {
        cancel()

        let alreadySaved = (try? environment.database.savedMediaTimestamps(board: board)) ?? []
        let pending = attachments(in: posts, kind: kind).filter { !alreadySaved.contains($0.tim) }

        guard !pending.isEmpty else {
            progress = Progress()
            return
        }

        progress = Progress(total: pending.count, isRunning: true)

        task = Task { [weak self] in
            guard let self else { return }

            var index = 0
            while index < pending.count, !Task.isCancelled {
                let upper = min(index + Self.batchSize, pending.count)
                let batch = Array(pending[index..<upper])

                await withTaskGroup(of: (Int, Int, Bool).self) { group in
                    for attachment in batch {
                        group.addTask { await Self.fetch(attachment, board: board) }
                    }
                    for await (tim, bytes, ok) in group {
                        if Task.isCancelled { break }
                        if ok {
                            self.progress.completed += 1
                            self.progress.bytes += bytes
                            self.record(tim: tim, bytes: bytes, board: board, posts: posts, environment: environment)
                        } else {
                            self.progress.failed += 1
                        }
                    }
                }

                index = upper
            }

            self.progress.isRunning = false
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        progress.isRunning = false
    }

    // MARK: - Work

    private struct Pending {
        let tim: Int
        let ext: String
        let fsize: Int
        let filename: String
        let postNumber: PostNumber
    }

    private func attachments(in posts: [Post], kind: Kind) -> [Pending] {
        posts.compactMap { post -> Pending? in
            guard let attachment = post.attachment,
                  !attachment.isDeleted,
                  kind.includes(MediaKind(ext: attachment.ext)) else { return nil }
            return Pending(
                tim: attachment.tim,
                ext: attachment.ext,
                fsize: attachment.size,
                filename: attachment.filename,
                postNumber: post.no
            )
        }
    }

    /// Fetches one file to disk. Returns (tim, bytes, succeeded).
    private static func fetch(_ item: Pending, board: BoardID) async -> (Int, Int, Bool) {
        let url = ChanMediaURL.full(board: board, tim: item.tim, ext: item.ext)
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return (item.tim, 0, false)
            }
            let bytes = try SavedMediaStore.store(data, board: board, tim: item.tim, ext: item.ext)
            return (item.tim, bytes, true)
        } catch {
            return (item.tim, 0, false)
        }
    }

    private func record(
        tim: Int,
        bytes: Int,
        board: BoardID,
        posts: [Post],
        environment: AppEnvironment
    ) {
        guard let post = posts.first(where: { $0.attachment?.tim == tim }),
              let attachment = post.attachment else { return }
        try? environment.database.saveMediaRecord(
            SavedMediaRecord(
                board: board,
                tim: tim,
                ext: attachment.ext,
                postNumber: post.no,
                filename: attachment.filename,
                byteCount: bytes,
                savedAt: Date()
            )
        )
    }
}
