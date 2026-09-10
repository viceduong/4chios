import Foundation

/// Where and how to talk to an OpenAI-compatible chat completions endpoint.
///
/// Defaults target General Compute, which serves `gemma-4-31B-it` (a multimodal
/// model: it accepts text and images) at `/v1/chat/completions`.
public struct AIConfiguration: Sendable, Equatable {
    public var baseURL: URL
    public var apiKey: String
    public var model: String
    /// This endpoint uses `max_tokens`, not `max_completion_tokens`.
    public var maximumTokens: Int
    public var temperature: Double

    public init(
        baseURL: URL = AIConfiguration.generalComputeBaseURL,
        apiKey: String = "",
        model: String = AIConfiguration.generalComputeModel,
        maximumTokens: Int = 1_200,
        temperature: Double = 0.3
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.maximumTokens = maximumTokens
        self.temperature = temperature
    }

    public static let generalComputeBaseURL = URL(string: "https://api.generalcompute.com/v1")!
    public static let generalComputeModel = "gemma-4-31B-it"

    /// General Compute's Gemma endpoint.
    public static let generalCompute = AIConfiguration()

    public var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var chatCompletionsURL: URL {
        baseURL.appendingPathComponent("chat/completions")
    }
}
