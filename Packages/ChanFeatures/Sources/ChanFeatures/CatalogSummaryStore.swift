import ChanAI
import ChanCore
import Foundation

/// Drives the "read this board" digest and caches the result per board.
@MainActor
public final class CatalogSummaryStore: ObservableObject {
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
    @Published public private(set) var summary: CatalogSummary?
    /// True when the catalog has changed since this digest was made.
    @Published public private(set) var isStale = false

    private let environment: AppEnvironment
    private let board: BoardID
    private var task: Task<Void, Never>?

    public init(board: BoardID, environment: AppEnvironment) {
        self.board = board
        self.environment = environment
    }

    public var isConfigured: Bool {
        environment.settings.isAIConfigured
    }

    /// One tap: show what we already have, otherwise read the board immediately.
    public func start(threads: [Post]) {
        loadCached(threads: threads)
        guard summary == nil || isStale else { return }
        summarize(threads: threads)
    }

    public func loadCached(threads: [Post]) {
        guard let json = try? environment.database.meta(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode(CatalogSummary.self, from: Data(json.utf8)) else {
            return
        }
        summary = decoded
        isStale = Set(decoded.coveredThreads) != Set(threads.map(\.no.value))
        phase = .ready
    }

    public func summarize(threads: [Post]) {
        cancel()

        let settings = environment.settings
        guard settings.isAIConfigured else {
            phase = .failed("Add a General Compute API key in Settings to read a board.")
            return
        }
        guard !threads.isEmpty else {
            phase = .failed("This board has no threads to read yet.")
            return
        }

        // A board digest is a snapshot; the caller hands us one so a later poll
        // cannot change the catalog mid-read.
        let snapshot = threads
        phase = .working("Reading \(snapshot.count) threads…")

        task = Task { [weak self] in
            guard let self else { return }

            let client = AIChatClient(configuration: settings.aiConfiguration)
            let summarizer = CatalogSummarizer(client: client)

            do {
                let result = try await summarizer.summarize(board: self.board, threads: snapshot) { status in
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
        try? environment.database.setMeta("", forKey: cacheKey)
        summary = nil
        isStale = false
        phase = .idle
    }

    /// Keyed by model too, so switching models does not show a digest the new one
    /// did not write.
    private var cacheKey: String {
        "catalogSummary.\(board.rawValue).\(environment.settings.aiModel)"
    }

    private func persist(_ summary: CatalogSummary) {
        guard let data = try? JSONEncoder().encode(summary),
              let json = String(data: data, encoding: .utf8) else { return }
        try? environment.database.setMeta(json, forKey: cacheKey)
    }
}
