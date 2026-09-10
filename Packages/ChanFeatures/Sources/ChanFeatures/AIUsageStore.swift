import ChanAI
import Foundation

/// Local record of what the AI features have cost in tokens.
///
/// General Compute's API exposes token counts on every response but has no
/// billing endpoint — there is no way to ask it for a credit balance. So this
/// tracks usage on the device and shows an estimated spend where the endpoint
/// publishes a price, with a link to the dashboard for the real balance.
@MainActor
public final class AIUsageStore: ObservableObject {
    public struct ModelTotals: Codable, Equatable {
        public var promptTokens = 0
        public var completionTokens = 0
        public var totalTokens = 0
        public var requests = 0
    }

    public struct Snapshot: Codable, Equatable {
        public var totalTokens = 0
        public var promptTokens = 0
        public var completionTokens = 0
        public var requests = 0
        public var lastModel = ""
        public var lastUsedAt: Date?
        public var byModel: [String: ModelTotals] = [:]
    }

    @Published public private(set) var snapshot: Snapshot

    private let defaults: UserDefaults
    private static let storageKey = "ai.usage.snapshot"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = Snapshot()
        }
    }

    public func record(_ usage: AIUsage?, model: String) {
        guard let usage else { return }

        snapshot.totalTokens += usage.totalTokens
        snapshot.promptTokens += usage.promptTokens
        snapshot.completionTokens += usage.completionTokens
        snapshot.requests += 1
        snapshot.lastModel = model
        snapshot.lastUsedAt = Date()

        let key = model.lowercased()
        var totals = snapshot.byModel[key] ?? ModelTotals()
        totals.promptTokens += usage.promptTokens
        totals.completionTokens += usage.completionTokens
        totals.totalTokens += usage.totalTokens
        totals.requests += 1
        snapshot.byModel[key] = totals

        persist()
    }

    public func reset() {
        snapshot = Snapshot()
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// Estimated spend across the models this device used, or nil when none of
    /// them have a published price (Gemma, for instance, is unpriced).
    public var estimatedSpend: Double? {
        var total = 0.0
        var pricedAnything = false

        for (model, totals) in snapshot.byModel {
            let usage = AIUsage(
                promptTokens: totals.promptTokens,
                completionTokens: totals.completionTokens,
                totalTokens: totals.totalTokens
            )
            guard let cost = AIPricing.estimatedCost(usage, model: model) else { continue }
            total += cost
            pricedAnything = true
        }
        return pricedAnything ? total : nil
    }

    /// True when the model in use has no published price, so the UI can explain
    /// why there is no dollar figure.
    public var hasUnpricedUsage: Bool {
        snapshot.byModel.keys.contains { AIPricing.rate(for: $0) == nil }
    }

    public var formattedTotalTokens: String {
        snapshot.totalTokens.formatted()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
