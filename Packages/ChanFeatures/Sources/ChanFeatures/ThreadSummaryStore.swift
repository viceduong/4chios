import ChanAI
import ChanCore
import Foundation

/// Drives the "summarize this thread" flow and caches the result per thread.
@MainActor
public final class ThreadSummaryStore: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case working(String)
        case ready
        case failed(String)

        public var isWorking: Bool {
            if case .working = self { return true }
            return false
        }
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var summary: ThreadSummary?
    /// True when the cached summary covers fewer posts than the thread now has.
    @Published public private(set) var isStale = false
    @Published public var style: SummaryStyle = .bullets

    private let environment: AppEnvironment
    private let board: BoardID
    private let op: PostNumber
    private var task: Task<Void, Never>?

    public init(board: BoardID, op: PostNumber, environment: AppEnvironment) {
        self.board = board
        self.op = op
        self.environment = environment
    }

    public var isConfigured: Bool {
        environment.settings.isAIConfigured
    }

    /// One tap on the summary button: show what we already have, otherwise ask
    /// the model immediately.
    public func start(posts: [Post]) {
        loadCached(posts: posts)
        guard summary == nil || isStale else { return }
        summarize(posts: posts)
    }

    /// Shows a previously generated summary for this thread, if one exists.
    public func loadCached(posts: [Post]) {
        let model = environment.settings.aiModel
        guard let cached = try? environment.database.summary(board: board, op: op, model: model),
              let decoded = try? JSONDecoder().decode(ThreadSummary.self, from: Data(cached.json.utf8)) else {
            return
        }
        summary = decoded
        isStale = cached.postCount != posts.count
        phase = .ready
    }

    public func summarize(posts: [Post]) {
        cancel()

        let settings = environment.settings
        guard settings.isAIConfigured else {
            phase = .failed("Add a General Compute API key in Settings to summarize threads.")
            return
        }
        guard !posts.isEmpty else {
            phase = .failed("There is nothing to summarize yet.")
            return
        }

        let snapshot = posts.sorted { $0.no < $1.no }
        phase = .working("Reading \(snapshot.count) posts…")

        task = Task { [weak self] in
            guard let self else { return }

            let client = AIChatClient(configuration: settings.aiConfiguration)
            let summarizer = ThreadSummarizer(
                client: client,
                options: ThreadSummarizer.Options(style: self.style)
            )

            do {
                let result = try await summarizer.summarize(
                    board: self.board,
                    op: self.op,
                    posts: snapshot
                ) { status in
                    Task { @MainActor [weak self] in
                        guard let self, self.phase.isWorking else { return }
                        self.phase = .working(status)
                    }
                }

                if Task.isCancelled { return }
                self.summary = result
                self.isStale = false
                self.phase = .ready
                self.persist(result)
                self.environment.usage.record(result.usage, model: result.model)
            } catch let error as AIChatError {
                self.phase = .failed(error.userMessage)
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    public func clear() {
        cancel()
        try? environment.database.deleteSummary(board: board, op: op)
        summary = nil
        isStale = false
        phase = .idle
    }

    private func persist(_ summary: ThreadSummary) {
        guard let data = try? JSONEncoder().encode(summary),
              let json = String(data: data, encoding: .utf8) else { return }
        try? environment.database.saveSummary(
            board: board,
            op: op,
            model: summary.model,
            postCount: summary.postCount,
            json: json,
            createdAt: summary.generatedAt
        )
    }
}
