import Foundation

/// A web result the model used, surfaced as a tappable source.
public struct AISource: Codable, Sendable, Equatable, Identifiable {
    public var id: String { url }
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return url }
        return trimmed
    }
}

/// One completion, with whatever sources backed it.
public struct AIChatReply: Sendable, Equatable {
    public let text: String
    public let sources: [AISource]
    public let model: String
    public let usedWebSearch: Bool

    public init(text: String, sources: [AISource] = [], model: String, usedWebSearch: Bool = false) {
        self.text = text
        self.sources = sources
        self.model = model
        self.usedWebSearch = usedWebSearch
    }
}

/// Detects when a question is really a request for current information.
///
/// A deterministic check rather than a planning round-trip: it costs nothing,
/// adds no latency, and the user can always flip the search toggle by hand.
public enum SearchIntent {
    /// Phrases that mean "go look this up" rather than "read the thread".
    private static let triggers = [
        "search", "google", "look up", "lookup", "search for", "find out",
        "latest", "current", "currently", "today", "tonight", "yesterday",
        "this week", "this year", "news", "recent", "recently", "right now",
        "up to date", "up-to-date", "release date", "price of", "how much is",
        "what happened", "who won", "is it true that", "fact check", "fact-check",
    ]

    /// Phrases a model uses when it is out of date and would need the web.
    private static let escalationMarkers = [
        "as of my knowledge", "knowledge cutoff", "my training data",
        "i don't have access to real-time", "i do not have access to real-time",
        "cannot browse", "can't browse", "unable to browse",
        "i don't have up-to-date", "i do not have up-to-date",
        "no access to current", "no real-time",
    ]

    public static func requiresWeb(_ question: String) -> Bool {
        let text = question.lowercased()
        return triggers.contains { text.contains($0) }
    }

    /// True when a reply admits it cannot answer without live information, so
    /// the caller should retry the same question with search enabled.
    public static func needsEscalation(_ reply: String) -> Bool {
        let text = reply.lowercased()
        return escalationMarkers.contains { text.contains($0) }
    }
}
