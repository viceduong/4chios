import Foundation

/// Where and how to talk to an OpenAI-compatible chat completions endpoint.
///
/// Defaults target General Compute, which serves `gemma-4-31B-it` at
/// `/v1/chat/completions`. An optional second endpoint can be supplied for
/// turns that need live web results.
public struct AIConfiguration: Sendable, Equatable {
    /// A search-capable endpoint, e.g. OpenRouter with its `web` plugin.
    public struct SearchConfiguration: Sendable, Equatable {
        public var baseURL: URL
        public var apiKey: String
        public var model: String
        public var maximumResults: Int

        public init(
            baseURL: URL = AIConfiguration.openRouterBaseURL,
            apiKey: String = "",
            model: String = AIConfiguration.openRouterSearchModel,
            maximumResults: Int = 4
        ) {
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.model = model
            self.maximumResults = maximumResults
        }

        public var isConfigured: Bool {
            !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    public var baseURL: URL
    public var apiKey: String
    public var model: String
    /// This endpoint family uses `max_tokens`, not `max_completion_tokens`.
    public var maximumTokens: Int
    public var temperature: Double
    /// Nil when no search endpoint is configured; search stays unavailable.
    public var search: SearchConfiguration?

    public init(
        baseURL: URL = AIConfiguration.generalComputeBaseURL,
        apiKey: String = "",
        model: String = AIConfiguration.generalComputeModel,
        maximumTokens: Int = 1_200,
        temperature: Double = 0.3,
        search: SearchConfiguration? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.maximumTokens = maximumTokens
        self.temperature = temperature
        self.search = search
    }

    public static let generalComputeBaseURL = URL(string: "https://api.generalcompute.com/v1")!
    public static let generalComputeModel = "gemma-4-31B-it"

    public static let openRouterBaseURL = URL(string: "https://openrouter.ai/api/v1")!
    /// Cheap, fast, and reliable with the `web` plugin.
    public static let openRouterSearchModel = "google/gemini-2.5-flash-lite"

    /// General Compute's Gemma endpoint.
    public static let generalCompute = AIConfiguration()

    public var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
