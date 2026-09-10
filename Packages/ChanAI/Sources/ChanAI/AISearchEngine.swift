import Foundation

/// Which search backend OpenRouter's `web` plugin should use.
///
/// Pricing is **per request, not per result**, and each request includes up to
/// 10 results. Measured against the live API (see docs/AI-PROVIDERS.md):
/// two results and ten results cost the same plugin fee, so asking for fewer
/// results saves nothing and only weakens the answer.
public enum AISearchEngine: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Exa's "auto" method: keyword search plus embeddings. The plugin default.
    case exaAuto
    /// Parallel's fastest mode. English and Japanese only.
    case parallelTurbo
    /// Parallel's default mode, broad language support.
    case parallelBasic
    case perplexity

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .exaAuto: return "Exa Auto"
        case .parallelTurbo: return "Parallel Turbo"
        case .parallelBasic: return "Parallel Basic"
        case .perplexity: return "Perplexity"
        }
    }

    /// Per-request charge, as published by OpenRouter.
    public var costPerRequest: Double {
        switch self {
        case .exaAuto: return 0.007
        case .parallelTurbo: return 0.001
        case .parallelBasic: return 0.005
        case .perplexity: return 0.005
        }
    }

    public var costLabel: String {
        let perThousand = Int((costPerRequest * 1_000).rounded())
        return "$\(perThousand) per 1,000 searches"
    }

    public var detail: String {
        switch self {
        case .exaAuto:
            return "Best quality; combines keyword and embedding search."
        case .parallelTurbo:
            return "Seven times cheaper and faster, but English and Japanese only."
        case .parallelBasic:
            return "Parallel's default mode; broad language support."
        case .perplexity:
            return "Routed through Perplexity."
        }
    }

    /// Wire value for the plugin, or nil to let the provider pick its default.
    var engineParameter: String? {
        switch self {
        case .exaAuto: return nil
        case .parallelTurbo, .parallelBasic: return "parallel"
        case .perplexity: return "perplexity"
        }
    }

    var modeParameter: String? {
        switch self {
        case .exaAuto: return nil
        case .parallelTurbo: return "turbo"
        case .parallelBasic: return "basic"
        case .perplexity: return nil
        }
    }
}

/// The `plugins` entry sent to OpenRouter.
struct SearchPlugin: Encodable {
    let id: String
    let maxResults: Int
    let engine: String?
    let mode: String?

    enum CodingKeys: String, CodingKey {
        case id, engine, mode
        case maxResults = "max_results"
    }

    init(engine: AISearchEngine, maxResults: Int) {
        id = "web"
        self.maxResults = maxResults
        self.engine = engine.engineParameter
        mode = engine.modeParameter
    }
}
