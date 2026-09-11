import ChanAI
import ChanCore
import Foundation

/// Drives the conversation about a thread and persists it per thread.
@MainActor
public final class ThreadChatStore: ObservableObject {
    @Published public private(set) var turns: [ChatTurn] = []
    @Published public private(set) var isAsking = false
    @Published public private(set) var errorMessage: String?
    /// Forces the next question through web search.
    @Published public var useWebSearch = false

    private let environment: AppEnvironment
    private let board: BoardID
    private let op: PostNumber

    private var session: ThreadChatSession?
    private var contextSignature = ""
    private var hasLoaded = false
    private var task: Task<Void, Never>?

    public init(board: BoardID, op: PostNumber, environment: AppEnvironment) {
        self.board = board
        self.op = op
        self.environment = environment
    }

    public var canSearch: Bool {
        environment.settings.canSearchTheWeb
    }

    /// True when search only runs if the reader asks for it.
    ///
    /// With a direct provider or the server tool, search is always offered and
    /// costs nothing unless the model uses it, so there is nothing to toggle.
    /// The plugin is the one path that needs opting into, because it searches on
    /// every message it is attached to.
    public var searchNeedsOptIn: Bool {
        let configuration = environment.settings.aiConfiguration
        guard configuration.directSearch?.isConfigured != true else { return false }
        return configuration.search?.mode == .plugin
    }

    public var isConfigured: Bool {
        environment.settings.isAIConfigured
    }

    /// Rebuilds the grounding context when the thread or summary changes.
    /// Cheap enough to call on every appear; it only rebuilds when the inputs do.
    public func prepare(posts: [Post], summary: ThreadSummary?) {
        loadIfNeeded()

        let signature = "\(posts.count):\(posts.last?.no.value ?? 0):\(summary?.text.count ?? 0)"
        guard signature != contextSignature else { return }
        contextSignature = signature

        session = ThreadChatSession(
            client: AIChatClient(configuration: environment.settings.aiConfiguration),
            posts: posts,
            summary: summary
        )
    }

    /// `forceSearch` overrides the model's judgement for one message, so the
    /// reader does not have to phrase the question to get a lookup.
    public func ask(_ question: String, forceSearch: Bool = false) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAsking else { return }
        guard isConfigured else {
            errorMessage = "Add an AI API key in Settings to chat about this thread."
            return
        }
        guard let session else {
            errorMessage = "This thread is still loading."
            return
        }

        errorMessage = nil
        let history = turns
        turns.append(.user(trimmed))
        isAsking = true
        persist()

        let searching = forceSearch || useWebSearch

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let reply = try await session.ask(trimmed, history: history, useWebSearch: searching)
                if Task.isCancelled { return }
                self.turns.append(reply)
                self.persist()
                self.environment.usage.record(
                    reply.usage,
                    model: reply.model,
                    searchCostUSD: reply.searchCostUSD
                )
            } catch let error as AIChatError {
                if case .cancelled = error { } else { self.errorMessage = error.userMessage }
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isAsking = false
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        isAsking = false
    }

    public func clear() {
        cancel()
        turns = []
        errorMessage = nil
        try? environment.database.deleteChat(board: board, op: op)
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true

        guard let cached = try? environment.database.chat(board: board, op: op),
              let turns = try? JSONDecoder().decode([ChatTurn].self, from: Data(cached.json.utf8)) else {
            return
        }
        self.turns = turns
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(turns),
              let json = String(data: data, encoding: .utf8) else { return }
        try? environment.database.saveChat(board: board, op: op, json: json)
    }
}
