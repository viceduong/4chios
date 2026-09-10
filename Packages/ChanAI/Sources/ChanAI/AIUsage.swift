import Foundation

/// Token accounting for one request, as reported by the endpoint.
public struct AIUsage: Codable, Sendable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }

    public static func + (lhs: AIUsage, rhs: AIUsage) -> AIUsage {
        AIUsage(
            promptTokens: lhs.promptTokens + rhs.promptTokens,
            completionTokens: lhs.completionTokens + rhs.completionTokens,
            totalTokens: lhs.totalTokens + rhs.totalTokens
        )
    }

    public static func += (lhs: inout AIUsage, rhs: AIUsage) {
        lhs = lhs + rhs
    }

    public static let zero = AIUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0)
}

/// Published per-model prices, in USD per million tokens.
///
/// Taken from General Compute's model table. Models it does not price (Gemma,
/// for one) are deliberately absent rather than guessed at: the UI reports
/// tokens for those and no dollar figure.
public enum AIPricing {
    public struct Rate: Sendable, Equatable {
        public let inputPerMillion: Double
        public let outputPerMillion: Double
    }

    private static let rates: [String: Rate] = [
        "minimax-m2.7": Rate(inputPerMillion: 0.28, outputPerMillion: 1.20),
        "deepseek-v3.2": Rate(inputPerMillion: 0.25, outputPerMillion: 0.38),
        "deepseek-v3.1": Rate(inputPerMillion: 0.21, outputPerMillion: 0.79),
        "gpt-oss-120b": Rate(inputPerMillion: 0.21, outputPerMillion: 0.79),
    ]

    /// nil when the endpoint does not publish a price for this model.
    public static func rate(for model: String) -> Rate? {
        rates[model.lowercased()]
    }

    public static func estimatedCost(_ usage: AIUsage, model: String) -> Double? {
        guard let rate = rate(for: model) else { return nil }
        let input = Double(usage.promptTokens) / 1_000_000 * rate.inputPerMillion
        let output = Double(usage.completionTokens) / 1_000_000 * rate.outputPerMillion
        return input + output
    }

    /// Compact currency for very small amounts.
    public static func format(_ amount: Double) -> String {
        if amount <= 0 { return "$0.00" }
        if amount < 0.01 { return String(format: "$%.4f", amount) }
        return String(format: "$%.2f", amount)
    }
}
